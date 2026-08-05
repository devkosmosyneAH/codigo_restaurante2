import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:restaurant_app/Presentation/core/di/injection_container.dart';
import 'package:restaurant_app/Presentation/core/tenant/tenant_context.dart';
import 'package:restaurant_app/Presentation/core/utils/image_picker_util.dart';
import 'package:restaurant_app/Presentation/entities/menu/categoria.dart';
import 'package:restaurant_app/Presentation/entities/menu/producto.dart';
import 'package:restaurant_app/Presentation/entities/menu/variante.dart';
import 'package:restaurant_app/Presentation/services/cloudinary_upload_service.dart';
import 'package:uuid/uuid.dart';

/// Formulario de producto. Las imágenes seleccionadas se suben a Cloudinary
/// y solo sus metadatos públicos se guardan junto al producto en Firebase.
class ProductoFormDialog extends StatefulWidget {
  final Producto? producto;
  final List<Categoria> categorias;

  const ProductoFormDialog({super.key, this.producto, required this.categorias});

  static Future<Producto?> show(
    BuildContext context, {
    Producto? producto,
    required List<Categoria> categorias,
  }) => showDialog<Producto>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ProductoFormDialog(producto: producto, categorias: categorias),
  );

  @override
  State<ProductoFormDialog> createState() => _ProductoFormDialogState();
}

