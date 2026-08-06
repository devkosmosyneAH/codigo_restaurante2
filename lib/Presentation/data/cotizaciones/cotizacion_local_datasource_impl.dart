import 'package:restaurant_app/Presentation/Models/cotizaciones/cotizacion_item_model.dart';
import 'package:restaurant_app/Presentation/Models/cotizaciones/cotizacion_model.dart';
import 'package:restaurant_app/Presentation/core/database/database_helper.dart';
import 'package:restaurant_app/Presentation/core/errors/exceptions.dart';
import 'package:restaurant_app/Presentation/core/sync/sync_manager.dart';
import 'package:restaurant_app/Presentation/core/sync/sync_record.dart'
    show SyncOperation;
import 'package:restaurant_app/Presentation/core/tenant/tenant_context.dart';
import 'package:restaurant_app/Presentation/data/cotizaciones/cotizacion_local_datasource.dart';

/// Implementacion SQLite del datasource de cotizaciones.
class CotizacionLocalDataSourceImpl implements CotizacionLocalDataSource {
  final DatabaseHelper _dbHelper;
  final SyncManager _syncManager;
  final TenantContext _tenantContext;

  CotizacionLocalDataSourceImpl({
    required DatabaseHelper dbHelper,
    required SyncManager syncManager,
    required TenantContext tenantContext,
  }) : _dbHelper = dbHelper,
       _syncManager = syncManager,
       _tenantContext = tenantContext;

  static const _tableCotizaciones = 'cotizaciones';
  static const _tableItems = 'cotizacion_items';
  static const _estadosValidos = {
    'borrador',
    'pendiente',
    'aceptada',
    'rechazada',
    'finalizada',
    'cobrada',
  };

  void _validateCotizacion(CotizacionModel cotizacion) {
    if (cotizacion.restaurantId != _tenantContext.restaurantId) {
      throw const DatabaseException(
        message: 'La cotización no pertenece al restaurante activo.',
      );
    }
    if (!_estadosValidos.contains(cotizacion.estado)) {
      throw const DatabaseException(message: 'Estado de cotización inválido.');
    }
    if (!cotizacion.subtotal.isFinite ||
        !cotizacion.total.isFinite ||
        cotizacion.subtotal < 0 ||
        cotizacion.total < 0 ||
        !cotizacion.descuento.isFinite ||
        !cotizacion.tasaImpuesto.isFinite ||
        cotizacion.descuento < 0 ||
        cotizacion.descuento > 100 ||
        cotizacion.tasaImpuesto < 0 ||
        cotizacion.tasaImpuesto > 100) {
      throw const DatabaseException(
        message:
            'Los importes, descuento o impuesto de la cotización no son válidos.',
      );
    }
    for (final item in cotizacion.items) {
      if (item.cantidad <= 0 ||
          !item.precioUnitario.isFinite ||
          !item.subtotal.isFinite ||
          item.precioUnitario < 0 ||
          item.subtotal < 0 ||
          !item.descuento.isFinite ||
          item.descuento < 0 ||
          item.descuento > 100) {
        throw const DatabaseException(
          message: 'Uno de los ítems de la cotización tiene valores inválidos.',
        );
      }
    }
  }

  @override
  Future<void> createCotizacion(CotizacionModel cotizacion) async {
    try {
      _validateCotizacion(cotizacion);
      await _dbHelper.transaction((txn) async {
        await txn.insert(_tableCotizaciones, cotizacion.toMap());
        for (final item in cotizacion.items) {
          final itemModel = CotizacionItemModel.fromEntity(item);
          await txn.insert(_tableItems, itemModel.toMap());
        }
      });
      await _syncManager.registrarOperacion(
        tabla: _tableCotizaciones,
        registroId: cotizacion.id,
        operacion: SyncOperation.insert,
        restaurantId: cotizacion.restaurantId,
        datos: cotizacion.toMap(),
      );
      for (final item in cotizacion.items) {
        await _syncManager.registrarOperacion(
          tabla: _tableItems,
          registroId: item.id,
          operacion: SyncOperation.insert,
          restaurantId: cotizacion.restaurantId,
          datos: CotizacionItemModel.fromEntity(item).toMap(),
        );
      }
    } catch (e) {
      throw DatabaseException(message: 'Error al crear cotizacion: $e');
    }
  }

  @override
  Future<List<CotizacionModel>> getCotizaciones(String restaurantId) async {
    try {
      final rows = await _dbHelper.query(
        _tableCotizaciones,
        where: 'restaurant_id = ?',
        whereArgs: [restaurantId],
        orderBy: 'created_at DESC',
      );

      final cotizacionIds = rows
          .map((row) => row['id'])
          .whereType<String>()
          .toList(growable: false);
      final itemsByCotizacion = await _getItemsByCotizacionIds(cotizacionIds);

      final cotizaciones = <CotizacionModel>[];
      for (final row in rows) {
        final cotizacionId = row['id'] as String;
        final items =
            itemsByCotizacion[cotizacionId] ?? const <CotizacionItemModel>[];
        cotizaciones.add(CotizacionModel.fromMap(row, items: items));
      }

      return cotizaciones;
    } catch (e) {
      throw DatabaseException(message: 'Error al listar cotizaciones: $e');
    }
  }

