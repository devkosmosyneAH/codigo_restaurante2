import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:restaurant_app/Presentation/core/firebase/firebase_initializer.dart';
import 'package:restaurant_app/Presentation/Models/cotizaciones/cotizacion_item_model.dart';
import 'package:restaurant_app/Presentation/Models/cotizaciones/cotizacion_model.dart';
import 'package:restaurant_app/Presentation/entities/cotizaciones/cotizacion.dart';

/// Lectura y recepción segura de cotizaciones públicas.
///
/// Las cotizaciones públicas usan UUID como identificador no adivinable. La
/// regla de Realtime Database limita la escritura anónima a nuevas solicitudes
/// con origen "publica" y la lectura a esos documentos.
class PublicCotizacionCloudService {
  PublicCotizacionCloudService({FirebaseDatabase? database, FirebaseAuth? auth})
    : _database = database,
      _auth = auth;

  final FirebaseDatabase? _database;
  final FirebaseAuth? _auth;

  FirebaseDatabase get _firebaseDatabase =>
      _database ?? FirebaseDatabase.instance;

  FirebaseAuth get _firebaseAuth => _auth ?? FirebaseAuth.instance;

  bool get isSignedIn => _firebaseAuth.currentUser != null;

  Future<void> submit(Cotizacion cotizacion) async {
    if (_database == null) await FirebaseAppInitializer.initialize();
    final root = _firebaseDatabase.ref();
    final base = 'restaurantes/${cotizacion.restaurantId}';
    final quotePath = '$base/cotizaciones/${cotizacion.id}';
    final writes = <String, dynamic>{quotePath: _quotePayload(cotizacion)};

    for (final item in cotizacion.items) {
      final itemPayload = CotizacionItemModel.fromEntity(item).toMap()
        ..removeWhere((key, value) => value == null);
      writes['$base/cotizacion_items/${item.id}'] = {
        ...itemPayload,
        'restaurant_id': cotizacion.restaurantId,
        'publico': true,
      };
    }

    await root.update(writes);
  }

  Future<CotizacionModel?> fetch({
    required String restaurantId,
    required String cotizacionId,
  }) async {
    if (_database == null) await FirebaseAppInitializer.initialize();
    final base = _firebaseDatabase
        .ref()
        .child('restaurantes')
        .child(restaurantId);
    final quoteSnapshot = await base
        .child('cotizaciones')
        .child(cotizacionId)
        .once();
    final rawQuote = quoteSnapshot.snapshot.value;
    if (rawQuote is! Map) return null;

    final quote = Map<String, dynamic>.from(rawQuote);
    if (quote['origen']?.toString() != 'publica') return null;

    final items = <CotizacionItemModel>[];
    final rawItemIds = quote['item_ids'];
    final itemIds = rawItemIds is List
        ? rawItemIds.map((id) => id.toString()).where((id) => id.isNotEmpty)
        : const <String>[];
    final itemSnapshots = await Future.wait(
      itemIds.map(
        (itemId) => base.child('cotizacion_items').child(itemId).once(),
      ),
    );
    for (final itemSnapshot in itemSnapshots) {
      final rawItem = itemSnapshot.snapshot.value;
      if (rawItem is! Map) continue;
      final item = Map<String, dynamic>.from(rawItem);
      if (item['cotizacion_id']?.toString() != cotizacionId ||
          item['publico'] != true) {
        continue;
      }
      try {
        items.add(CotizacionItemModel.fromMap(item));
      } catch (_) {
        // Ignorar un item corrupto sin tumbar la consulta completa.
      }
    }
    items.sort((a, b) => a.id.compareTo(b.id));

    try {
      return CotizacionModel.fromMap({
        ...quote,
        'id': quote['id'] ?? cotizacionId,
      }, items: items);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _quotePayload(Cotizacion cotizacion) {
    final payload =
        Map<String, dynamic>.from(
          CotizacionModel.fromEntity(cotizacion).toMap(),
        )..removeWhere(
          (key, value) => value == null || key == 'firma_imagen_bytes',
        );
    payload['origen'] = 'publica';
    payload['item_ids'] = cotizacion.items.map((item) => item.id).toList();
    return payload;
  }
}
