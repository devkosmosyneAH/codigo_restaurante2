class PublicGalleryImage {
  final String id;
  final String restaurantId;
  final String tipo;
  final String imageUrl;
  final String cloudinaryPublicId;
  final int width;
  final int height;
  final int bytes;
  final int version;
  final int orden;
  final bool activo;
  final String altText;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PublicGalleryImage({
    required this.id,
    required this.restaurantId,
    required this.tipo,
    required this.imageUrl,
    required this.cloudinaryPublicId,
    required this.width,
    required this.height,
    required this.bytes,
    required this.version,
    required this.orden,
    required this.activo,
    required this.altText,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isCover => tipo == 'portada';

  PublicGalleryImage copyWith({
    String? imageUrl,
    String? cloudinaryPublicId,
    int? width,
    int? height,
    int? bytes,
    int? version,
    int? orden,
    bool? activo,
    String? altText,
    DateTime? updatedAt,
  }) => PublicGalleryImage(
    id: id,
    restaurantId: restaurantId,
    tipo: tipo,
    imageUrl: imageUrl ?? this.imageUrl,
    cloudinaryPublicId: cloudinaryPublicId ?? this.cloudinaryPublicId,
    width: width ?? this.width,
    height: height ?? this.height,
    bytes: bytes ?? this.bytes,
    version: version ?? this.version,
    orden: orden ?? this.orden,
    activo: activo ?? this.activo,
    altText: altText ?? this.altText,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
