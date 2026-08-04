import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restaurant_app/Presentation/core/constants/app_constants.dart';
import 'package:restaurant_app/Presentation/providers/menu/menu_state.dart';
import 'package:restaurant_app/Presentation/services/menu/public_menu_service.dart';

class PublicMenuNotifier extends StateNotifier<MenuState> {
  PublicMenuNotifier({PublicMenuService? service})
    : _service = service ?? PublicMenuService(),
      super(const MenuState());

  final PublicMenuService _service;
  StreamSubscription<PublicMenuSnapshot>? _subscription;
  String? _restaurantId;

  Future<void> load([String? restaurantId]) async {
    if (_subscription != null) return;
    _restaurantId = AppConstants.restaurantId;
    state = state.copyWith(isLoading: true, clearError: true);
    _subscription = _service
        .watch(_restaurantId!)
        .listen(
          (snapshot) {
            state = state.copyWith(
              isLoading: false,
              categorias: snapshot.categorias,
              productos: snapshot.productos,
              clearError: true,
            );
          },
          onError: (Object error, StackTrace stack) {
            state = state.copyWith(
              isLoading: false,
              errorMessage: error.toString(),
            );
          },
        );
  }

  void seleccionarCategoria(String? id) {
    state = state.copyWith(
      categoriaSeleccionadaId: id,
      clearCategoria: id == null,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final publicMenuProvider = StateNotifierProvider<PublicMenuNotifier, MenuState>(
  (ref) => PublicMenuNotifier(),
);
