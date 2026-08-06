import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseAppInitializer {
  const FirebaseAppInitializer._();

  static Future<void>? _initialization;

  static Future<void> initialize() async {
    if (Firebase.apps.isNotEmpty) return;

    final pending = _initialization;
    if (pending != null) {
      await pending;
      return;
    }

    final current = _initialize();
    _initialization = current;
    try {
      await current;
    } finally {
      if (identical(_initialization, current)) _initialization = null;
    }
  }

  static Future<void> _initialize() async {
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'AIzaSyCyMYO7DLe4WlJeGeBkOJqjV5uHXHClFHQ',
          appId: '1:1062396228506:web:9ae562109a517ed7a38023',
          messagingSenderId: '1062396228506',
          projectId: 'restaura-a1e34',
          authDomain: 'restaura-a1e34.firebaseapp.com',
          databaseURL: 'https://restaura-a1e34-default-rtdb.firebaseio.com',
          storageBucket: 'restaura-a1e34.firebasestorage.app',
        ),
      );
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      return;
    }

    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSyCyMYO7DLe4WlJeGeBkOJqjV5uHXHClFHQ',
        appId: '1:1062396228506:android:9ae562109a517ed7a38023',
        messagingSenderId: '1062396228506',
        projectId: 'restaura-a1e34',
        authDomain: 'restaura-a1e34.firebaseapp.com',
        databaseURL: 'https://restaura-a1e34-default-rtdb.firebaseio.com',
        storageBucket: 'restaura-a1e34.firebasestorage.app',
      ),
    );
  }
}
