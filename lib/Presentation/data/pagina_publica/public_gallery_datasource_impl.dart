import 'package:restaurant_app/Presentation/Models/pagina_publica/public_gallery_image_model.dart';
import 'package:restaurant_app/Presentation/core/database/database_helper.dart';
import 'package:restaurant_app/Presentation/core/errors/exceptions.dart';
import 'package:restaurant_app/Presentation/core/sync/sync_manager.dart';
import 'package:restaurant_app/Presentation/core/sync/sync_record.dart' show SyncOperation;
import 'package:restaurant_app/Presentation/data/pagina_publica/public_gallery_datasource.dart';

class PublicGalleryDatasourceImpl implements PublicGalleryDatasource {
  static const _table = 'public_gallery_images';
  final DatabaseHelper _db;
  final SyncManager _sync;

  PublicGalleryDatasourceImpl({required DatabaseHelper dbHelper, required SyncManager syncManager})
      : _db = dbHelper,
        _sync = syncManager;

  @override
  Future<List<PublicGalleryImageModel>> getAll(String restaurantId) async {
    try {
      final rows = await _db.query(
        _table,
        where: 'restaurant_id = ?',
        whereArgs: [restaurantId],
        orderBy: 'orden ASC, created_at ASC',
      );
      return rows.map(PublicGalleryImageModel.fromMap).toList();
    } catch (error) {
      throw DatabaseException(message: 'Error al leer la galeria publica: $error');
    }
  }

  @override
  Future<void> save(PublicGalleryImageModel image) async {
    try {
      final existing = await _db.query(_table, where: 'id = ?', whereArgs: [image.id], limit: 1);
      final data = image.toMap();
      await _db.insert(_table, data);
      await _sync.registrarOperacion(
        tabla: _table,
        registroId: image.id,
        operacion: existing.isEmpty ? SyncOperation.insert : SyncOperation.update,
        restaurantId: image.restaurantId,
        datos: data,
      );
    } catch (error) {
      throw DatabaseException(message: 'Error al guardar imagen publica: $error');
    }
  }

  @override
  Future<void> delete(String id, String restaurantId) async {
    try {
      await _db.delete(_table, where: 'id = ? AND restaurant_id = ?', whereArgs: [id, restaurantId]);
      await _sync.registrarOperacion(
        tabla: _table,
        registroId: id,
        operacion: SyncOperation.delete,
        restaurantId: restaurantId,
      );
    } catch (error) {
      throw DatabaseException(message: 'Error al eliminar imagen publica: $error');
    }
  }

  @override
  Future<void> reorder(String restaurantId, List<String> orderedIds) async {
    try {
      await _db.transaction((txn) async {
        for (var i = 0; i < orderedIds.length; i++) {
          await txn.update(
            _table,
            {'orden': i, 'updated_at': DateTime.now().toIso8601String()},
            where: 'id = ? AND restaurant_id = ?',
            whereArgs: [orderedIds[i], restaurantId],
          );
        }
      });
      for (final id in orderedIds) {
        await _sync.registrarOperacion(
          tabla: _table,
          registroId: id,
          operacion: SyncOperation.update,
          restaurantId: restaurantId,
        );
      }
    } catch (error) {
      throw DatabaseException(message: 'Error al ordenar la galeria publica: $error');
    }
  }
}
