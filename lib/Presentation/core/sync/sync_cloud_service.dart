import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:restaurant_app/Presentation/core/config/app_environment.dart';
import 'package:restaurant_app/Presentation/core/firebase/firebase_initializer.dart';
import 'package:restaurant_app/Presentation/core/sync/sync_record.dart';

/// Delta angosto de disponibilidad. [updatedAt] es un timestamp de servidor
/// usado exclusivamente como cursor; [version] conserva el `updated_at` del
/// producto para que el pull completo pueda reconciliarse sin perder el flag.
class DisponibilidadUpdate {
  const DisponibilidadUpdate({
    required this.productoId,
    required this.disponible,
    required this.updatedAt,
    required this.version,
  });

  final String productoId;
  final bool disponible;
  final int updatedAt;
  final String version;
}

abstract class SyncCloudBackend {
  Future<void> ensureAvailable();

  Future<void> setDocument({
    required String restaurantId,
    required String collection,
    required String documentId,
    required Map<String, dynamic> data,
    required bool merge,
  });

  Future<void> deleteDocument({
    required String restaurantId,
    required String collection,
    required String documentId,
  });

  Future<void> writeAudit({
    required String recordId,
    required Map<String, dynamic> data,
  });

  Future<Map<String, Map<String, dynamic>>> listCollection({
    required String restaurantId,
    required String collection,
    String? updatedAfter,
  }) async {
    return const {};
  }

  /// Lee solo los flags de disponibilidad. El cursor es inclusivo para no
  /// perder cambios que compartan el mismo milisegundo de servidor.
  Future<Map<String, DisponibilidadUpdate>> listDisponibilidad({
    required String restaurantId,
    int? updatedAtInclusive,
  }) async {
    return const {};
  }

  /// Escribe el producto y su proyeccion angosta en una actualizacion RTDB
  /// multipath, de modo que ambas rutas nunca divergen por una doble escritura.
  Future<void> setProductoConDisponibilidad({
    required String restaurantId,
    required String productoId,
    required Map<String, dynamic> producto,
    required bool mergeProducto,
    required Map<String, dynamic> disponibilidad,
  }) async {}

  /// Completa una proyeccion de disponibilidad ya existente sin reescribir
  /// productos. Solo se usa durante el bootstrap de instalaciones anteriores.
  Future<void> setDisponibilidadBatch({
    required String restaurantId,
    required Map<String, Map<String, dynamic>> updates,
  }) async {}

  /// Valor especial que RTDB resuelve con su propio reloj al confirmar el
  /// update, evitando depender de la hora de cada dispositivo.
  Object availabilityTimestamp();

  Object serverTimestamp();
}

