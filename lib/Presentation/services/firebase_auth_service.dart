import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:restaurant_app/Presentation/core/constants/app_constants.dart';
import 'package:restaurant_app/Presentation/core/database/database_helper.dart';
import 'package:restaurant_app/Presentation/services/Auth/auth_service.dart';
import 'package:restaurant_app/Presentation/services/session_service.dart';

/// Servicio ÚNICO para autenticación con Firebase.
class FirebaseAuthService {
  FirebaseAuthService._({
    FirebaseAuth? firebaseAuth,
    DatabaseReference? databaseReference,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _database = databaseReference ?? FirebaseDatabase.instance.ref();

  static FirebaseAuthService? _instance;

  /// Obtiene la instancia única de FirebaseAuthService.
  static FirebaseAuthService get instance {
    _instance ??= FirebaseAuthService._();
    return _instance!;
  }

  /// Para pruebas: permite inyectar una instancia custom.
  @visibleForTesting
  static void setInstance(FirebaseAuthService instance) {
    _instance = instance;
  }

  /// Para pruebas: resetea la instancia.
  @visibleForTesting
  static void reset() {
    _instance = null;
  }

  final FirebaseAuth _firebaseAuth;
  final DatabaseReference _database;

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();
  User? get currentUser => _firebaseAuth.currentUser;
  bool get isSignedIn => currentUser != null;

  Future<String?> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await _syncUserToRealtimeDatabase(credential.user);
      await _saveSessionFromFirebase(credential.user);
      return null;
    } on FirebaseAuthException catch (e) {
      return _mapAuthError(e.code);
    } catch (e) {
      debugPrint('firebase_auth.sign_in_failed: $e');
      return 'No fue posible iniciar sesión en este momento.';
    }
  }

  Future<String?> registerWithEmailAndPassword({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String role,
    required String permission,
  }) async {
    try {
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = credential.user;
      if (user == null) {
        return 'No se pudo crear la cuenta.';
      }

      await user.updateDisplayName('$firstName $lastName'.trim());
      await _syncUserToRealtimeDatabase(
        user,
        extraData: {
          'name': firstName,
          'lastname': lastName,
          'role': role,
          'permission': permission,
          'restaurantId': AppConstants.defaultRestaurantId,
        },
      );
      await _saveSessionFromFirebase(user);
      return null;
    } on FirebaseAuthException catch (e) {
      return _mapAuthError(e.code);
    } catch (e) {
      debugPrint('firebase_auth.register_failed: $e');
      return 'No fue posible crear la cuenta.';
    }
  }

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
    await SessionService.logout();
  }

  Future<Map<String, dynamic>?> restoreSessionFromFirebase() async {
    final user =
        currentUser ??
        await _firebaseAuth
            .authStateChanges()
            .firstWhere((u) => u != null, orElse: () => null)
            .timeout(const Duration(seconds: 5), onTimeout: () => null);

    if (user == null) {
      await SessionService.logout();
      return null;
    }

    await _saveSessionFromFirebase(user);
    return await SessionService.getCurrentUserSession();
  }

  Future<Map<String, dynamic>?> getCurrentAuthenticatedUser() async {
    final user = currentUser;
    if (user == null) return null;

    final existingSession = await SessionService.getCurrentUserSession();
    if (existingSession != null) return existingSession;

    final profile = await _syncUserToRealtimeDatabase(user);
    final resolvedRole = await _resolveRole(user, profile);
    final sessionData = {
      'id': user.uid,
      'uid': user.uid,
      'email': user.email,
      'name': user.displayName ?? profile?['name'] ?? 'Usuario',
      'role': resolvedRole,
      'permission': profile?['permission'] ?? 'operador',
      'restaurantId': AppConstants.restaurantId,
    };
    await SessionService.saveUserSession(sessionData);
    return sessionData;
  }

  Future<void> _saveSessionFromFirebase(User? user) async {
    if (user == null) {
      await SessionService.logout();
      return;
    }

    final profile = await _syncUserToRealtimeDatabase(user);
    final resolvedRole = await _resolveRole(user, profile);
    final sessionData = {
      'uid': user.uid,
      'email': user.email,
      'name': user.displayName ?? profile?['name'] ?? 'Usuario',
      'role': resolvedRole,
      'permission': profile?['permission'] ?? 'operador',
      'restaurantId': AppConstants.restaurantId,
    };
    await SessionService.saveUserSession(sessionData);

    final localUser = await AuthService().getUserByUid(user.uid);
    if (localUser != null) {
      await AuthService().updateUser(user.uid, {
        'email': user.email ?? localUser['email'],
        'name': profile?['name'] ?? localUser['name'],
        'lastname': profile?['lastname'] ?? localUser['lastname'],
        'role': profile?['role'] ?? localUser['role'],
        'permission': profile?['permission'] ?? localUser['permission'],
      });
    }
  }

  /// Obtiene el rol administrado por la pantalla de Usuarios.
  ///
  /// La tabla local es la fuente operativa para este restaurante: el
  /// administrador puede crear o editar el usuario por correo y el siguiente
  /// inicio de sesión aplicará ese rol. El perfil remoto solo se usa como
  /// respaldo para cuentas todavía no registradas localmente.
  Future<String> _resolveRole(
    User user,
    Map<String, dynamic>? profile,
  ) async {
    final email = user.email?.trim();
    if (email != null && email.isNotEmpty) {
      try {
        final rows = await DatabaseHelper.instance.query(
          'usuarios',
          where: 'lower(email) = lower(?) AND restaurant_id = ? AND activo = 1',
          whereArgs: [email, AppConstants.restaurantId],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          final localRole = rows.first['rol']?.toString().trim();
          if (localRole != null && localRole.isNotEmpty) return localRole;
        }
      } catch (error) {
        debugPrint('firebase_auth.local_role_lookup_failed: $error');
      }
    }

    final remoteRole = profile?['role']?.toString().trim();
    return remoteRole == null || remoteRole.isEmpty ? 'mesero' : remoteRole;
  }

  Future<Map<String, dynamic>?> _syncUserToRealtimeDatabase(
    User? user, {
    Map<String, dynamic>? extraData,
  }) async {
    if (user == null) return null;

    final profileRef = _database.child('users').child(user.uid);
    final snapshot = await profileRef.once();
    final profile = <String, dynamic>{
      'uid': user.uid,
      'email': user.email,
      'displayName': user.displayName,
      'photoURL': user.photoURL,
      'updatedAt': ServerValue.timestamp,
      if (extraData != null) ...extraData,
    };

    if (snapshot.snapshot.exists) {
      final existingData = Map<String, dynamic>.from(
        (snapshot.snapshot.value as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{},
      );
      profile.addAll(existingData);
      profile['uid'] = user.uid;
      profile['email'] = profile['email'] ?? user.email;
      profile['displayName'] = profile['displayName'] ?? user.displayName;
    }

    await profileRef.set(profile);
    return profile;
  }

  static String _mapAuthError(String code) {
    return switch (code) {
      'invalid-email' => 'Las credenciales ingresadas no son válidas.',
      'user-disabled' => 'No fue posible iniciar sesión con esas credenciales.',
      'user-not-found' => 'Las credenciales ingresadas no son válidas.',
      'wrong-password' => 'Las credenciales ingresadas no son válidas.',
      'email-already-in-use' => 'No fue posible completar el registro.',
      'weak-password' => 'La contraseña no cumple los requisitos de seguridad.',
      'operation-not-allowed' =>
        'El método de autenticación no está habilitado.',
      _ => 'No fue posible completar la solicitud de autenticación.',
    };
  }
}
