import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:restaurant_app/Presentation/core/database/database_helper.dart';
import 'package:restaurant_app/Presentation/core/sync/hybrid_sync_orchestrator.dart';
import 'package:restaurant_app/Presentation/core/sync/sync_cloud_service.dart';
import 'package:restaurant_app/Presentation/core/sync/sync_manager.dart';
import 'package:restaurant_app/Presentation/core/sync/sync_record.dart';
import 'package:restaurant_app/Presentation/core/tenant/tenant_context.dart';

class _RecordingBackend implements SyncCloudBackend {
  int setCalls = 0;
  int productoConDisponibilidadCalls = 0;
  int disponibilidadBatchCalls = 0;
  int auditCalls = 0;
  String? latestAuditRecordId;
  final List<({String collection, String? updatedAfter})> collectionReads = [];
  Map<String, DisponibilidadUpdate> disponibilidad = {};
  Map<String, dynamic>? lastDisponibilidadProducto;
  Map<String, Map<String, dynamic>>? lastDisponibilidadBatch;

  @override
  Future<void> deleteDocument({
    required String restaurantId,
    required String collection,
    required String documentId,
  }) async {}

  @override
  Future<void> ensureAvailable() async {}

  @override
  Future<Map<String, Map<String, dynamic>>> listCollection({
    required String restaurantId,
    required String collection,
    String? updatedAfter,
  }) async {
    collectionReads.add((collection: collection, updatedAfter: updatedAfter));
    return const {};
  }

  @override
  Future<Map<String, DisponibilidadUpdate>> listDisponibilidad({
    required String restaurantId,
    int? updatedAtInclusive,
  }) async => disponibilidad;

  @override
  Future<void> setProductoConDisponibilidad({
    required String restaurantId,
    required String productoId,
    required Map<String, dynamic> producto,
    required bool mergeProducto,
    required Map<String, dynamic> disponibilidad,
  }) async {
    productoConDisponibilidadCalls++;
    lastDisponibilidadProducto = disponibilidad;
  }

  @override
  Future<void> setDisponibilidadBatch({
    required String restaurantId,
    required Map<String, Map<String, dynamic>> updates,
  }) async {
    disponibilidadBatchCalls++;
    lastDisponibilidadBatch = updates;
  }

  @override
  Object availabilityTimestamp() => 1723000000;

  @override
  Object serverTimestamp() => 'server-time';

  @override
  Future<void> setDocument({
    required String restaurantId,
    required String collection,
    required String documentId,
    required Map<String, dynamic> data,
    required bool merge,
  }) async {
    setCalls++;
  }

  @override
  Future<void> writeAudit({
    required String recordId,
    required Map<String, dynamic> data,
  }) async {
    auditCalls++;
    latestAuditRecordId = recordId;
  }
}

class _MockDatabaseHelper extends Mock implements DatabaseHelper {}

class _MockSyncManager extends Mock implements SyncManager {}

class _MockConnectivity extends Mock implements Connectivity {}

SyncRecord _record({String id = 'sync-1'}) {
  return SyncRecord(
    id: id,
    tabla: 'ventas',
    registroId: 'venta-1',
    operacion: SyncOperation.insert,
    restaurantId: 'la_pena_001',
    datos: {'id': 'venta-1', 'total': 12.5},
    createdAt: DateTime.utc(2026, 8, 5),
  );
}

