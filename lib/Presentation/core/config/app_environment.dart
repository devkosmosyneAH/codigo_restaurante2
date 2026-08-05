/// Valores de integraciones externas inyectados con `--dart-define`.
///
/// El API Secret de Cloudinary no se usa ni se incluye en Flutter. Las
/// subidas usan exclusivamente presets unsigned.
class AppEnvironment {
  AppEnvironment._();

  static const String _defaultRealtimeDatabaseUrl =
      'https://restaura-a1e34-default-rtdb.firebaseio.com';

  static const String _cloudinaryCloudName = String.fromEnvironment(
    'CLOUDINARY_CLOUD_NAME',
    defaultValue: 'ttviexhh',
  );
  static const String _cloudinaryMenuUploadPreset = String.fromEnvironment(
    'CLOUDINARY_MENU_UPLOAD_PRESET',
    defaultValue: 'restaurante_menu_unsigned',
  );
  static const String _cloudinaryPublicUploadPreset = String.fromEnvironment(
    'CLOUDINARY_PUBLIC_UPLOAD_PRESET',
    defaultValue: 'restaurante_public_unsigned',
  );

  static const String _firebaseDatabaseUrl = String.fromEnvironment(
    'FIREBASE_DATABASE_URL',
    defaultValue: '',
  );
  static const String _realtimeDatabaseUrl = String.fromEnvironment(
    'REALTIME_DATABASE_URL',
    defaultValue: '',
  );
  static const String _firebaseRtdbUrl = String.fromEnvironment(
    'FIREBASE_RTDB_URL',
    defaultValue: '',
  );
  static const String _legacyFirebaseDatabaseUrl = String.fromEnvironment(
    'REACT_APP_FIREBASE_DATABASE_URL',
    defaultValue: '',
  );
  static const String _viteFirebaseDatabaseUrl = String.fromEnvironment(
    'VITE_FIREBASE_DATABASE_URL',
    defaultValue: '',
  );
  static const String _nextFirebaseDatabaseUrl = String.fromEnvironment(
    'NEXT_PUBLIC_FIREBASE_DATABASE_URL',
    defaultValue: '',
  );

  static String get cloudinaryCloudName => _cloudinaryCloudName.trim();
  static String get cloudinaryMenuUploadPreset =>
      _cloudinaryMenuUploadPreset.trim();
  static String get cloudinaryPublicUploadPreset =>
      _cloudinaryPublicUploadPreset.trim();

  static bool get isCloudinaryConfigured =>
      cloudinaryCloudName.isNotEmpty &&
      cloudinaryMenuUploadPreset.isNotEmpty &&
      cloudinaryPublicUploadPreset.isNotEmpty;

  static String get realtimeDatabaseUrl {
    for (final value in [
      _firebaseDatabaseUrl,
      _realtimeDatabaseUrl,
      _firebaseRtdbUrl,
      _viteFirebaseDatabaseUrl,
      _nextFirebaseDatabaseUrl,
      _legacyFirebaseDatabaseUrl,
    ]) {
      if (value.trim().isNotEmpty) return _normalizeBaseUrl(value);
    }
    return _defaultRealtimeDatabaseUrl;
  }

  static bool get isRealtimeDatabaseConfigured => realtimeDatabaseUrl.isNotEmpty;

  static String _normalizeBaseUrl(String value) =>
      value.trim().replaceFirst(RegExp(r'/+$'), '');
}
