import 'package:restaurant_app/Presentation/core/constants/app_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ActivationMode { none, demo, full }

class ActivationStatus {
  const ActivationStatus({
    required this.mode,
    required this.evaluatedAt,
    this.activatedAt,
    this.expiresAt,
  });

  final ActivationMode mode;
  final DateTime evaluatedAt;
  final DateTime? activatedAt;
  final DateTime? expiresAt;

  factory ActivationStatus.empty({DateTime? now}) {
    return ActivationStatus(
      mode: ActivationMode.none,
      evaluatedAt: now ?? DateTime.now(),
    );
  }

  bool get isDemo => mode == ActivationMode.demo;
  bool get isFull => mode == ActivationMode.full;

  bool get isExpired {
    return isDemo && expiresAt != null && !expiresAt!.isAfter(evaluatedAt);
  }

  bool get canAccessApp => isFull || (isDemo && !isExpired);

  int get remainingDays {
    if (!isDemo || expiresAt == null || isExpired) return 0;

    final remaining = expiresAt!.difference(evaluatedAt);
    final wholeDays = remaining.inDays;
    final hasPartialDay = remaining - Duration(days: wholeDays) > Duration.zero;

    return hasPartialDay ? wholeDays + 1 : wholeDays;
  }

  String get message {
    if (isFull) {
      return 'Licencia fija activa. La app está desbloqueada.';
    }
    if (isDemo && !isExpired) {
      return 'Demo activa. Quedan $remainingDays día(s) para probar la app.';
    }
    if (isDemo && isExpired) {
      return 'La demo de 7 días ya venció. Ingresa el código fijo para continuar.';
    }
    return 'Ingresa un código de activación para habilitar la demo o la licencia fija.';
  }
}

class ActivationService {
  static const String _modeKey = 'activation_mode';
  static const String _activatedAtKey = 'activation_activated_at';
  static const String _expiresAtKey = 'activation_expires_at';
  static const String _failedAttemptsKey = 'activation_failed_attempts';
  static const String _lockUntilKey = 'activation_lock_until';
  static const String _legacyLastCodeKey = 'activation_last_code';

  Future<ActivationStatus> getStatus({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    // Elimina códigos almacenados por versiones antiguas.
    await prefs.remove(_legacyLastCodeKey);
    final evaluatedAt = now ?? DateTime.now();
    final rawMode = prefs.getString(_modeKey);

    final mode = switch (rawMode) {
      'demo' => ActivationMode.demo,
      'full' => ActivationMode.full,
      _ => ActivationMode.none,
    };

    return ActivationStatus(
      mode: mode,
      evaluatedAt: evaluatedAt,
      activatedAt: _parseDate(prefs.getString(_activatedAtKey)),
      expiresAt: _parseDate(prefs.getString(_expiresAtKey)),
    );
  }

  Future<String?> activateWithCode(String code, {DateTime? now}) async {
    final normalized = code.trim().toUpperCase();
    final current = now ?? DateTime.now();
    final prefs = await SharedPreferences.getInstance();

    final lockRaw = prefs.getString(_lockUntilKey);
    final lockUntil = lockRaw == null ? null : DateTime.tryParse(lockRaw);
    if (lockUntil != null && lockUntil.isAfter(current)) {
      return 'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.';
    }

    if (normalized == AppConstants.demoActivationCode.toUpperCase()) {
      await prefs.setString(_modeKey, 'demo');
      await prefs.setString(_activatedAtKey, current.toIso8601String());
      await prefs.setString(
        _expiresAtKey,
        current.add(AppConstants.demoActivationDuration).toIso8601String(),
      );
      await _clearFailedAttempts(prefs);
      return null;
    }

    if (normalized == AppConstants.fullActivationCode.toUpperCase()) {
      await prefs.setString(_modeKey, 'full');
      await prefs.setString(_activatedAtKey, current.toIso8601String());
      await prefs.remove(_expiresAtKey);
      await _clearFailedAttempts(prefs);
      return null;
    }

    final attempts = (prefs.getInt(_failedAttemptsKey) ?? 0) + 1;
    await prefs.setInt(_failedAttemptsKey, attempts);
    if (attempts >= 5) {
      await prefs.setString(
        _lockUntilKey,
        current.add(const Duration(minutes: 5)).toIso8601String(),
      );
      return 'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.';
    }
    return 'El código ingresado no es válido.';
  }

  Future<void> clearActivation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_modeKey);
    await prefs.remove(_activatedAtKey);
    await prefs.remove(_expiresAtKey);
    await _clearFailedAttempts(prefs);
  }

  Future<void> _clearFailedAttempts(SharedPreferences prefs) async {
    await prefs.remove(_failedAttemptsKey);
    await prefs.remove(_lockUntilKey);
    await prefs.remove(_legacyLastCodeKey);
  }

  DateTime? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}