  @override
  Future<void> updateEstado(String cotizacionId, String estado) async {
    try {
      if (!_estadosValidos.contains(estado)) {
        throw const DatabaseException(
          message: 'Estado de cotización inválido.',
        );
      }
      final affected = await _dbHelper.update(
        _tableCotizaciones,
        {'estado': estado},
        where: 'id = ? AND restaurant_id = ?',
        whereArgs: [cotizacionId, _tenantContext.restaurantId],
      );
      if (affected == 0) {
        throw const DatabaseException(message: 'Cotización no encontrada.');
      }
      await _syncManager.registrarOperacion(
        tabla: _tableCotizaciones,
        registroId: cotizacionId,
        operacion: SyncOperation.update,
        restaurantId: _tenantContext.restaurantId,
        datos: {'estado': estado},
      );
    } on DatabaseException {
      rethrow;
    } catch (e) {
      throw DatabaseException(message: 'Error al actualizar cotizacion: $e');
    }
  }

  @override
  Future<void> updateCotizacion(CotizacionModel cotizacion) async {
    try {
      _validateCotizacion(cotizacion);
      final previousRows = await _dbHelper.query(
        _tableItems,
        where: 'cotizacion_id = ?',
        whereArgs: [cotizacion.id],
      );
      final previousIds = previousRows
          .map((row) => row['id'])
          .whereType<String>()
          .toSet();
      final currentIds = cotizacion.items.map((item) => item.id).toSet();

      await _dbHelper.transaction((txn) async {
        final affected = await txn.update(
          _tableCotizaciones,
          cotizacion.toMap(),
          where: 'id = ? AND restaurant_id = ?',
          whereArgs: [cotizacion.id, cotizacion.restaurantId],
        );
        if (affected == 0) {
          throw const DatabaseException(message: 'Cotización no encontrada.');
        }
        await txn.delete(
          _tableItems,
          where: 'cotizacion_id = ?',
          whereArgs: [cotizacion.id],
        );
        for (final item in cotizacion.items) {
          final itemModel = CotizacionItemModel.fromEntity(item);
          await txn.insert(_tableItems, itemModel.toMap());
        }
      });
      await _syncManager.registrarOperacion(
        tabla: _tableCotizaciones,
        registroId: cotizacion.id,
        operacion: SyncOperation.update,
        restaurantId: cotizacion.restaurantId,
        datos: cotizacion.toMap(),
      );
      for (final removedId in previousIds.difference(currentIds)) {
        await _syncManager.registrarOperacion(
          tabla: _tableItems,
          registroId: removedId,
          operacion: SyncOperation.delete,
          restaurantId: cotizacion.restaurantId,
        );
      }
      for (final item in cotizacion.items) {
        await _syncManager.registrarOperacion(
          tabla: _tableItems,
          registroId: item.id,
          operacion: previousIds.contains(item.id)
              ? SyncOperation.update
              : SyncOperation.insert,
          restaurantId: cotizacion.restaurantId,
          datos: CotizacionItemModel.fromEntity(item).toMap(),
        );
      }
    } on DatabaseException {
      rethrow;
    } catch (e) {
      throw DatabaseException(message: 'Error al actualizar cotizacion: $e');
    }
  }

  @override
  Future<void> deleteCotizacion(String cotizacionId) async {
    try {
      final cotizacionRows = await _dbHelper.query(
        _tableCotizaciones,
        where: 'id = ? AND restaurant_id = ?',
        whereArgs: [cotizacionId, _tenantContext.restaurantId],
        limit: 1,
      );
      if (cotizacionRows.isEmpty) {
        throw const DatabaseException(message: 'Cotización no encontrada.');
      }
      final itemRows = await _dbHelper.query(
        _tableItems,
        where: 'cotizacion_id = ?',
        whereArgs: [cotizacionId],
      );
      final itemIds = itemRows
          .map((row) => row['id'])
          .whereType<String>()
          .where((itemId) => itemId.isNotEmpty)
          .toList();

      await _dbHelper.transaction((txn) async {
        await txn.delete(
          _tableItems,
          where: 'cotizacion_id = ?',
          whereArgs: [cotizacionId],
        );
        await txn.delete(
          _tableCotizaciones,
          where: 'id = ? AND restaurant_id = ?',
          whereArgs: [cotizacionId, _tenantContext.restaurantId],
        );
      });

      for (final itemId in itemIds) {
        await _syncManager.registrarOperacion(
          tabla: _tableItems,
          registroId: itemId,
          operacion: SyncOperation.delete,
          restaurantId: _tenantContext.restaurantId,
        );
      }

      await _syncManager.registrarOperacion(
        tabla: _tableCotizaciones,
        registroId: cotizacionId,
        operacion: SyncOperation.delete,
        restaurantId: _tenantContext.restaurantId,
      );
    } on DatabaseException {
      rethrow;
    } catch (e) {
      throw DatabaseException(message: 'Error al eliminar cotizacion: $e');
    }
  }

  Future<Map<String, List<CotizacionItemModel>>> _getItemsByCotizacionIds(
    List<String> cotizacionIds,
  ) async {
    if (cotizacionIds.isEmpty) return const {};

    final placeholders = List.filled(cotizacionIds.length, '?').join(',');
    final rows = await _dbHelper.rawQuery('''
      SELECT *
      FROM $_tableItems
      WHERE cotizacion_id IN ($placeholders)
      ORDER BY cotizacion_id ASC, rowid ASC
      ''', cotizacionIds);

    final grouped = <String, List<CotizacionItemModel>>{};
    for (final row in rows) {
      final item = CotizacionItemModel.fromMap(row);
      grouped.putIfAbsent(item.cotizacionId, () => []).add(item);
    }
    return grouped;
  }
}
