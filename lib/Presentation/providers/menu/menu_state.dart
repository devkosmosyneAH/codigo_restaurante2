import 'package:restaurant_app/Presentation/entities/menu/categoria.dart';
import 'package:restaurant_app/Presentation/entities/menu/producto.dart';

/// Estado compartido del menú administrativo y público.
class MenuState {
  final List<Categoria> categorias;
  final List<Producto> productos;
  final String? categoriaSeleccionadaId;
  final bool isLoading;
  final String? errorMessage;

  const MenuState({
    this.categorias = const [],
    this.productos = const [],
    this.categoriaSeleccionadaId,
    this.isLoading = false,
    this.errorMessage,
  });

  MenuState copyWith({
    List<Categoria>? categorias,
    List<Producto>? productos,
    String? categoriaSeleccionadaId,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    bool clearCategoria = false,
  }) {
    return MenuState(
      categorias: categorias ?? this.categorias,
      productos: productos ?? this.productos,
      categoriaSeleccionadaId: clearCategoria
          ? null
          : (categoriaSeleccionadaId ?? this.categoriaSeleccionadaId),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  /// Productos filtrados por la categoría seleccionada.
  List<Producto> get productosFiltrados {
    if (categoriaSeleccionadaId == null) return productos;
    return productos
        .where((p) => p.categoriaId == categoriaSeleccionadaId)
        .toList();
  }

  /// Productos disponibles.
  List<Producto> get productosDisponibles =>
      productos.where((p) => p.disponible).toList();

  int get totalProductos => productos.length;
  int get totalCategorias => categorias.length;
}
