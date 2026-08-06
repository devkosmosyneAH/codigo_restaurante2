import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:restaurant_app/Presentation/core/database/database_helper.dart';
import 'package:restaurant_app/Presentation/core/sync/sync_cloud_service.dart';
import 'package:restaurant_app/Presentation/core/sync/sync_manager.dart';
import 'package:restaurant_app/Presentation/core/sync/sync_record.dart'
    show SyncOperation;
import 'package:restaurant_app/Presentation/core/tenant/tenant_context.dart';

/// Orquestador de sincronizacion hibrida (SQLite local + Realtime Database).
///
/// Mantiene:
/// - Push incremental de pendientes locales hacia la nube.
/// - Pull por polling desde Realtime Database hacia SQLite.
/// - Comportamiento offline-safe cuando no hay conectividad.
class HybridSyncOrchestrator {
  HybridSyncOrchestrator({
    required SyncManager syncManager,
    required SyncCloudService cloudService,
    required DatabaseHelper dbHelper,
    required TenantContext tenantContext,
    Connectivity? connectivity,
    Future<void> Function()? beforePushHook,
  }) : _syncManager = syncManager,
       _cloudService = cloudService,
       _dbHelper = dbHelper,
       _tenantContext = tenantContext,
       _connectivity = connectivity ?? Connectivity(),
       _beforePushHook = beforePushHook;

  // La sincronización de cambios locales se dispara por evento. Este pulso
  // solo revisa cambios hechos desde otro dispositivo y evita lecturas
  // frecuentes para conservar el uso gratuito de Firebase.
  static const Duration _pulseInterval = Duration(minutes: 5);
  // La disponibilidad es el unico dato del menu que bloquea una venta. Su
  // feed es angosto y puntual, por eso puede refrescarse sin sondear las
  // demas colecciones operativas cada pocos segundos.
  static const Duration _availabilityPulseInterval = Duration(seconds: 20);
  static const Duration _localChangeDebounce = Duration(milliseconds: 700);
  static const Duration _tombstoneRetention = Duration(days: 30);
  // Purging requires downloading every synchronized collection. Tombstones
  // already remain visible for 30 days, so doing this from every device twice
  // a day wastes bandwidth without improving consistency.
  static const Duration _tombstonePurgeInterval = Duration(days: 7);
  static const int _pushBatchSize = 100;

  static const List<String> _realtimeTables = [
    'categorias',
    'productos',
    'variantes',
    'pedidos',
    'pedido_items',
    'mesas',
    'llamados_mesero',
    'cotizaciones',
    'cotizacion_items',
    'reservaciones',
    'clientes',
    'ventas',
    'usuarios',
    'public_config',
    'public_gallery_images',
  ];

  final SyncManager _syncManager;
  final SyncCloudService _cloudService;
  final DatabaseHelper _dbHelper;
  final TenantContext _tenantContext;
  final Connectivity _connectivity;
  final Future<void> Function()? _beforePushHook;

  final Map<String, Set<String>> _tableColumnsCache = {};
  final Set<String> _menuBootstrapCheckedTenants = <String>{};
  final StreamController<MenuChangeEvent> _menuChangesController =
      StreamController<MenuChangeEvent>.broadcast();

  Timer? _pulseTimer;
  Timer? _availabilityPulseTimer;
  Timer? _localChangeTimer;
  StreamSubscription<dynamic>? _connectivitySub;
  StreamSubscription<void>? _pendingChangesSub;

  bool _started = false;
  bool _online = false;
  bool _syncInProgress = false;
  bool _availabilityPullInProgress = false;
  bool _cloudSyncEnabled = true;
  DateTime? _lastTombstonePurgeAt;

  /// Eventos locales emitidos solo despues de que SQLite confirmo el cambio.
  /// La UI no necesita volver a consultar categorias ni variantes para pintar
  /// una disponibilidad que ya conoce por ID.
  Stream<MenuChangeEvent> get menuChanges => _menuChangesController.stream;