class FirebaseRealtimeSyncCloudBackend implements SyncCloudBackend {
  FirebaseRealtimeSyncCloudBackend({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  static const Duration _requestTimeout = Duration(seconds: 12);
  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
  };
  static const Set<String> _localOnlyKeys = {
    // Columnas heredadas de la migración anterior; nunca deben llegar a
    // Realtime Database después del retiro de Google Drive.
    'drive_file_id',
    'drive_public_url',
    'imagen_local_cache_path',
    'image_base64',
    'image_temp_path',
  };

  final http.Client _httpClient;

  String get _baseUrl => AppEnvironment.realtimeDatabaseUrl;

  @override
  Future<void> ensureAvailable() async {
    if (!AppEnvironment.isRealtimeDatabaseConfigured) {
      throw StateError(
        'Realtime Database no esta configurada. Define FIREBASE_DATABASE_URL o REALTIME_DATABASE_URL.',
      );
    }

    final healthUri = Uri.parse('$_baseUrl/.json?shallow=true');
    final response = await _request(
      healthUri,
      (uri) => _httpClient.get(uri).timeout(_requestTimeout),
    );
    _ensureSuccess(response, operation: 'healthCheck', uri: healthUri);
  }

  @override
  Future<void> setDocument({
    required String restaurantId,
    required String collection,
    required String documentId,
    required Map<String, dynamic> data,
    required bool merge,
  }) async {
    final uri = _documentUri(
      restaurantId: restaurantId,
      collection: collection,
      documentId: documentId,
    );

    final payload = _sanitizePayload(data);
    if (payload.isEmpty) {
      throw StateError(
        'Realtime DB recibio un payload vacio para '
        '$collection/$documentId.',
      );
    }
    final response = merge
        ? await _request(
            uri,
            (target) => _httpClient
                .patch(target, headers: _jsonHeaders, body: jsonEncode(payload))
                .timeout(_requestTimeout),
          )
        : await _request(
            uri,
            (target) => _httpClient
                .put(target, headers: _jsonHeaders, body: jsonEncode(payload))
                .timeout(_requestTimeout),
          );

    _ensureSuccess(response, operation: 'setDocument', uri: uri);

    // Firebase REST puede responder 200 aunque otra escritura haya dejado el
    // documento vacio inmediatamente despues. Verificamos las entidades del
    // menu para no marcar como sincronizado un producto que no existe.
    if (collection == 'categorias' ||
        collection == 'productos' ||
        collection == 'variantes') {
      final verification = await _request(
        uri,
        (target) => _httpClient.get(target).timeout(_requestTimeout),
      );
      _ensureSuccess(verification, operation: 'verifyDocument', uri: uri);
      if (verification.body.trim().isEmpty ||
          verification.body.trim() == 'null') {
        throw StateError(
          'Realtime DB no conservo $collection/$documentId despues de escribir.',
        );
      }
    }
  }

  @override
  Future<void> deleteDocument({
    required String restaurantId,
    required String collection,
    required String documentId,
  }) async {
    final uri = _documentUri(
      restaurantId: restaurantId,
      collection: collection,
      documentId: documentId,
    );
    final response = await _request(
      uri,
      (target) => _httpClient.delete(target).timeout(_requestTimeout),
    );
    _ensureSuccess(response, operation: 'deleteDocument', uri: uri);
  }

  @override
  Future<void> writeAudit({
    required String recordId,
    required Map<String, dynamic> data,
  }) async {
    final safeRecordId = Uri.encodeComponent(recordId);
    final uri = Uri.parse('$_baseUrl/sync_audit/$safeRecordId.json');
    final response = await _request(
      uri,
      (target) => _httpClient
          .put(
            target,
            headers: _jsonHeaders,
            body: jsonEncode(_sanitizePayload(data)),
          )
          .timeout(_requestTimeout),
    );
    _ensureSuccess(response, operation: 'writeAudit', uri: uri);
  }

  @override
  Future<Map<String, Map<String, dynamic>>> listCollection({
    required String restaurantId,
    required String collection,
    String? updatedAfter,
  }) async {
    final uri = _collectionUri(
      restaurantId: restaurantId,
      collection: collection,
      updatedAfter: updatedAfter,
    );

    final response = await _request(
      uri,
      (target) => _httpClient.get(target).timeout(_requestTimeout),
    );
    _ensureSuccess(response, operation: 'listCollection', uri: uri);

    if (response.body.trim().isEmpty || response.body.trim() == 'null') {
      return const {};
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      return const {};
    }

    final output = <String, Map<String, dynamic>>{};
    for (final entry in decoded.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is Map) {
        output[key] = Map<String, dynamic>.from(value);
      }
    }

    return output;
  }

  @override
  Future<Map<String, DisponibilidadUpdate>> listDisponibilidad({
    required String restaurantId,
    int? updatedAtInclusive,
  }) async {
    final uri = _disponibilidadUri(
      restaurantId: restaurantId,
      updatedAtInclusive: updatedAtInclusive,
    );
    final response = await _request(
      uri,
      (target) => _httpClient.get(target).timeout(_requestTimeout),
    );
    _ensureSuccess(response, operation: 'listDisponibilidad', uri: uri);
    return _parseDisponibilidad(response.body);
  }

  @override
  Future<void> setProductoConDisponibilidad({
    required String restaurantId,
    required String productoId,
    required Map<String, dynamic> producto,
    required bool mergeProducto,
    required Map<String, dynamic> disponibilidad,
  }) async {
    final safeProducto = _sanitizePayload(producto);
    final safeDisponibilidad = _sanitizePayload(disponibilidad);
    if (safeProducto.isEmpty || safeDisponibilidad.isEmpty) {
      throw StateError('No se puede sincronizar disponibilidad sin producto.');
    }

    final updates = <String, dynamic>{
      'disponibilidad/$productoId': safeDisponibilidad,
    };
    if (mergeProducto) {
      for (final entry in safeProducto.entries) {
        updates['productos/$productoId/${entry.key}'] = entry.value;
      }
    } else {
      updates['productos/$productoId'] = safeProducto;
    }

    final rootUri = _restaurantUri(restaurantId);
    final response = await _request(
      rootUri,
      (target) => _httpClient
          .patch(target, headers: _jsonHeaders, body: jsonEncode(updates))
          .timeout(_requestTimeout),
    );
    _ensureSuccess(
      response,
      operation: 'setProductoConDisponibilidad',
      uri: rootUri,
    );

    final productoUri = _documentUri(
      restaurantId: restaurantId,
      collection: 'productos',
      documentId: productoId,
    );
    final verification = await _request(
      productoUri,
      (target) => _httpClient.get(target).timeout(_requestTimeout),
    );
    _ensureSuccess(verification, operation: 'verifyProducto', uri: productoUri);
    if (verification.body.trim().isEmpty ||
        verification.body.trim() == 'null') {
      throw StateError('Realtime DB no conservo productos/$productoId.');
    }
  }

