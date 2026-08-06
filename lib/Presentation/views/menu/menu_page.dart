import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:restaurant_app/Presentation/config/routes/app_router.dart';
import 'package:restaurant_app/Presentation/providers/menu/menu_provider.dart';
import 'package:restaurant_app/Presentation/widgets/menu/categoria_form_dialog.dart';
import 'package:restaurant_app/Presentation/widgets/menu/producto_card.dart';
import 'package:restaurant_app/Presentation/widgets/menu/producto_form_dialog.dart';
import 'package:restaurant_app/Presentation/widgets/skeleton_loader.dart';

/// Administración del menú. Las imágenes se gestionan mediante Cloudinary;
/// Firebase conserva el producto y sus metadatos.
class MenuPage extends ConsumerStatefulWidget {
  const MenuPage({super.key});

  @override
  ConsumerState<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends ConsumerState<MenuPage>
    with TickerProviderStateMixin {
  TabController? _tabs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(menuProvider.notifier).loadMenu();
    });
  }

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  void _syncTabs(int count) {
    final length = count + 1;
    if (_tabs != null && _tabs!.length == length) return;
    _tabs?.dispose();
    _tabs = TabController(length: length, vsync: this);
    _tabs!.addListener(() {
      if (_tabs!.indexIsChanging) return;
      final state = ref.read(menuProvider);
      final index = _tabs!.index;
      ref
          .read(menuProvider.notifier)
          .seleccionarCategoria(
            index == 0 ? null : state.categorias[index - 1].id,
          );
    });
  }

  Future<void> _createCategory() async {
    final category = await CategoriaFormDialog.show(context);
    if (!mounted || category == null) return;
    final ok = await ref.read(menuProvider.notifier).crearCategoria(category);
    if (!ok && mounted) _showError(ref.read(menuProvider).errorMessage);
  }

  Future<void> _editCategory(int index) async {
    final state = ref.read(menuProvider);
    if (index < 0 || index >= state.categorias.length) return;
    final updated = await CategoriaFormDialog.show(
      context,
      categoria: state.categorias[index],
    );
    if (!mounted || updated == null) return;
    final ok = await ref
        .read(menuProvider.notifier)
        .actualizarCategoria(updated);
    if (!ok && mounted) _showError(ref.read(menuProvider).errorMessage);
  }

  Future<void> _deleteCategory(int index) async {
    final state = ref.read(menuProvider);
    if (index < 0 || index >= state.categorias.length) return;
    final category = state.categorias[index];
    final confirmed = await _confirm(
      'Eliminar categoría',
      '¿Eliminar "${category.nombre}"? Los productos quedarán sin categoría.',
    );
    if (!mounted || confirmed != true) return;
    final ok = await ref
        .read(menuProvider.notifier)
        .eliminarCategoria(category.id);
    if (!ok && mounted) _showError(ref.read(menuProvider).errorMessage);
  }

  Future<void> _createProduct() async {
    final state = ref.read(menuProvider);
    if (state.categorias.isEmpty) {
      _showMessage('Crea al menos una categoría primero.');
      return;
    }
    final product = await ProductoFormDialog.show(
      context,
      categorias: state.categorias,
    );
    if (!mounted || product == null) return;
    final ok = await ref.read(menuProvider.notifier).crearProducto(product);
    if (!ok && mounted) _showError(ref.read(menuProvider).errorMessage);
  }

  Future<void> _editProduct(String id) async {
    final state = ref.read(menuProvider);
    final product = state.productos.where((p) => p.id == id).firstOrNull;
    if (product == null) return;
    final updated = await ProductoFormDialog.show(
      context,
      producto: product,
      categorias: state.categorias,
    );
    if (!mounted || updated == null) return;
    final ok = await ref
        .read(menuProvider.notifier)
        .actualizarProducto(updated);
    if (!ok && mounted) _showError(ref.read(menuProvider).errorMessage);
  }

  Future<void> _deleteProduct(String id, String name) async {
    final confirmed = await _confirm(
      'Eliminar producto',
      '¿Eliminar "$name" del menú?',
    );
    if (!mounted || confirmed != true) return;
    final ok = await ref.read(menuProvider.notifier).eliminarProducto(id);
    if (!ok && mounted) _showError(ref.read(menuProvider).errorMessage);
  }

  Future<bool?> _confirm(String title, String message) => showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Eliminar'),
        ),
      ],
    ),
  );

  void _showMessage(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  void _showError(String? message) {
    if (message == null || message.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(menuProvider);
    _syncTabs(state.categorias.length);
    final tabs = _tabs;
    final productsByTab = <List<dynamic>>[
      state.productos,
      ...state.categorias.map(
        (category) =>
            state.productos.where((p) => p.categoriaId == category.id).toList(),
      ),
    ];

    return Scaffold(
      body: state.isLoading
          ? const AppLoadingView(message: 'Cargando menú...')
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Menú',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${state.totalProductos} productos · ${state.totalCategorias} categorías',
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => context.push(AppRouter.menuPublico),
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('Vista cliente'),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _createCategory,
                        icon: const Icon(Icons.create_new_folder_outlined),
                        label: const Text('Categoría'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _createProduct,
                        icon: const Icon(Icons.add),
                        label: const Text('Producto'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (tabs != null)
                  TabBar(
                    controller: tabs,
                    isScrollable: true,
                    tabs: [
                      const Tab(text: 'Todos'),
                      ...state.categorias.asMap().entries.map(
                        (entry) => Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(entry.value.nombre),
                              IconButton(
                                icon: const Icon(Icons.more_vert, size: 16),
                                onPressed: () => _categoryMenu(entry.key),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                Expanded(
                  child: tabs == null
                      ? const SizedBox.shrink()
                      : TabBarView(
                          controller: tabs,
                          children: productsByTab
                              .map((products) => _productGrid(products, state))
                              .toList(),
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createProduct,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo producto'),
      ),
    );
  }

  void _categoryMenu(int index) {
    showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Editar'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Eliminar'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    ).then((value) {
      if (value == 'edit') _editCategory(index);
      if (value == 'delete') _deleteCategory(index);
    });
  }

  Widget _productGrid(List<dynamic> products, MenuState state) {
    if (products.isEmpty) {
      return Center(
        child: FilledButton.icon(
          onPressed: _createProduct,
          icon: const Icon(Icons.add),
          label: const Text('Agregar producto'),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: .84,
      ),
      itemCount: products.length,
      itemBuilder: (_, index) {
        final product = products[index];
        final categoryName = state.categorias
            .where((c) => c.id == product.categoriaId)
            .map((c) => c.nombre)
            .firstOrNull;
        return ProductoCard(
          producto: product,
          categoriaNombre: categoryName,
          onEdit: () => _editProduct(product.id),
          onDelete: () => _deleteProduct(product.id, product.nombre),
        );
      },
    );
  }
}