  /// Fuerza un ciclo de sincronizacion en este momento.
  ///
  /// Si la orquestación aún no está iniciada, la inicia para que una acción
  /// explícita del administrador no se quede únicamente en SQLite.
  Future<void> syncNow({String reason = 'manual'}) async {
    // Una escritura explícita desde el administrador debe poder recuperar
    // una sesión cuyo sincronizador no alcanzó a iniciarse durante el arranque.
    if (!_started) {
      await start();
    }
    if (!_started) return;

    // Connectivity puede reportar `none` temporalmente al iniciar la web o
    // el escritorio. Para una acción explícita intentamos la escritura y
    // dejamos que HTTP determine si realmente hay conexión.
    if (!_online) _online = true;
    await _runCycle(reason: reason, rethrowErrors: true);
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _cloudSyncEnabled = _cloudService.isCloudSyncSupportedPlatform;

    if (!_cloudSyncEnabled) {
      return;
    }

    try {
      await _refreshConnectivity();
    } catch (_) {
      _online = true;
    }

    try {
      _connectivitySub = _connectivity.onConnectivityChanged.listen((event) {
        final wasOnline = _online;
        _online = _hasConnectivity(event);
        if (!wasOnline && _online) {
          unawaited(_runCycle(reason: 'connectivity-restored'));
        }
      });
    } catch (_) {
      _connectivitySub = null;
    }

    _pendingChangesSub = _syncManager.onPendingChanges.listen((_) {
      if (!_online) return;
      _scheduleLocalChangeSync();
    });

    _pulseTimer = Timer.periodic(
      _pulseInterval,
      (_) => unawaited(_runCycle(reason: 'pulse')),
    );

    await _runCycle(reason: 'startup');
    await _pullAvailabilityChanges();
    _availabilityPulseTimer = Timer.periodic(
      _availabilityPulseInterval,
      (_) => unawaited(_pullAvailabilityChanges()),
    );
  }

  Future<void> stop() async {
    _pulseTimer?.cancel();
    _pulseTimer = null;

    _availabilityPulseTimer?.cancel();
    _availabilityPulseTimer = null;

    _localChangeTimer?.cancel();
    _localChangeTimer = null;

    await _connectivitySub?.cancel();
    _connectivitySub = null;

    await _pendingChangesSub?.cancel();
    _pendingChangesSub = null;

    _started = false;
  }

  Future<void> _runCycle({
    required String reason,
    bool rethrowErrors = false,
  }) async {
    if (!_started || !_cloudSyncEnabled || _syncInProgress) return;
    if (!_online) return;

    _syncInProgress = true;
    try {
      await _cloudService.ensureAvailable();

      final tenantId = _tenantContext.restaurantId.trim();
      final shouldPullRemote = reason != 'local-change';
      if (tenantId.isNotEmpty && shouldPullRemote) {
        await _queueLocalMenuIfCloudIsEmpty(tenantId: tenantId);
        await _pullRemoteChanges(tenantId: tenantId);
        await _purgeExpiredTombstones(tenantId: tenantId);
      }

      final beforePushHook = _beforePushHook;
      if (beforePushHook != null) {
        try {
          await beforePushHook();
        } catch (_) {
          // No interrumpe push cloud si falla una tarea auxiliar local.
        }
      }

      await _pushPendingRecords();
    } catch (error, stackTrace) {
      // Si la nube falla (auth/config/transitorio), mantenemos modo local.
      debugPrint('SYNC_CYCLE_ERROR [$reason] $error');
      debugPrintStack(stackTrace: stackTrace);
      if (rethrowErrors) rethrow;
    } finally {
      _syncInProgress = false;
    }
  }