  @override
  Future<void> setDisponibilidadBatch({
    required String restaurantId,
    required Map<String, Map<String, dynamic>> updates,
  }) async {
    if (updates.isEmpty) return;
    final payload = <String, dynamic>{};
    for (final entry in updates.entries) {
      payload['disponibilidad/${entry.key}'] = _sanitizePayload(entry.value);
    }
    final uri = _restaurantUri(restaurantId);
    final response = await _request(
      uri,
      (target) => _httpClient
          .patch(target, headers: _jsonHeaders, body: jsonEncode(payload))
          .timeout(_requestTimeout),
    );
    _ensureSuccess(response, operation: 'setDisponibilidadBatch', uri: uri);
  }

  @override
  Object serverTimestamp() => DateTime.now().toIso8601String();

  @override
  Object availabilityTimestamp() => const {'.sv': 'timestamp'};

  Uri _restaurantUri(String restaurantId) {
    final safeRestaurantId = Uri.encodeComponent(restaurantId);
    return Uri.parse('$_baseUrl/restaurantes/$safeRestaurantId.json');
  }

  Uri _documentUri({
    required String restaurantId,
    required String collection,
    required String documentId,
  }) {
    final safeRestaurantId = Uri.encodeComponent(restaurantId);
    final safeCollection = Uri.encodeComponent(collection);
    final safeDocumentId = Uri.encodeComponent(documentId);

    return Uri.parse(
      '$_baseUrl/restaurantes/$safeRestaurantId/$safeCollection/$safeDocumentId.json',
    );
  }

  /// Firebase REST acepta el ID token en el parámetro `auth`. Las operaciones
  /// administrativas deben viajar autenticadas, mientras que las lecturas
  /// públicas pueden seguir usando la misma clase sin token.
  Future<Uri> _authenticatedUri(Uri uri) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return uri;

    final token = await user.getIdToken();
    if (token == null || token.isEmpty) return uri;

