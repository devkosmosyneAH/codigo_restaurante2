import 'package:restaurant_app/Presentation/Models/menu/variante_model.dart';
import 'package:restaurant_app/Presentation/entities/menu/producto.dart';
import 'package:restaurant_app/Presentation/entities/menu/variante.dart';

/// Modelo de datos: Producto.
///
/// Serialización SQLite para la entidad [Producto].
/// Maneja la relación con [Variante] opcionalmente.
class ProductoModel extends Producto {
  const ProductoModel({
    required super.id,
    required super.restaurantId,
    required super.categoriaId,
    required super.nombre,
    super.descripcion,
    required super.precio,
    super.imagenUrl,
    super.cloudinaryPublicId,
    super.imagenWidth,
    super.imagenHeight,
    super.imagenBytes,
    super.imagenVersion,
    super.imagenLocalCachePath,
    super.disponible,
    super.activo,
    required super.createdAt,
    required super.updatedAt,
    super.variantes,
  });

  factory ProductoModel.fromMap(
    Map<String, dynamic> map, {
    List<Variante>? variantes,
  }) {
    return ProductoModel(
      id: map['id'] as String,
      restaurantId: map['restaurant_id'] as String,
      categoriaId: map['categoria_id'] as String,
      nombre: map['nombre'] as String,
      descripcion: map['descripcion'] as String?,
      precio: (map['precio'] as num).toDouble(),
      imagenUrl: map['imagen_url'] as String?,
      cloudinaryPublicId: map['cloudinary_public_id'] as String?,
      imagenWidth: (map['imagen_width'] as num?)?.toInt(),
      imagenHeight: (map['imagen_height'] as num?)?.toInt(),
      imagenBytes: (map['imagen_bytes'] as num?)?.toInt(),
      imagenVersion: (map['imagen_version'] as num?)?.toInt(),
      imagenLocalCachePath: map['imagen_local_cache_path'] as String?,
      // Los productos existentes antes de agregar estos campos deben seguir
      // visibles. Solo dejan de mostrarse cuando el administrador los marca
      // explícitamente como no disponibles o inactivos.
      disponible: _readBool(map['disponible'], defaultValue: true),
      activo: _readBool(map['activo'], defaultValue: true),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      variantes: variantes ?? const [],
    );
  }

  static bool _readBool(dynamic value, {required bool defaultValue}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
    return defaultValue;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'restaurant_id': restaurantId,
      'categoria_id': categoriaId,
      'nombre': nombre,
      'descripcion': descripcion,
      'precio': precio,
      'imagen_url': imagenUrl,
      'cloudinary_public_id': cloudinaryPublicId,
      'imagen_width': imagenWidth,
      'imagen_height': imagenHeight,
      'imagen_bytes': imagenBytes,
      'imagen_version': imagenVersion,
      'imagen_local_cache_path': imagenLocalCachePath,
      'disponible': disponible ? 1 : 0,
      'activo': activo ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Convierte variantes relacionadas a Map list para inserción batch.
  List<Map<String, dynamic>> variantesToMapList() {
    return variantes.map((v) => VarianteModel.fromEntity(v).toMap()).toList();
  }

  factory ProductoModel.fromEntity(Producto entity) {
    return ProductoModel(
      id: entity.id,
      restaurantId: entity.restaurantId,
      categoriaId: entity.categoriaId,
      nombre: entity.nombre,
      descripcion: entity.descripcion,
      precio: entity.precio,
      imagenUrl: entity.imagenUrl,
      cloudinaryPublicId: entity.cloudinaryPublicId,
      imagenWidth: entity.imagenWidth,
      imagenHeight: entity.imagenHeight,
      imagenBytes: entity.imagenBytes,
      imagenVersion: entity.imagenVersion,
      imagenLocalCachePath: entity.imagenLocalCachePath,
      disponible: entity.disponible,
      activo: entity.activo,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
      variantes: entity.variantes,
    );
  }
}