  /// Migra el menú que ya existe en SQLite cuando la colección remota todavía
  /// no tiene productos. Esto cubre instalaciones anteriores a Firebase
  /// como fuente de verdad y evita exigir que el administrador edite cada
  /// producto manualmente.
  Future<void> _queueLocalMenuIfCloudIsEmpty({required String tenantId}) async {
    // This is a one-time migration guard, not a periodic health check. Once
    // the remote menu is known to exist (or local rows have been queued),
    // normal CRUD sync keeps it current. Repeating the full `productos` read
    // on each pulse is especially expensive for the public catalog.
    if (!_menuBootstrapCheckedTenants.add(tenantId)) return;

    try {
      final remoteProducts = await _cloudService.listCollection(
        restaurantId: tenantId,
        collection: 'productos',
      );
      if (remoteProducts.isNotEmpty) {
        // Aprovecha la lectura completa que ya hacia el bootstrap para
        // completar, una sola vez por sesion, el espejo angosto de productos
        // creados antes de esta mejora.
        await _cloudService.completarDisponibilidadFaltante(
          restaurantId: tenantId,
          productos: remoteProducts,
        );
        return;
      }

      for (final table in const ['categorias', 'productos', 'variantes']) {
        final rows = table == 'variantes'
            ? await _dbHelper.rawQuery(
                '''
                SELECT v.*
                FROM variantes v
                INNER JOIN productos p ON p.id = v.producto_id
                WHERE p.restaurant_id = ?
                ''',
                [tenantId],
              )
            : await _dbHelper.query(
                table,
                where: 'restaurant_id = ?',
                whereArgs: [tenantId],
              );
        for (final row in rows) {
          final recordId = row['id']?.toString().trim();
          if (recordId == null || recordId.isEmpty) continue;
          await _syncManager.registrarOperacion(
            tabla: table,
            registroId: recordId,
            operacion: SyncOperation.insert,
            restaurantId: tenantId,
            datos: Map<String, dynamic>.from(row),
          );
        }
      }
    } catch (_) {
      // Do not cache a failed availability check; a later pulse can retry it.
      _menuBootstrapCheckedTenants.remove(tenantId);
      rethrow;
    }
  }

  void _scheduleLocalChangeSync() {
    _localChangeTimer?.cancel();
    _localChangeTimer = Timer(_localChangeDebounce, () {
      unawaited(_runCycle(reason: 'local-change'));
    });
  }

  Future<void> _pushPendingRecords() async {
    final pendientes = await _syncManager.obtenerPendientesParaEnvio(
      limit: _pushBatchSize,
    );
    final failures = <String>[];

    for (final record in pendientes) {
      try {
        await _cloudService.pushRecord(record);
        await _syncManager.marcarSincronizado(record.id);
        await _syncManager.registrarAuditoria(
          direction: 'push',
          status: 'success',
          tabla: record.tabla,
          registroId: record.registroId,
          restaurantId: record.restaurantId,
          syncRecordId: record.id,
        );
      } catch (error, stackTrace) {
        debugPrint(
          'SYNC_PUSH_ERROR [${record.tabla}/${record.registroId}] $error',
        );
        debugPrintStack(stackTrace: stackTrace);
        await _syncManager.incrementarIntentos(record.id);
        await _syncManager.registrarAuditoria(
          direction: 'push',
          status: 'error',
          tabla: record.tabla,
          registroId: record.registroId,
          restaurantId: record.restaurantId,
          syncRecordId: record.id,
          detail: error.toString(),
        );
        failures.add('${record.tabla}/${record.registroId}: $error');
      }
    }

    if (failures.isNotEmpty) {
      throw StateError(
        'Fallaron ${failures.length} operaciones de sincronizacion. '
        'Primera causa: ${failures.first}',
      );
    }
  }

  Future<void> _pullRemoteChanges({required String tenantId}) async {
    for (final table in _realtimeTables) {
      try {
        final cursor = await _loadLocalRealtimeCursor(
          table: table,
          tenantId: tenantId,
        );

        final remoteDocs = await _cloudService.listCollection(
          restaurantId: tenantId,
          collection: table,
          updatedAfter: cursor,
        );

        if (remoteDocs.isEmpty) continue;

        for (final entry in remoteDocs.entries) {
          await _applyRemoteUpsert(
            table: table,
            tenantId: tenantId,
            docId: entry.key,
            rawData: entry.value,
          );
        }
      } catch (error) {
        await _syncManager.registrarAuditoria(
          direction: 'pull',
          status: 'stream_error',
          tabla: table,
          registroId: '*',
          restaurantId: tenantId,
          detail: error.toString(),
        );
      }
    }
  }