    return uri.replace(
      queryParameters: {...uri.queryParameters, 'auth': token},
    );
  }

  Future<http.Response> _request(
    Uri uri,
    Future<http.Response> Function(Uri uri) request,
  ) async {
    final authenticatedUri = await _authenticatedUri(uri);
    final response = await request(authenticatedUri);
    if ((response.statusCode == 401 || response.statusCode == 403) &&
        authenticatedUri != uri) {
      // Realtime Database rules remain the final authority. This retry makes
      // public-rule deployments resilient to an expired Firebase Auth token.
      return request(uri);
    }
    return response;
  }

  Uri _collectionUri({
    required String restaurantId,
    required String collection,
    String? updatedAfter,
  }) {
    final safeRestaurantId = Uri.encodeComponent(restaurantId);
    final safeCollection = Uri.encodeComponent(collection);
    final base = Uri.parse(
      '$_baseUrl/restaurantes/$safeRestaurantId/$safeCollection.json',
    );

    final trimmedCursor = updatedAfter?.trim();
    if (trimmedCursor == null || trimmedCursor.isEmpty) {
      return base;
    }

    return base.replace(
      queryParameters: {
        'orderBy': jsonEncode('updated_at'),
        'startAt': jsonEncode(trimmedCursor),
      },
    );
  }

  Uri _disponibilidadUri({
    required String restaurantId,
    int? updatedAtInclusive,
  }) {
    final safeRestaurantId = Uri.encodeComponent(restaurantId);
    final base = Uri.parse(
      '$_baseUrl/restaurantes/$safeRestaurantId/disponibilidad.json',
    );
    if (updatedAtInclusive == null) return base;
    return base.replace(
      queryParameters: {
        'orderBy': jsonEncode('u'),
        'startAt': jsonEncode(updatedAtInclusive),
      },
    );
  }

  Map<String, DisponibilidadUpdate> _parseDisponibilidad(String body) {
    if (body.trim().isEmpty || body.trim() == 'null') return const {};
    final decoded = jsonDecode(body);
    if (decoded is! Map) return const {};
    final output = <String, DisponibilidadUpdate>{};
    for (final entry in decoded.entries) {
      if (entry.value is! Map) continue;
      final value = Map<String, dynamic>.from(entry.value as Map);
      final updatedAt = (value['u'] as num?)?.toInt();
      if (updatedAt == null) continue;
      output[entry.key.toString()] = DisponibilidadUpdate(
        productoId: entry.key.toString(),
        disponible: _readBool(value['d']),
        updatedAt: updatedAt,
        version: value['v']?.toString() ?? '',
      );
    }
    return output;
  }

  bool _readBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return value?.toString().toLowerCase() == 'true' || value == '1';
  }

  Map<String, dynamic> _sanitizePayload(Map<String, dynamic> source) {
    final output = <String, dynamic>{};
    for (final entry in source.entries) {
      final key = entry.key;
      if (_localOnlyKeys.contains(key)) continue;

      final value = entry.value;
      // Firebase PATCH uses null to remove a previous tombstone field.
      if (value == null && key != 'deleted_at') continue;

      final sanitized = _sanitizeValue(key, value);
      if (identical(sanitized, _dropValue)) continue;
      output[key] = sanitized;
    }

    final imageUrl = output['imagen_url'];
    if (imageUrl is String && !_isValidRemoteImageUrl(imageUrl)) {
      output.remove('imagen_url');
    }

    final cloudinaryId = output['cloudinary_public_id'];
    if (cloudinaryId is String && cloudinaryId.trim().isEmpty) {
      output.remove('cloudinary_public_id');
    }
    return output;
  }

  static const Object _dropValue = Object();

  Object _sanitizeValue(String key, dynamic value) {
    if (value is DateTime) {
      return value.toIso8601String();
    }

    if (value is Map) {
      final nested = <String, dynamic>{};
      for (final entry in value.entries) {
        final nestedKey = entry.key.toString();
        final sanitized = _sanitizeValue(nestedKey, entry.value);
        if (identical(sanitized, _dropValue)) continue;
        nested[nestedKey] = sanitized;
      }
      return nested;
    }

    if (value is List) {
      final nested = <dynamic>[];
      for (final item in value) {
        final sanitized = _sanitizeValue(key, item);
        if (identical(sanitized, _dropValue)) continue;
        nested.add(sanitized);
      }
      return nested;
    }

    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return value;

      if (key == 'imagen_url') {
        return _isValidRemoteImageUrl(trimmed) ? trimmed : _dropValue;
      }

      if (key == 'cloudinary_public_id') {
        return trimmed.isNotEmpty ? trimmed : _dropValue;
      }

      final lowerKey = key.toLowerCase();
      final isImageField =
          lowerKey.contains('imagen') || lowerKey.contains('image');

      if (isImageField && _isForbiddenBinaryValue(trimmed)) {
        return _dropValue;
      }

      return trimmed;
    }

    return value;
  }

  bool _isForbiddenBinaryValue(String value) {
    final normalized = value.trim();
    final lower = normalized.toLowerCase();

    if (lower.startsWith('data:') ||
        lower.startsWith('file://') ||
        lower.startsWith('blob:') ||
        lower.startsWith('content://') ||
        lower.contains(';base64,')) {
      return true;
    }

    if (normalized.startsWith('/') ||
        normalized.startsWith('./') ||
        normalized.startsWith('../')) {
      return true;
    }

    return RegExp(r'^[a-zA-Z]:\\').hasMatch(normalized);
  }

  bool _isValidRemoteImageUrl(String value) {
    if (_isForbiddenBinaryValue(value)) return false;

    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasScheme) return false;

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;

    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty || host == 'localhost' || host == '127.0.0.1') {
      return false;
    }

    return true;
  }

  void _ensureSuccess(
    http.Response response, {
    required String operation,
    required Uri uri,
  }) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    throw StateError(
      'Realtime DB $operation fallo (${response.statusCode}) en $uri: ${response.body}',
    );
  }
}

/// Backend nativo de Firebase Realtime Database.
///
/// En web usamos el SDK oficial en lugar del cliente HTTP. Esto evita que una
/// restriccion CORS o un token de Firebase Auth caducado haga que la app
/// mantenga las operaciones en SQLite aunque el endpoint sea accesible desde
/// fuera del navegador.
class FirebaseSdkSyncCloudBackend implements SyncCloudBackend {
  FirebaseSdkSyncCloudBackend({FirebaseDatabase? database})
    : _database = database;

  static const Set<String> _localOnlyKeys = {
    'drive_file_id',
    'drive_public_url',
    'imagen_local_cache_path',
    'image_base64',
    'image_temp_path',
  };

  final FirebaseDatabase? _database;

  FirebaseDatabase get _firebaseDatabase =>
      _database ?? FirebaseDatabase.instance;

