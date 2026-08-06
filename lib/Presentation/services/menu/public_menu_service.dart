import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:restaurant_app/Presentation/Models/menu/categoria_model.dart';
import 'package:restaurant_app/Presentation/Models/menu/producto_model.dart';
import 'package:restaurant_app/Presentation/Models/menu/variante_model.dart';
import 'package:restaurant_app/Presentation/entities/menu/categoria.dart';
import 'package:restaurant_app/Presentation/entities/menu/producto.dart';
import 'package:restaurant_app/Presentation/entities/menu/variante.dart';
import 'package:restaurant_app/Presentation/core/firebase/firebase_initializer.dart';

/// Fuente pública de menú. Solo usa lecturas de Firebase y nunca consulta
/// Firebase Authentication, por lo que puede consumirse desde un QR.
class PublicMenuSnapshot {
  final List<Categoria> categorias;
  final List<Producto> productos;

  const PublicMenuSnapshot({required this.categorias, required this.productos});
}

/// Lee el contenido público del menú sin requerir autenticación.
class PublicMenuService {
  PublicMenuService({FirebaseDatabase? database}) : _database = database;

  final FirebaseDatabase? _database;

  FirebaseDatabase get _firebaseDatabase =>
      _database ?? FirebaseDatabase.instance;

  /// Escucha únicamente las tres colecciones públicas necesarias. Esto evita
  /// sondear toda la base cada cierto tiempo y actualiza la UI cuando Firebase
  /// emite un cambio real.
  Stream<PublicMenuSnapshot> watch(String restaurantId) {
    final controller = StreamController<PublicMenuSnapshot>.broadcast();
    DatabaseEvent? categoriasEvent;
    DatabaseEvent? productosEvent;
    DatabaseEvent? variantesEvent;
    final subscriptions = <StreamSubscription<DatabaseEvent>>[];
    Timer? firstSnapshotTimer;
    var hasEmittedSnapshot = false;

    void emitIfReady() {
      if (categoriasEvent == null ||
          productosEvent == null ||
          variantesEvent == null ||
          controller.isClosed) {
        return;
      }
      controller.add(
        _snapshotFromValues(
          categoriasEvent!.snapshot.value,
          productosEvent!.snapshot.value,
          variantesEvent!.snapshot.value,
        ),
      );
      hasEmittedSnapshot = true;
      firstSnapshotTimer?.cancel();
    }

    controller.onListen = () async {
      try {
        // La ruta pública puede aparecer antes de que Firebase termine de
        // inicializarse globalmente. Esperar aquí evita una pantalla de error.
        if (_database == null) {
          await FirebaseAppInitializer.initialize();
        }
        if (controller.isClosed) return;

        final root = _firebaseDatabase
            .ref()
            .child('restaurantes')
            .child(restaurantId);
        firstSnapshotTimer = Timer(const Duration(seconds: 12), () {
          if (!hasEmittedSnapshot && !controller.isClosed) {
            controller.addError(
              TimeoutException('El menú tardó demasiado en responder.'),
            );
          }
        });

        subscriptions.add(
          root.child('categorias').onValue.listen((event) {
            categoriasEvent = event;
            emitIfReady();
          }, onError: controller.addError),
        );
        subscriptions.add(
          root.child('productos').onValue.listen((event) {
            productosEvent = event;
            emitIfReady();
          }, onError: controller.addError),
        );
        subscriptions.add(
          root.child('variantes').onValue.listen((event) {
            variantesEvent = event;
            emitIfReady();
          }, onError: controller.addError),
        );
      } catch (error, stack) {
        if (!controller.isClosed) controller.addError(error, stack);
      }
    };
    controller.onCancel = () async {
      firstSnapshotTimer?.cancel();
      await Future.wait(
        subscriptions.map((subscription) => subscription.cancel()),
      );
      subscriptions.clear();
    };
    return controller.stream;
  }

  Future<PublicMenuSnapshot> fetch(String restaurantId) async {
    if (_database == null) {
      await FirebaseAppInitializer.initialize();
    }
    final root = _firebaseDatabase
        .ref()
        .child('restaurantes')
        .child(restaurantId);
    final results = await Future.wait([
      root.child('categorias').once(),
      root.child('productos').once(),
      root.child('variantes').once(),
    ]);

    return _snapshotFromValues(
      results[0].snapshot.value,
      results[1].snapshot.value,
      results[2].snapshot.value,
    );
  }

  PublicMenuSnapshot _snapshotFromValues(
    dynamic categoriasRaw,
    dynamic productosRaw,
    dynamic variantesRaw,
  ) {
    final categorias = _parseCategorias(categoriasRaw);
    final variantes = _parseVariantes(variantesRaw);
    final productos = _parseProductos(productosRaw, variantes);
    return PublicMenuSnapshot(categorias: categorias, productos: productos);
  }

