import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:restaurant_app/Presentation/core/config/app_environment.dart';

/// Resultado normalizado de una subida unsigned a Cloudinary.
class CloudinaryUploadResult {
  final String secureUrl;
  final String publicId;
  final int width;
  final int height;
  final int bytes;
  final int version;

  const CloudinaryUploadResult({
    required this.secureUrl,
    required this.publicId,
    required this.width,
    required this.height,
    required this.bytes,
    required this.version,
  });

  factory CloudinaryUploadResult.fromJson(Map<String, dynamic> json) {
    final secureUrl = (json['secure_url'] ?? json['url'] ?? '').toString();
    final publicId = (json['public_id'] ?? '').toString();
    if (secureUrl.trim().isEmpty || publicId.trim().isEmpty) {
      throw const CloudinaryUploadException(
        'Cloudinary no devolvió una URL o public_id válido.',
      );
    }

    return CloudinaryUploadResult(
      secureUrl: secureUrl,
      publicId: publicId,
      width: _asInt(json['width']),
      height: _asInt(json['height']),
      bytes: _asInt(json['bytes']),
      version: _asInt(json['version']),
    );
  }

  static int _asInt(Object? value) => value is num ? value.toInt() : 0;
}

enum CloudinaryUploadKind { menu, publicPage }

class CloudinaryUploadException implements Exception {
  final String message;
  const CloudinaryUploadException(this.message);

  @override
  String toString() => message;
}

/// Cliente mínimo para subidas unsigned desde Flutter.
///
/// El upload preset es público por diseño; nunca se incluye API Secret.
class CloudinaryUploadService {
  const CloudinaryUploadService();

  Future<CloudinaryUploadResult> upload({
    required Uint8List bytes,
    required String mimeType,
    required CloudinaryUploadKind kind,
    String? publicId,
  }) async {
    if (bytes.isEmpty) {
      throw const CloudinaryUploadException('La imagen está vacía.');
    }
    final cloudName = AppEnvironment.cloudinaryCloudName;
    final uploadPreset = switch (kind) {
      CloudinaryUploadKind.menu => AppEnvironment.cloudinaryMenuUploadPreset,
      CloudinaryUploadKind.publicPage =>
        AppEnvironment.cloudinaryPublicUploadPreset,
    };
    if (cloudName.isEmpty || uploadPreset.isEmpty) {
      throw const CloudinaryUploadException(
        'Cloudinary no está configurado. Define CLOUDINARY_CLOUD_NAME y los upload presets.',
      );
    }

    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
    );
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = uploadPreset
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: 'restaurant_image.${_extensionForMime(mimeType)}',
        ),
      );
    if (publicId != null && publicId.trim().isNotEmpty) {
      request.fields['public_id'] = publicId.trim();
    }

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      payload = <String, dynamic>{};
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = payload['error'] is Map
          ? (payload['error'] as Map)['message']?.toString()
          : null;
      throw CloudinaryUploadException(
        detail == null || detail.isEmpty
            ? 'Cloudinary rechazó la subida (${response.statusCode}).'
            : 'Cloudinary rechazó la subida: $detail',
      );
    }
    return CloudinaryUploadResult.fromJson(payload);
  }

  String _extensionForMime(String mimeType) {
    switch (mimeType.toLowerCase()) {
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      default:
        return 'jpg';
    }
  }
}