  DatabaseReference _documentRef({
    required String restaurantId,
    required String collection,
    required String documentId,
  }) => _firebaseDatabase
      .ref()
      .child('restaurantes')
      .child(restaurantId.trim())
      .child(collection.trim())
      .child(documentId.trim());

  DatabaseReference _collectionRef({
    required String restaurantId,
    required String collection,
  }) => _firebaseDatabase
      .ref()
      .child('restaurantes')
      .child(restaurantId.trim())
      .child(collection.trim());

  @override
  Future<void> ensureAvailable() async {
    if (!AppEnvironment.isRealtimeDatabaseConfigured) {
      throw StateError(
        'Realtime Database no esta configurada. Define FIREBASE_DATABASE_URL o REALTIME_DATABASE_URL.',
      );
    }

    try {
      final snapshot = await _firebaseDatabase
          .ref()
          .child('.info')
          .child('connected')
          .once();
      if (snapshot.snapshot.value != true) {
        throw StateError('Firebase SDK reporta la conexion como inactiva.');
      }
    } catch (error) {
      throw StateError('Firebase SDK no esta disponible: $error');
    }
  }

  @override
  Future<void> setDocument({
    required String restaurantId,
    required String collection,
    required String documentId,
    required Map<String, dynamic> data,
    required bool merge,
  }) async {
    final payload = _sanitizePayload(data);
    if (payload.isEmpty) {
      throw StateError(
        'Realtime DB recibio un payload vacio para '
        '$collection/$documentId.',
      );
    }

    final reference = _documentRef(
      restaurantId: restaurantId,
      collection: collection,
      documentId: documentId,
    );
    if (merge) {
      await reference.update(Map<String, Object?>.from(payload));
    } else {
      await reference.set(payload);
    }

    if (collection == 'categorias' ||
        collection == 'productos' ||
        collection == 'variantes') {
      final snapshot = await reference.once();
      if (!snapshot.snapshot.exists || snapshot.snapshot.value == null) {
        throw StateError(
          'Realtime DB no conservo $collection/$documentId despues de escribir.',
        );
      }
    }
  }

  @override
  Future<void> deleteDocument({
    required String restaurantId,
    required String collection,
    required String documentId,
  }) async {
    await _documentRef(
      restaurantId: restaurantId,
      collection: collection,
      documentId: documentId,
    ).remove();
  }

  @override
  Future<void> writeAudit({
    required String recordId,
    required Map<String, dynamic> data,
  }) async {
    await _firebaseDatabase
        .ref()
        .child('sync_audit')
        .child(recordId)
        .set(_sanitizePayload(data));
  }

  @override
  Future<Map<String, Map<String, dynamic>>> listCollection({
    required String restaurantId,
    required String collection,
    String? updatedAfter,
  }) async {
    Query query = _collectionRef(
      restaurantId: restaurantId,
      collection: collection,
    );
    final cursor = updatedAfter?.trim();
    if (cursor != null && cursor.isNotEmpty) {
      query = query.orderByChild('updated_at').startAt(cursor);
    }

    final snapshot = await query.once();
    final raw = snapshot.snapshot.value;
    if (raw is! Map) return const {};

    final result = <String, Map<String, dynamic>>{};
    for (final entry in raw.entries) {
      if (entry.value is Map) {
        result[entry.key.toString()] = Map<String, dynamic>.from(
          entry.value as Map,
        );
      }
    }
    return result;
  }

  @override
  Future<Map<String, DisponibilidadUpdate>> listDisponibilidad({
    required String restaurantId,
    int? updatedAtInclusive,
  }) async {
    Query query = _collectionRef(
      restaurantId: restaurantId,
      collection: 'disponibilidad',
    );
    if (updatedAtInclusive != null) {
      query = query.orderByChild('u').startAt(updatedAtInclusive);
    }

    final snapshot = await query.once();
    final raw = snapshot.snapshot.value;
    if (raw is! Map) return const {};

    final result = <String, DisponibilidadUpdate>{};
    for (final entry in raw.entries) {
      if (entry.value is! Map) continue;
      final value = Map<String, dynamic>.from(entry.value as Map);
      final updatedAt = (value['u'] as num?)?.toInt();
      if (updatedAt == null) continue;
      result[entry.key.toString()] = DisponibilidadUpdate(
        productoId: entry.key.toString(),
        disponible: _readBool(value['d']),
        updatedAt: updatedAt,
        version: value['v']?.toString() ?? '',
      );
    }
    return result;
  }