  /// Aplica solamente `id -> disponible` desde el nodo angosto. No registra
  /// operaciones locales ni hace un pull de productos completo; asi el evento
  /// puede pintar la UI sin reiniciar el menu ni aumentar las lecturas RTDB.
  Future<void> _pullAvailabilityChanges() async {
    if (!_started ||
        !_cloudSyncEnabled ||
        !_online ||
        _availabilityPullInProgress) {
      return;
    }

    final tenantId = _tenantContext.restaurantId.trim();
    if (tenantId.isEmpty) return;

    _availabilityPullInProgress = true;
    try {
      final cursor = await _loadAvailabilityCursor(tenantId);
      final updates = await _cloudService.pullDisponibilidad(
        restaurantId: tenantId,
        updatedAtInclusive: cursor,
      );
      if (updates.isEmpty) return;

      final pendingFiltered = <String, DisponibilidadUpdate>{};
      for (final entry in updates.entries) {
        final pending = await _syncManager.obtenerPendiente(
          tabla: 'productos',
          registroId: entry.key,
        );
        if (pending == null) {
          pendingFiltered[entry.key] = entry.value;
        }
      }

      final applied = <String, bool>{};
      if (pendingFiltered.isNotEmpty) {
        await _dbHelper.transaction((txn) async {
          for (final entry in pendingFiltered.entries) {
            final update = entry.value;
            final data = <String, dynamic>{
              'disponible': update.disponible ? 1 : 0,
              'disponibilidad_updated_at': update.updatedAt,
            };
            // La version viene del mismo write atomico del producto. Mantener
            // su updated_at evita que el pull completo posterior lo revierta.
            if (DateTime.tryParse(update.version) != null) {
              data['updated_at'] = update.version;
            }
            final count = await txn.update(
              'productos',
              data,
              where:
                  'id = ? AND restaurant_id = ? '
                  'AND disponibilidad_updated_at < ?',
              whereArgs: [entry.key, tenantId, update.updatedAt],
            );
            if (count > 0) applied[entry.key] = update.disponible;
          }
        });
      }

      final newestCursor = updates.values
          .map((update) => update.updatedAt)
          .reduce((a, b) => a > b ? a : b);
      await _saveAvailabilityCursor(tenantId, newestCursor);

      if (applied.isNotEmpty) {
        _menuChangesController.add(
          MenuChangeEvent.disponibilidad(
            restaurantId: tenantId,
            disponibilidadPorProducto: applied,
          ),
        );
      }
    } catch (error, stackTrace) {
      // No auditar cada pulso fallido: hacerlo convertiría una caida de red en
      // escrituras locales permanentes. El siguiente pulso reintentara.
      debugPrint('SYNC_AVAILABILITY_PULL_ERROR $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _availabilityPullInProgress = false;
    }
  }

  Future<int?> _loadAvailabilityCursor(String tenantId) async {
    final rows = await _dbHelper.query(
      'sync_state',
      where: 'restaurant_id = ? AND state_key = ?',
      whereArgs: [tenantId, 'disponibilidad_cursor_v1'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return int.tryParse(rows.first['value']?.toString() ?? '');
  }

  Future<void> _saveAvailabilityCursor(String tenantId, int cursor) async {
    await _dbHelper.insert('sync_state', {
      'restaurant_id': tenantId,
      'state_key': 'disponibilidad_cursor_v1',
      'value': cursor.toString(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _applyRemoteUpsert({
    required String table,
    required String tenantId,
    required String docId,
    required Map<String, dynamic> rawData,
  }) async {
    final payload = await _sanitizePayload(
      table: table,
      tenantId: tenantId,
      docId: docId,
      rawData: rawData,
    );
    if (payload.isEmpty) {
      await _syncManager.registrarAuditoria(
        direction: 'pull',
        status: 'ignored',
        tabla: table,
        registroId: docId,
        restaurantId: tenantId,
        detail: 'empty_payload',
      );
      return;
    }

    final registroId = table == 'clientes'
        ? _registroIdClientes(tenantId: tenantId, docId: docId, data: payload)
        : docId;

    final pendingRecord = await _syncManager.obtenerPendiente(
      tabla: table,
      registroId: registroId,
    );

    // Si existe cambio local pendiente, solo aceptamos el eco remoto del
    // mismo sync_record para evitar pisar cambios locales.
    if (pendingRecord != null) {
      final remoteRecordId = _extractRemoteSyncRecordId(rawData);
      final isLocalEcho =
          remoteRecordId != null && remoteRecordId == pendingRecord.id;

      if (!isLocalEcho) {
        await _syncManager.registrarAuditoria(
          direction: 'pull',
          status: 'deferred',
          tabla: table,
          registroId: registroId,
          restaurantId: tenantId,
          syncRecordId: pendingRecord.id,
          detail: 'local_pending_wins',
        );
        return;
      }
    }

    if (_isTombstone(rawData)) {
      await _applyRemoteTombstone(
        table: table,
        tenantId: tenantId,
        docId: docId,
        registroId: registroId,
        payload: payload,
        rawData: rawData,
      );
      return;
    }

    final local = await _loadLocalRow(
      table: table,
      tenantId: tenantId,
      docId: docId,
      payload: payload,
    );

    if (!_shouldApplyRemote(local: local, remotePayload: payload)) {
      await _syncManager.registrarAuditoria(
        direction: 'pull',
        status: 'stale_remote',
        tabla: table,
        registroId: registroId,
        restaurantId: tenantId,
      );
      return;
    }

    await _upsertLocalRow(
      table: table,
      tenantId: tenantId,
      docId: docId,
      payload: payload,
      localRow: local,
    );

    await _syncManager.registrarAuditoria(
      direction: 'pull',
      status: 'applied',
      tabla: table,
      registroId: registroId,
      restaurantId: tenantId,
      syncRecordId: _extractRemoteSyncRecordId(rawData),
    );
  }

  Future<void> _applyRemoteTombstone({
    required String table,
    required String tenantId,
    required String docId,
    required String registroId,
    required Map<String, dynamic> payload,
    required Map<String, dynamic> rawData,
  }) async {
    final local = await _loadLocalRow(
      table: table,
      tenantId: tenantId,
      docId: docId,
      payload: payload,
    );
    final deletedAt = _parseDateTime(rawData['deleted_at']);
    final localUpdatedAt = local == null
        ? null
        : _parseDateTime(local['updated_at']) ??
              _parseDateTime(local['created_at']);
    if (deletedAt != null &&
        localUpdatedAt != null &&
        deletedAt.isBefore(localUpdatedAt)) {
      return;
    }

    final lookup = await _lookupForRow(
      table: table,
      tenantId: tenantId,
      docId: docId,
      payload: payload,
    );
    if (lookup != null && local != null) {
      final columns = await _getTableColumns(table);
      if (columns.contains('activo')) {
        await _dbHelper.update(
          table,
          {
            'activo': 0,
            if (columns.contains('updated_at'))
              'updated_at': (deletedAt ?? DateTime.now()).toIso8601String(),
          },
          where: lookup.where,
          whereArgs: lookup.whereArgs,
        );
      } else {
        await _dbHelper.delete(
          table,
          where: lookup.where,
          whereArgs: lookup.whereArgs,
        );
      }
    }
    await _syncManager.registrarAuditoria(
      direction: 'pull',
      status: 'deleted',
      tabla: table,
      registroId: registroId,
      restaurantId: tenantId,
      syncRecordId: _extractRemoteSyncRecordId(rawData),
    );
  }

  Future<void> _purgeExpiredTombstones({required String tenantId}) async {
    final lastPurge = _lastTombstonePurgeAt;
    if (lastPurge != null &&
        DateTime.now().difference(lastPurge) < _tombstonePurgeInterval) {
      return;
    }
    final cutoff = DateTime.now().toUtc().subtract(_tombstoneRetention);
    for (final table in _realtimeTables) {
      try {
        final documents = await _cloudService.listCollection(
          restaurantId: tenantId,
          collection: table,
        );
        for (final entry in documents.entries) {
          final deletedAt = _parseDateTime(entry.value['deleted_at']);
          if (deletedAt != null && deletedAt.isBefore(cutoff)) {
            await _cloudService.purgeDocument(
              restaurantId: tenantId,
              collection: table,
              documentId: entry.key,
            );
          }
        }
      } catch (_) {
        // Purge is best-effort; failures must not block operational sync.
      }
    }
    _lastTombstonePurgeAt = DateTime.now();
  }

  Future<Map<String, dynamic>?> _loadLocalRow({
    required String table,
    required String tenantId,
    required String docId,
    required Map<String, dynamic> payload,
  }) async {
    final lookup = await _lookupForRow(
      table: table,
      tenantId: tenantId,
      docId: docId,
      payload: payload,
    );
    if (lookup == null) return null;

    final rows = await _dbHelper.query(
      table,
      where: lookup.where,
      whereArgs: lookup.whereArgs,
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> _upsertLocalRow({
    required String table,
    required String tenantId,
    required String docId,
    required Map<String, dynamic> payload,
    required Map<String, dynamic>? localRow,
  }) async {
    if (table == 'clientes') {
      final cedula = _extractCedula(docId: docId, data: payload);
      if (cedula == null) return;

      final data = <String, dynamic>{...payload};
      final nowIso = DateTime.now().toIso8601String();

      data['restaurant_id'] = tenantId;
      data['cedula'] = cedula;
      data['nombre'] = (data['nombre']?.toString().trim().isNotEmpty ?? false)
          ? data['nombre']
          : (data['nombres']?.toString().trim().isNotEmpty ?? false)
          ? data['nombres']
          : 'Cliente';
      data['nombres'] = (data['nombres']?.toString().trim().isNotEmpty ?? false)
          ? data['nombres']
          : data['nombre'];
      data['activo'] = data['activo'] ?? 1;
      data['estado'] = data['estado'] ?? 1;
      data['created_at'] = data['created_at'] ?? nowIso;
      data['updated_at'] = data['updated_at'] ?? nowIso;

      if (localRow == null) {
        await _dbHelper.insert(table, data);
      } else {
        await _dbHelper.update(
          table,
          data,
          where: 'restaurant_id = ? AND cedula = ?',
          whereArgs: [tenantId, cedula],
        );
      }
      return;
    }

    final lookup = await _lookupForRow(
      table: table,
      tenantId: tenantId,
      docId: docId,
      payload: payload,
    );
    if (lookup == null) return;

    if (localRow == null) {
      await _dbHelper.insert(table, payload);
    } else {
      await _dbHelper.update(
        table,
        payload,
        where: lookup.where,
        whereArgs: lookup.whereArgs,
      );
    }
  }

  Future<_TableLookup?> _lookupForRow({
    required String table,
    required String tenantId,
    required String docId,
    Map<String, dynamic>? payload,
  }) async {
    if (table == 'clientes') {
      final cedula = _extractCedula(docId: docId, data: payload);
      if (cedula == null) return null;
      return _TableLookup(
        where: 'restaurant_id = ? AND cedula = ?',
        whereArgs: [tenantId, cedula],
      );
    }

    final columns = await _getTableColumns(table);
    if (columns.contains('id')) {
      return _TableLookup(where: 'id = ?', whereArgs: [docId]);
    }

    if (columns.contains('restaurant_id')) {
      return _TableLookup(where: 'restaurant_id = ?', whereArgs: [tenantId]);
    }

    return null;
  }

  Future<Map<String, dynamic>> _sanitizePayload({
    required String table,
    required String tenantId,
    required String docId,
    required Map<String, dynamic> rawData,
  }) async {
    final allowedColumns = await _getTableColumns(table);

    final payload = <String, dynamic>{};
    for (final entry in rawData.entries) {
      if (entry.key == '_sync') continue;
      if (!allowedColumns.contains(entry.key)) continue;
      payload[entry.key] = _normalizeValue(entry.value);
    }

    final nowIso = DateTime.now().toIso8601String();

    if (allowedColumns.contains('restaurant_id')) {
      payload['restaurant_id'] = tenantId;
    }

    if (table != 'clientes' && allowedColumns.contains('id')) {
      payload['id'] = payload['id'] ?? docId;
    }

    if (allowedColumns.contains('created_at')) {
      final createdAt = _toIsoString(payload['created_at']);
      payload['created_at'] = createdAt ?? nowIso;
    }

    if (allowedColumns.contains('updated_at')) {
      final updatedAt = _toIsoString(payload['updated_at']);
      payload['updated_at'] = updatedAt ?? nowIso;
    }

    if (table == 'clientes') {
      final cedula = _extractCedula(docId: docId, data: payload);
      if (cedula == null) return const {};
      payload.remove('id_cliente');
      payload['cedula'] = cedula;
    }

    return payload;
  }

  bool _isTombstone(Map<String, dynamic> rawData) {
    final value = rawData['deleted_at'];
    return value is String && DateTime.tryParse(value) != null;
  }

  bool _shouldApplyRemote({
    required Map<String, dynamic>? local,
    required Map<String, dynamic> remotePayload,
  }) {
    if (local == null) return true;

    final remoteTs =
        _parseDateTime(remotePayload['updated_at']) ??
        _parseDateTime(remotePayload['created_at']);
    final localTs =
        _parseDateTime(local['updated_at']) ??
        _parseDateTime(local['created_at']);

    if (remoteTs == null || localTs == null) {
      return true;
    }

    return !remoteTs.isBefore(localTs);
  }

  Future<String?> _loadLocalRealtimeCursor({
    required String table,
    required String tenantId,
  }) async {
    final columns = await _getTableColumns(table);
    if (!columns.contains('updated_at')) return null;

    List<Map<String, dynamic>> rows;
    if (columns.contains('restaurant_id')) {
      rows = await _dbHelper.rawQuery(
        'SELECT MAX(updated_at) as max_updated_at FROM $table WHERE restaurant_id = ?',
        [tenantId],
      );
    } else {
      rows = await _dbHelper.rawQuery(
        'SELECT MAX(updated_at) as max_updated_at FROM $table',
      );
    }

    if (rows.isEmpty) return null;
    final cursor = _toIsoString(rows.first['max_updated_at']);
    if (cursor == null || cursor.isEmpty) return null;
    return cursor;
  }

  Future<Set<String>> _getTableColumns(String table) async {
    final cached = _tableColumnsCache[table];
    if (cached != null) return cached;

    final rows = await _dbHelper.rawQuery('PRAGMA table_info($table)');
    final columns = rows
        .map((row) => (row['name'] as String?) ?? '')
        .where((name) => name.isNotEmpty)
        .toSet();

    _tableColumnsCache[table] = columns;
    return columns;
  }

  Future<void> _refreshConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    _online = _hasConnectivity(result);
  }

  bool _hasConnectivity(dynamic event) {
    if (event is ConnectivityResult) {
      return event != ConnectivityResult.none;
    }
    if (event is List<ConnectivityResult>) {
      return event.any((item) => item != ConnectivityResult.none);
    }
    if (event is Iterable) {
      return event.any(
        (item) => item is ConnectivityResult && item != ConnectivityResult.none,
      );
    }

    return true;
  }

  dynamic _normalizeValue(dynamic value) {
    if (value is DateTime) return value.toIso8601String();
    if (value is bool) return value ? 1 : 0;
    if (value is Map || value is List) return jsonEncode(value);
    return value;
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return null;
  }

  String? _toIsoString(dynamic value) {
    final dt = _parseDateTime(value);
    return dt?.toIso8601String();
  }

  String _registroIdClientes({
    required String tenantId,
    required String docId,
    required Map<String, dynamic> data,
  }) {
    final cedula = _extractCedula(docId: docId, data: data);
    if (cedula == null) return docId;
    return '$tenantId:$cedula';
  }

  String? _extractRemoteSyncRecordId(Map<String, dynamic> rawData) {
    final sync = rawData['_sync'];
    if (sync is! Map) return null;

    final recordId = sync['record_id'];
    if (recordId == null) return null;
    final normalized = recordId.toString().trim();
    return normalized.isEmpty ? null : normalized;
  }

  String? _extractCedula({required String docId, Map<String, dynamic>? data}) {
    final fromPayload = data?['cedula']?.toString().trim();
    if (fromPayload != null && fromPayload.isNotEmpty) {
      return fromPayload;
    }

    final separator = docId.indexOf(':');
    if (separator < 0 || separator >= docId.length - 1) {
      return null;
    }

    final candidate = docId.substring(separator + 1).trim();
    return candidate.isEmpty ? null : candidate;
  }
}

class _TableLookup {
  _TableLookup({required this.where, required this.whereArgs});

  final String where;
  final List<Object?> whereArgs;
}

/// Cambio del menu que puede aplicarse en memoria sin hacer una recarga SQL.
class MenuChangeEvent {
  const MenuChangeEvent.disponibilidad({
    required this.restaurantId,
    required this.disponibilidadPorProducto,
  });

  final String restaurantId;
  final Map<String, bool> disponibilidadPorProducto;
}
