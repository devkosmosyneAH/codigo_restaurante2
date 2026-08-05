import 'package:restaurant_app/Presentation/entities/pagina_publica/public_gallery_image.dart';

class PublicGalleryImageModel extends PublicGalleryImage {
  const PublicGalleryImageModel({
    required super.id,
    required super.restaurantId,
    required super.tipo,
    required super.imageUrl,
    required super.cloudinaryPublicId,
    required super.width,
    required super.height,
    required super.bytes,
    required super.version,
    required super.orden,
    required super.activo,
    required super.altText,
    required super.createdAt,
    required super.updatedAt,
  });

  factory PublicGalleryImageModel.fromMap(Map<String, dynamic> map) {
    DateTime parseDate(dynamic value) => value is String
        ? DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0)
        : DateTime.fromMillisecondsSinceEpoch((value as num?)?.toInt() ?? 0);
    return PublicGalleryImageModel(
      id: map['id'] as String,
      restaurantId: map['restaurant_id'] as String,
      tipo: map['tipo'] as String,
      imageUrl: map['image_url'] as String? ?? '',
      cloudinaryPublicId: map['cloudinary_public_id'] as String? ?? '',
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
      bytes: (map['bytes'] as num?)?.toInt() ?? 0,
      version: (map['version'] as num?)?.toInt() ?? 0,
      orden: (map['orden'] as num?)?.toInt() ?? 0,
      activo: map['activo'] is bool ? map['activo'] as bool : map['activo'] == 1,
      altText: map['alt_text'] as String? ?? '',
      createdAt: parseDate(map['created_at']),
      updatedAt: parseDate(map['updated_at']),
    );
  }

  factory PublicGalleryImageModel.fromEntity(PublicGalleryImage image) =>
      PublicGalleryImageModel(
        id: image.id,
        restaurantId: image.restaurantId,
        tipo: image.tipo,
        imageUrl: image.imageUrl,
        cloudinaryPublicId: image.cloudinaryPublicId,
        width: image.width,
        height: image.height,
        bytes: image.bytes,
        version: image.version,
        orden: image.orden,
        activo: image.activo,
        altText: image.altText,
        createdAt: image.createdAt,
        updatedAt: image.updatedAt,
      );

  Map<String, dynamic> toMap() => {
    'id': id,
    'restaurant_id': restaurantId,
    'tipo': tipo,
    'image_url': imageUrl,
    'cloudinary_public_id': cloudinaryPublicId,
    'width': width,
    'height': height,
    'bytes': bytes,
    'version': version,
    'orden': orden,
    'activo': activo ? 1 : 0,
    'alt_text': altText,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}