  @override
  Future<void> setProductoConDisponibilidad({
    required String restaurantId,
    required String productoId,
    required Map<String, dynamic> producto,
    required bool mergeProducto,
    required Map<String, dynamic> disponibilidad,
  }) async {
    final safeProducto = _sanitizePayload(producto);
    final safeDisponibilidad = _sanitizePayload(disponibilidad);
    if (safeProducto.isEmpty || safeDisponibilidad.isEmpty) {
      throw StateError('No se puede sincronizar disponibilidad sin producto.');
    }

    final updates = <String, Object?>{
      'disponibilidad/$productoId': safeDisponibilidad,
    };
    if (mergeProducto) {
      for (final entry in safeProducto.entries) {
        updates['productos/$productoId/${entry.key}'] = entry.value;
      }
    } else {
      updates['productos/$productoId'] = safeProducto;
    }

    final root = _firebaseDatabase
        .ref()
        .child('restaurantes')
        .child(restaurantId.trim());
    await root.update(updates);

    final productoSnapshot = await _documentRef(
      restaurantId: restaurantId,
      collection: 'productos',
      documentId: productoId,
    ).once();
    if (!productoSnapshot.snapshot.exists ||
        productoSnapshot.snapshot.value == null) {
      throw StateError('Realtime DB no conservo productos/$productoId.');
    }
  }

  @override
  Future<void> setDisponibilidadBatch({
    required String restaurantId,
    required Map<String, Map<String, dynamic>> updates,
  }) async {
    if (updates.isEmpty) return;
    final payload = <String, Object?>{};
    for (final entry in updates.entries) {
      payload['disponibilidad/${entry.key}'] = _sanitizePayload(entry.value);
    }
    await _firebaseDatabase
        .ref()
        .child('restaurantes')
        .child(restaurantId.trim())
        .update(payload);
  }

  @override
  Object serverTimestamp() => DateTime.now().toIso8601String();

  @override
  Object availabilityTimestamp() => const {'.sv': 'timestamp'};

  bool _readBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return value?.toString().toLowerCase() == 'true' || value == '1';
  }

  Map<String, dynamic> _sanitizePayload(Map<String, dynamic> source) {
    final output = <String, dynamic>{};
    for (final entry in source.entries) {
      if (_localOnlyKeys.contains(entry.key)) continue;
      if (entry.value == null && entry.key != 'deleted_at') continue;
      final value = _sanitizeValue(entry.key, entry.value);
      if (value != null || entry.key == 'deleted_at') {
        output[entry.key] = value;
      }
    }

    final imageUrl = output['imagen_url'];
    if (imageUrl is String && !_isValidRemoteImageUrl(imageUrl)) {
      output.remove('imagen_url');
    }
    final cloudinaryId = output['cloudinary_public_id'];
    if (cloudinaryId is String && cloudinaryId.trim().isEmpty) {
      output.remove('cloudinary_public_id');
    }
    return output;
  }

  dynamic _sanitizeValue(String key, dynamic value) {
    if (value is DateTime) return value.toIso8601String();
    if (value is Map) {
      final nested = <String, dynamic>{};
      for (final entry in value.entries) {
        final sanitized = _sanitizeValue(entry.key.toString(), entry.value);
        if (sanitized != null) nested[entry.key.toString()] = sanitized;
      }
      return nested;
    }
    if (value is List) {
      return value
          .map((item) => _sanitizeValue(key, item))
          .where((item) => item != null)
          .toList();
    }
    if (value is String) {
      final trimmed = value.trim();
      if (key == 'imagen_url' && !_isValidRemoteImageUrl(trimmed)) return null;
      if (key == 'cloudinary_public_id' && trimmed.isEmpty) return null;
      if (_isImageKey(key) && _isForbiddenBinaryValue(trimmed)) return null;
      return trimmed;
    }
    return value;
  }

  bool _isImageKey(String key) {
    final lower = key.toLowerCase();
    return lower.contains('imagen') || lower.contains('image');
  }

  bool _isForbiddenBinaryValue(String value) {
    final lower = value.toLowerCase();
    return lower.startsWith('data:') ||
        lower.startsWith('file://') ||
        lower.startsWith('blob:') ||
        lower.startsWith('content://') ||
        lower.contains(';base64,') ||
        value.startsWith('/') ||
        value.startsWith('./') ||
        value.startsWith('../') ||
        RegExp(r'^[a-zA-Z]:\\').hasMatch(value);
  }

  bool _isValidRemoteImageUrl(String value) {
    if (_isForbiddenBinaryValue(value)) return false;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return false;
    return uri.scheme == 'http' || uri.scheme == 'https';
  }
}