  List<Categoria> _parseCategorias(dynamic raw) {
    final output = <Categoria>[];
    for (final map in _maps(raw)) {
      if (_isDeleted(map)) continue;
      if (!_isActive(map)) continue;
      final normalized = _normalize(
        map,
        defaults: {
          'id': map['id'] ?? '',
          'restaurant_id': map['restaurant_id'] ?? '',
          'nombre': map['nombre'] ?? 'Sin nombre',
          'activo': 1,
        },
      );
      try {
        output.add(CategoriaModel.fromMap(normalized));
      } catch (error) {
        _reportMalformedRecord('categoría', map, error);
      }
    }
    output.sort(
      (a, b) => a.orden != b.orden
          ? a.orden.compareTo(b.orden)
          : a.nombre.compareTo(b.nombre),
    );
    return output;
  }

  Map<String, List<Variante>> _parseVariantes(dynamic raw) {
    final output = <String, List<Variante>>{};
    for (final map in _maps(raw)) {
      if (_isDeleted(map)) continue;
      if (!_isActive(map)) continue;
      final normalized = _normalize(
        map,
        defaults: {
          'id': map['id'] ?? '',
          'producto_id': map['producto_id'] ?? '',
          'nombre': map['nombre'] ?? '',
          'precio': map['precio'] ?? 0,
          'activo': 1,
        },
      );
      try {
        final variante = VarianteModel.fromMap(normalized);
        (output[variante.productoId] ??= []).add(variante);
      } catch (error) {
        _reportMalformedRecord('variante', map, error);
      }
    }
    for (final values in output.values) {
      values.sort((a, b) => a.precio.compareTo(b.precio));
    }
    return output;
  }

  List<Producto> _parseProductos(
    dynamic raw,
    Map<String, List<Variante>> variantes,
  ) {
    final output = <Producto>[];
    for (final map in _maps(raw)) {
      if (_isDeleted(map)) continue;
      if (!_isActive(map) || !_isAvailable(map)) continue;
      final normalized = _normalize(
        map,
        defaults: {
          'id': map['id'] ?? '',
          'restaurant_id': map['restaurant_id'] ?? '',
          'categoria_id': map['categoria_id'] ?? '',
          'nombre': map['nombre'] ?? 'Sin nombre',
          'precio': map['precio'] ?? 0,
          'activo': 1,
          'disponible': 1,
        },
      );
      try {
        final id = normalized['id'].toString();
        output.add(
          ProductoModel.fromMap(
            normalized,
            variantes: variantes[id] ?? const <Variante>[],
          ),
        );
      } catch (error) {
        _reportMalformedRecord('producto', map, error);
      }
    }
    output.sort((a, b) => a.nombre.compareTo(b.nombre));
    return output;
  }

  Iterable<Map<String, dynamic>> _maps(dynamic raw) sync* {
    if (raw is! Map) return;
    for (final entry in raw.entries) {
      if (entry.value is! Map) continue;
      final map = Map<String, dynamic>.from(entry.value as Map);
      map.putIfAbsent('id', () => entry.key.toString());
      yield map;
    }
  }

  bool _isActive(Map<String, dynamic> map) {
    final value = map['activo'];
    if (value == null) return true;
    if (value is bool) return value;
    if (value is num) return value != 0;
    return value.toString().toLowerCase() != 'false' && value.toString() != '0';
  }

  bool _isDeleted(Map<String, dynamic> map) {
    final value = map['deleted_at'];
    return value != null && value.toString().trim().isNotEmpty;
  }

  bool _isAvailable(Map<String, dynamic> map) {
    final value = map['disponible'];
    if (value == null) return true;
    if (value is bool) return value;
    if (value is num) return value != 0;
    return value.toString().toLowerCase() != 'false' && value.toString() != '0';
  }

  Map<String, dynamic> _normalize(
    Map<String, dynamic> source, {
    required Map<String, dynamic> defaults,
  }) {
    final map = {...defaults, ...source};
    for (final key in ['activo', 'disponible']) {
      final value = map[key];
      if (value is bool) map[key] = value ? 1 : 0;
      if (value is String) {
        map[key] = value.toLowerCase() == 'true' || value == '1' ? 1 : 0;
      }
    }
    for (final key in ['created_at', 'updated_at']) {
      final value = map[key];
      if (value is num) {
        map[key] = DateTime.fromMillisecondsSinceEpoch(
          value.toInt(),
        ).toIso8601String();
      } else if (value == null || value.toString().trim().isEmpty) {
        map[key] = DateTime.fromMillisecondsSinceEpoch(0).toIso8601String();
      }
    }
    return map;
  }

  void _reportMalformedRecord(
    String entity,
    Map<String, dynamic> record,
    Object error,
  ) {
    debugPrint(
      'PublicMenuService: se omitió $entity inválido '
      '(${record['id'] ?? 'sin-id'}): $error',
    );
  }
}