SyncRecord _productoRecord({
  String id = 'sync-producto-1',
  bool disponible = false,
}) {
  return SyncRecord(
    id: id,
    tabla: 'productos',
    registroId: 'producto-1',
    operacion: SyncOperation.update,
    restaurantId: 'la_pena_001',
    datos: {
      'id': 'producto-1',
      'restaurant_id': 'la_pena_001',
      'nombre': 'Producto de prueba',
      'precio': 10.0,
      'disponible': disponible ? 1 : 0,
      'activo': 1,
      'updated_at': '2026-08-06T12:00:00.000Z',
    },
    createdAt: DateTime.utc(2026, 8, 6),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sync push keeps a bounded remote support status', () async {
    final backend = _RecordingBackend();
    final service = SyncCloudService(
      backend: backend,
      enforcePlatformSupport: false,
    );

    await service.pushRecord(_record());

    expect(backend.setCalls, 1);
    expect(backend.auditCalls, 1);
    expect(backend.latestAuditRecordId, 'la_pena_001_latest');
  });

  test('remote support status is throttled within its audit window', () async {
    final backend = _RecordingBackend();
    final service = SyncCloudService(
      backend: backend,
      enforcePlatformSupport: false,
    );

    await service.pushRecord(_record(id: 'sync-1'));
    await service.pushRecord(_record(id: 'sync-2'));

    expect(backend.setCalls, 2);
    expect(backend.auditCalls, 1);
  });

  test(
    'product sync atomically mirrors the narrow availability payload',
    () async {
      final backend = _RecordingBackend();
      final service = SyncCloudService(
        backend: backend,
        enforcePlatformSupport: false,
      );

      await service.pushRecord(_productoRecord());

      expect(backend.productoConDisponibilidadCalls, 1);
      expect(backend.setCalls, 0);
      expect(backend.lastDisponibilidadProducto?['d'], isFalse);
      expect(
        backend.lastDisponibilidadProducto?['v'],
        '2026-08-06T12:00:00.000Z',
      );
    },
  );

  test(
    'availability bootstrap only writes product IDs missing from the feed',
    () async {
      final backend = _RecordingBackend()
        ..disponibilidad = {
          'producto-existente': const DisponibilidadUpdate(
            productoId: 'producto-existente',
            disponible: true,
            updatedAt: 1723000000,
            version: '2026-08-06T12:00:00.000Z',
          ),
        };
      final service = SyncCloudService(
        backend: backend,
        enforcePlatformSupport: false,
      );

      await service.completarDisponibilidadFaltante(
        restaurantId: 'la_pena_001',
        productos: {
          'producto-existente': {'disponible': 1, 'activo': 1},
          'producto-faltante': {
            'disponible': 0,
            'activo': 1,
            'updated_at': '2026-08-06T12:00:00.000Z',
          },
        },
      );

      expect(backend.disponibilidadBatchCalls, 1);
      expect(
        backend.lastDisponibilidadBatch?.keys,
        contains('producto-faltante'),
      );
      expect(backend.lastDisponibilidadBatch, hasLength(1));
      expect(
        backend.lastDisponibilidadBatch?['producto-faltante']?['d'],
        isFalse,
      );
    },
  );

  test('long sessions do not rerun the menu bootstrap check', () async {
    final backend = _RecordingBackend();
    final db = _MockDatabaseHelper();
    final syncManager = _MockSyncManager();
    final connectivity = _MockConnectivity();
    final cloudService = SyncCloudService(
      backend: backend,
      enforcePlatformSupport: false,
    );

    when(
      () => db.query(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
        orderBy: any(named: 'orderBy'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((_) async => []);
    when(() => db.rawQuery(any(), any())).thenAnswer((invocation) async {
      final sql = invocation.positionalArguments.first.toString();
      if (sql.startsWith('PRAGMA table_info')) {
        return const [
          {'name': 'id'},
          {'name': 'restaurant_id'},
          {'name': 'updated_at'},
        ];
      }
      if (sql.startsWith('SELECT MAX(updated_at)')) {
        return const [
          {'max_updated_at': '2026-08-05T00:00:00.000Z'},
        ];
      }
      return const [];
    });
    when(
      () => syncManager.obtenerPendientesParaEnvio(limit: 100),
    ).thenAnswer((_) async => []);
    when(
      () => syncManager.onPendingChanges,
    ).thenAnswer((_) => const Stream<void>.empty());
    when(
      () => connectivity.checkConnectivity(),
    ).thenAnswer((_) async => [ConnectivityResult.wifi]);
    when(
      () => connectivity.onConnectivityChanged,
    ).thenAnswer((_) => const Stream<List<ConnectivityResult>>.empty());

    final orchestrator = HybridSyncOrchestrator(
      syncManager: syncManager,
      cloudService: cloudService,
      dbHelper: db,
      tenantContext: TenantContext(),
      connectivity: connectivity,
    );

    await orchestrator.syncNow(reason: 'first');
    final initialNullCursorProductReads = backend.collectionReads
        .where(
          (read) => read.collection == 'productos' && read.updatedAfter == null,
        )
        .length;
    await orchestrator.syncNow(reason: 'later-in-the-same-session');
    final laterNullCursorProductReads = backend.collectionReads
        .where(
          (read) => read.collection == 'productos' && read.updatedAfter == null,
        )
        .length;

    // One null-cursor product read is the bootstrap check and the other is
    // the first tombstone maintenance pass. Later cycles use the incremental
    // cursor, so a long-lived session still receives remote menu changes.
    expect(initialNullCursorProductReads, 2);
    expect(laterNullCursorProductReads, initialNullCursorProductReads);
    expect(
      backend.collectionReads.where(
        (read) => read.collection == 'productos' && read.updatedAfter != null,
      ),
      isNotEmpty,
    );

    await orchestrator.stop();
  });
}