/// Servicio para enviar operaciones del sync_log a Realtime Database.
class SyncCloudService {
  SyncCloudService({
    SyncCloudBackend? backend,
    bool? enforcePlatformSupport,
    DateTime Function()? now,
  }) : _backend =
           backend ??
           (kIsWeb
               ? FirebaseSdkSyncCloudBackend()
               : FirebaseRealtimeSyncCloudBackend()),
       _enforcePlatformSupport = enforcePlatformSupport ?? backend == null,
       _now = now ?? DateTime.now;

  final SyncCloudBackend _backend;
  final bool _enforcePlatformSupport;
  final DateTime Function() _now;
  final Map<String, DateTime> _lastRemoteAuditAtByRestaurant = {};

  static const Duration _remoteAuditInterval = Duration(minutes: 15);

  bool get isCloudSyncSupportedPlatform =>
      !_enforcePlatformSupport || AppEnvironment.isRealtimeDatabaseConfigured;

  String get unsupportedPlatformMessage =>
      'Sincronizacion en nube deshabilitada en esta plataforma. '
      'Modo local activo (SQLite sin sync cloud).';

  /// Valida que Realtime Database este configurada y disponible.
  Future<void> ensureAvailable() async {
    if (!isCloudSyncSupportedPlatform) {
      throw UnsupportedError(unsupportedPlatformMessage);
    }

    try {
      await _backend.ensureAvailable();
    } catch (e) {
      throw StateError(
        'Realtime Database no esta configurada para sincronizacion. '
        'Completa la configuracion de FIREBASE_DATABASE_URL e intenta de nuevo.\nDetalle: $e',
      );
    }
  }

  Future<Map<String, Map<String, dynamic>>> listCollection({
    required String restaurantId,
    required String collection,
    String? updatedAfter,
  }) async {
    await ensureAvailable();
    return _backend.listCollection(
      restaurantId: restaurantId,
      collection: collection,
      updatedAfter: updatedAfter,
    );
  }

  /// Consulta puntual y angosta para los dispositivos operativos. No ejecuta
  /// `ensureAvailable()` en cada pulso: el orquestador ya valida la sesion al
  /// iniciar y una lectura REST/once fallida se maneja como fallo transitorio.
  Future<Map<String, DisponibilidadUpdate>> pullDisponibilidad({
    required String restaurantId,
    int? updatedAtInclusive,
  }) => _backend.listDisponibilidad(
    restaurantId: restaurantId,
    updatedAtInclusive: updatedAtInclusive,
  );

  /// Materializa el feed angosto en instalaciones que ya tenian productos
  /// antes de que existiera `/disponibilidad`. Recibe el resultado de la
  /// lectura de productos que el bootstrap normal ya hizo, asi no agrega otra
  /// descarga pesada. Solo escribe IDs que todavia no tienen espejo.
  Future<void> completarDisponibilidadFaltante({
    required String restaurantId,
    required Map<String, Map<String, dynamic>> productos,
  }) async {
    if (productos.isEmpty) return;
    final actuales = await pullDisponibilidad(restaurantId: restaurantId);
    final missing = <String, Map<String, dynamic>>{};
    for (final entry in productos.entries) {
      if (actuales.containsKey(entry.key)) continue;
      missing[entry.key] = _availabilityPayloadFromProduct(entry.value);
    }
    await _backend.setDisponibilidadBatch(
      restaurantId: restaurantId,
      updates: missing,
    );
  }

  /// Lee una coleccion publica sin exigir la comprobacion de salud de la raiz.
  Future<Map<String, Map<String, dynamic>>> listPublicCollection({
    required String restaurantId,
    required String collection,
  }) async {
    if (kIsWeb) await FirebaseAppInitializer.initialize();
    return _backend.listCollection(
      restaurantId: restaurantId,
      collection: collection,
    );
  }

  /// Removes an expired tombstone only after the retention window elapsed.
  Future<void> purgeDocument({
    required String restaurantId,
    required String collection,
    required String documentId,
  }) async {
    await ensureAvailable();
    await _backend.deleteDocument(
      restaurantId: restaurantId,
      collection: collection,
      documentId: documentId,
    );
  }