class _ProductoFormDialogState extends State<ProductoFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombre;
  late final TextEditingController _descripcion;
  late final TextEditingController _precio;
  late final TextEditingController _imagenUrl;
  late String _categoriaId;
  Uint8List? _selectedBytes;
  String? _selectedMimeType;
  String? _previewDataUri;
  String? _cloudinaryId;
  int? _imageWidth;
  int? _imageHeight;
  int? _imageBytes;
  int? _imageVersion;
  bool _disponible = true;
  bool _activo = true;
  bool _busy = false;
  String? _imageMessage;
  final List<_VarianteEditable> _variantes = [];

  bool get _editing => widget.producto != null;

  @override
  void initState() {
    super.initState();
    final p = widget.producto;
    _nombre = TextEditingController(text: p?.nombre ?? '');
    _descripcion = TextEditingController(text: p?.descripcion ?? '');
    _precio = TextEditingController(
      text: p == null ? '' : p.precio.toStringAsFixed(2),
    );
    _imagenUrl = TextEditingController(text: p?.imagenUrl ?? '');
    _categoriaId = p?.categoriaId ??
        (widget.categorias.isEmpty ? '' : widget.categorias.first.id);
    _cloudinaryId = p?.cloudinaryPublicId;
    _imageWidth = p?.imagenWidth;
    _imageHeight = p?.imagenHeight;
    _imageBytes = p?.imagenBytes;
    _imageVersion = p?.imagenVersion;
    _disponible = p?.disponible ?? true;
    _activo = p?.activo ?? true;
    for (final variante in p?.variantes ?? const <Variante>[]) {
      _variantes.add(_VarianteEditable.fromEntity(variante));
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    _precio.dispose();
    _imagenUrl.dispose();
    for (final variante in _variantes) {
      variante.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_busy) return;
    try {
      final picked = await pickAndEncodeImage(
        maxWidth: 1200,
        jpegQuality: 84,
        maxBytes: 5 * 1024 * 1024,
      );
      if (!mounted || picked == null) return;
      setState(() {
        _selectedBytes = picked.bytes;
        _selectedMimeType = picked.mimeType;
        _previewDataUri = picked.dataUri;
        _imagenUrl.clear();
        _cloudinaryId = null;
        _imageWidth = null;
        _imageHeight = null;
        _imageBytes = null;
        _imageVersion = null;
        _imageMessage = 'Imagen lista para subir a Cloudinary.';
      });
    } on PickedImageError catch (e) {
      if (mounted) _showMessage(e.message);
    } catch (e) {
      if (mounted) _showMessage('No se pudo procesar la imagen: $e');
    }
  }

  void _clearImage() {
    setState(() {
      _selectedBytes = null;
      _selectedMimeType = null;
      _previewDataUri = null;
      _imagenUrl.clear();
      _cloudinaryId = null;
      _imageWidth = null;
      _imageHeight = null;
      _imageBytes = null;
      _imageVersion = null;
      _imageMessage = null;
    });
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final now = DateTime.now();
      final productId = widget.producto?.id ?? const Uuid().v4();
      var imageUrl = _imagenUrl.text.trim();
      if (imageUrl.isEmpty) imageUrl = '';

      if (_selectedBytes != null && _selectedMimeType != null) {
        setState(() => _imageMessage = 'Subiendo imagen a Cloudinary...');
        final upload = await sl<CloudinaryUploadService>().upload(
          bytes: _selectedBytes!,
          mimeType: _selectedMimeType!,
          kind: CloudinaryUploadKind.menu,
        );
        imageUrl = upload.secureUrl;
        _cloudinaryId = upload.publicId;
        _imageWidth = upload.width;
        _imageHeight = upload.height;
        _imageBytes = upload.bytes;
        _imageVersion = upload.version;
        _imageMessage = 'Imagen subida correctamente.';
      }

      if (imageUrl.isNotEmpty && !_isValidUrl(imageUrl)) {
        throw StateError('La URL de imagen debe ser pública y usar http/https.');
      }

      final variantes = _variantes.map((item) {
        return Variante(
          id: item.id ?? const Uuid().v4(),
          productoId: productId,
          nombre: item.nombre.text.trim(),
          precio: double.tryParse(item.precio.text.trim()) ?? 0,
          activo: true,
          createdAt: item.createdAt ?? now,
          updatedAt: now,
        );
      }).where((v) => v.nombre.isNotEmpty).toList(growable: false);

      final product = Producto(
        id: productId,
        restaurantId: sl<TenantContext>().restaurantId,
        categoriaId: _categoriaId,
        nombre: _nombre.text.trim(),
        descripcion: _descripcion.text.trim().isEmpty ? null : _descripcion.text.trim(),
        precio: double.tryParse(_precio.text.trim()) ?? 0,
        imagenUrl: imageUrl.isEmpty ? null : imageUrl,
        cloudinaryPublicId: _cloudinaryId,
        imagenWidth: _imageWidth,
        imagenHeight: _imageHeight,
        imagenBytes: _imageBytes,
        imagenVersion: _imageVersion,
        disponible: _disponible,
        activo: _activo,
        createdAt: widget.producto?.createdAt ?? now,
        updatedAt: now,
        variantes: variantes,
      );
      if (mounted) Navigator.of(context).pop(product);
    } catch (e) {
      if (mounted) _showMessage('No se pudo guardar la imagen/producto: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _isValidUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _addVariante() => setState(() => _variantes.add(_VarianteEditable()));

  void _removeVariante(int index) {
    final item = _variantes.removeAt(index);
    item.dispose();
    setState(() {});
  }

  Widget _imagePreview() {
    final value = _previewDataUri ?? _imagenUrl.text.trim();
    if (value.isEmpty) {
      return Container(
        height: 150,
        width: double.infinity,
        alignment: Alignment.center,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Text('Sin imagen'),
      );
    }
    final image = value.startsWith('data:image')
        ? Image.memory(base64Decode(value.split(',').last), fit: BoxFit.cover)
        : Image.network(value, fit: BoxFit.cover);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(height: 150, width: double.infinity, child: image),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = (MediaQuery.sizeOf(context).height * .82).clamp(360.0, 720.0);
    return AlertDialog(
      title: Text(_editing ? 'Editar producto' : 'Nuevo producto'),
      content: SizedBox(
        width: 520,
        height: maxHeight,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nombre,
                  decoration: const InputDecoration(labelText: 'Nombre *'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'El nombre es obligatorio' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descripcion,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _precio,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Precio *'),
                  validator: (v) => double.tryParse(v?.trim() ?? '') == null ? 'Precio inválido' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _categoriaId.isEmpty ? null : _categoriaId,
                  decoration: const InputDecoration(labelText: 'Categoría *'),
                  items: widget.categorias
                      .map((c) => DropdownMenuItem(value: c.id, child: Text(c.nombre)))
                      .toList(),
                  onChanged: _busy ? null : (value) => setState(() => _categoriaId = value ?? ''),
                  validator: (v) => v == null || v.isEmpty ? 'Selecciona una categoría' : null,
                ),
                const SizedBox(height: 16),
                Text('Imagen del producto', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                _imagePreview(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _pickImage,
                      icon: const Icon(Icons.upload_rounded),
                      label: const Text('Subir imagen'),
                    ),
                    const SizedBox(width: 8),
                    if (_imagenUrl.text.isNotEmpty || _previewDataUri != null)
                      TextButton.icon(
                        onPressed: _busy ? null : _clearImage,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Quitar'),
                      ),
                  ],
                ),
                TextFormField(
                  controller: _imagenUrl,
                  decoration: const InputDecoration(labelText: 'URL externa opcional'),
                  onChanged: (_) => setState(() {}),
                ),
                if (_imageMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_imageMessage!, style: Theme.of(context).textTheme.bodySmall),
                  ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Variantes', style: Theme.of(context).textTheme.titleSmall),
                    TextButton.icon(onPressed: _busy ? null : _addVariante, icon: const Icon(Icons.add), label: const Text('Agregar')),
                  ],
                ),
                ..._variantes.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  return Row(
                    children: [
                      Expanded(child: TextFormField(controller: item.nombre, decoration: const InputDecoration(labelText: 'Nombre'))),
                      const SizedBox(width: 8),
                      SizedBox(width: 110, child: TextFormField(controller: item.precio, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Precio'))),
                      IconButton(onPressed: _busy ? null : () => _removeVariante(index), icon: const Icon(Icons.delete_outline)),
                    ],
                  );
                }),
                SwitchListTile.adaptive(title: const Text('Disponible'), value: _disponible, onChanged: _busy ? null : (v) => setState(() => _disponible = v), contentPadding: EdgeInsets.zero),
                SwitchListTile.adaptive(title: const Text('Activo'), value: _activo, onChanged: _busy ? null : (v) => setState(() => _activo = v), contentPadding: EdgeInsets.zero),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _busy ? null : _submit, child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_editing ? 'Guardar' : 'Crear')),
      ],
    );
  }
}

class _VarianteEditable {
  final String? id;
  final DateTime? createdAt;
  final TextEditingController nombre;
  final TextEditingController precio;

  _VarianteEditable({this.id, this.createdAt})
      : nombre = TextEditingController(),
        precio = TextEditingController();

  factory _VarianteEditable.fromEntity(Variante value) => _VarianteEditable(id: value.id, createdAt: value.createdAt)
    ..nombre.text = value.nombre
    ..precio.text = value.precio.toStringAsFixed(2);

  void dispose() {
    nombre.dispose();
    precio.dispose();
  }
}