  Future<void> pushRecord(SyncRecord record) async {
    await ensureAvailable();

    final restaurantId = record.restaurantId.trim();
    if (restaurantId.isEmpty || record.registroId.trim().isEmpty) {
      throw ArgumentError(
        'sync_log invalido: restaurant_id y registro_id son obligatorios.',
      );
    }

    if (record.tabla == 'productos') {
      final producto = record.operacion == SyncOperation.delete
          ? _buildTombstone(record, restaurantId)
          : _buildPayload(record);
      await _backend.setProductoConDisponibilidad(
        restaurantId: restaurantId,
        productoId: record.registroId,
        producto: producto,
        mergeProducto: record.operacion == SyncOperation.update,
        disponibilidad: _availabilityPayloadFromProduct(
          producto,
          forceUnavailable: record.operacion == SyncOperation.delete,
        ),
      );
    } else {
      switch (record.operacion) {
        case SyncOperation.insert:
          // PUT/set creates an exact replica for a new document.
          await _backend.setDocument(
            restaurantId: restaurantId,
            collection: record.tabla,
            documentId: record.registroId,
            data: _buildPayload(record),
            // Una solicitud pública puede haber llegado antes de que el
            // dispositivo autenticado procese su sync_log. Conservamos sus
            // metadatos públicos al materializar la copia local.
            merge: record.tabla == 'cotizaciones',
          );
        case SyncOperation.update:
          // PATCH/update changes only the current SQLite snapshot fields.
          await _backend.setDocument(
            restaurantId: restaurantId,
            collection: record.tabla,
            documentId: record.registroId,
            data: _buildPayload(record),
            merge: true,
          );
        case SyncOperation.delete:
          // Keep a tombstone long enough for offline devices to observe the
          // deletion during their next pull.
          await _backend.setDocument(
            restaurantId: restaurantId,
            collection: record.tabla,
            documentId: record.registroId,
            data: _buildTombstone(record, restaurantId),
            merge: false,
          );
      }
    }

    await _writeRemoteSyncStatusIfDue(record, restaurantId);
  }

  /// Keeps a small remote support signal without duplicating every business
  /// write. Detailed per-operation history remains in SQLite's
  /// `sync_audit_log`; Firebase stores only the latest confirmed sync per
  /// restaurant, at most once every fifteen minutes.
  Future<void> _writeRemoteSyncStatusIfDue(
    SyncRecord record,
    String restaurantId,
  ) async {
    final now = _now();
    final lastAuditAt = _lastRemoteAuditAtByRestaurant[restaurantId];
    if (lastAuditAt != null &&
        now.difference(lastAuditAt) < _remoteAuditInterval) {
      return;
    }

    try {
      await _backend.writeAudit(
        recordId: '${restaurantId}_latest',
        data: {
          'restaurant_id': restaurantId,
          'status': 'success',
          'tabla': record.tabla,
          'registro_id': record.registroId,
          'operacion': record.operacion.name,
          'synced_at': _backend.serverTimestamp(),
        },
      );
      _lastRemoteAuditAtByRestaurant[restaurantId] = now;
    } catch (_) {
      // A diagnostic signal must never turn an acknowledged business write
      // into a retry. Leave it eligible for the next successful sync.
    }
  }

  Map<String, dynamic> _buildPayload(SyncRecord record) {
    final cleanData = <String, dynamic>{...?record.datos};
    if (record.tabla == 'clientes') {
      cleanData.remove('id_cliente');
    }

    final payload = <String, dynamic>{
      ...cleanData,
      // PATCH with null removes an earlier tombstone if an entity is revived.
      'deleted_at': null,
      '_sync': {
        'record_id': record.id,
        'operation': record.operacion.name,
        'source': 'restaurant_app',
        'created_at_local': record.createdAt.toIso8601String(),
        'synced_at': _backend.serverTimestamp(),
      },
    };

    payload['id'] = cleanData['id'] ?? record.registroId;

    return payload;
  }

  Map<String, dynamic> _buildTombstone(SyncRecord record, String restaurantId) {
    final payload = <String, dynamic>{
      'id': record.registroId,
      'restaurant_id': restaurantId,
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      '_sync': {
        'record_id': record.id,
        'operation': record.operacion.name,
        'source': 'restaurant_app',
        'created_at_local': record.createdAt.toIso8601String(),
        'synced_at': _backend.serverTimestamp(),
      },
    };
    if (record.tabla == 'clientes') {
      final separator = record.registroId.indexOf(':');
      payload['cedula'] = separator < 0
          ? record.registroId
          : record.registroId.substring(separator + 1);
    }
    return payload;
  }

  Map<String, dynamic> _availabilityPayloadFromProduct(
    Map<String, dynamic> producto, {
    bool forceUnavailable = false,
  }) {
    final deleted = producto['deleted_at'] != null;
    final active = _readBool(producto['activo'], defaultValue: true);
    final available = _readBool(producto['disponible'], defaultValue: true);
    final version = producto['updated_at']?.toString().trim();
    return {
      'd': !forceUnavailable && !deleted && active && available,
      'u': _backend.availabilityTimestamp(),
      'v': (version == null || version.isEmpty)
          ? _now().toUtc().toIso8601String()
          : version,
    };
  }

  bool _readBool(dynamic value, {required bool defaultValue}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
    return defaultValue;
  }
}
