import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restaurant_app/Presentation/Models/pagina_publica/public_gallery_image_model.dart';
import 'package:restaurant_app/Presentation/core/di/injection_container.dart';
import 'package:restaurant_app/Presentation/core/tenant/tenant_context.dart';
import 'package:restaurant_app/Presentation/core/utils/image_picker_util.dart';
import 'package:restaurant_app/Presentation/entities/pagina_publica/public_gallery_image.dart';
import 'package:restaurant_app/Presentation/providers/pagina_publica/public_gallery_provider.dart';
import 'package:restaurant_app/Presentation/services/cloudinary_upload_service.dart';
import 'package:uuid/uuid.dart';

class PublicGalleryEditor extends ConsumerStatefulWidget {
  const PublicGalleryEditor({super.key});

  @override
  ConsumerState<PublicGalleryEditor> createState() => _PublicGalleryEditorState();
}

class _PublicGalleryEditorState extends ConsumerState<PublicGalleryEditor> {
  bool _uploading = false;

  Future<void> _upload({required bool cover}) async {
    final picked = await pickAndEncodeImage(
      maxWidth: 1600,
      jpegQuality: 86,
      maxBytes: 8 * 1024 * 1024,
    );
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final result = await sl<CloudinaryUploadService>().upload(
        bytes: picked.bytes,
        mimeType: picked.mimeType,
        kind: CloudinaryUploadKind.publicPage,
      );
      final images = ref.read(publicGalleryProvider).images;
      final restaurantId = sl<TenantContext>().restaurantId;
      final now = DateTime.now();
      final existingCover = images.where((image) => image.isCover).firstOrNull;
      final image = PublicGalleryImageModel(
        id: cover ? existingCover?.id ?? '${restaurantId}_cover' : const Uuid().v4(),
        restaurantId: restaurantId,
        tipo: cover ? 'portada' : 'galeria',
        imageUrl: result.secureUrl,
        cloudinaryPublicId: result.publicId,
        width: result.width,
        height: result.height,
        bytes: result.bytes,
        version: result.version,
        orden: cover ? 0 : images.where((item) => !item.isCover).length,
        activo: true,
        altText: cover ? 'Portada del restaurante' : 'Foto del restaurante',
        createdAt: existingCover?.createdAt ?? now,
        updatedAt: now,
      );
      final saved = await ref.read(publicGalleryProvider.notifier).save(image);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(saved ? 'Imagen subida correctamente.' : 'No se pudo guardar la imagen.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _toggle(PublicGalleryImage image, bool active) async {
    final updated = image.copyWith(activo: active, updatedAt: DateTime.now());
    await ref.read(publicGalleryProvider.notifier).save(updated);
  }

  Future<void> _delete(PublicGalleryImage image) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar imagen'),
        content: const Text('Se quitara de Firebase. El asset de Cloudinary debera limpiarse manualmente.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmed == true) await ref.read(publicGalleryProvider.notifier).delete(image);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(publicGalleryProvider);
    final cover = state.images.where((image) => image.isCover).firstOrNull;
    final gallery = state.images.where((image) => !image.isCover).toList()
      ..sort((a, b) => a.orden.compareTo(b.orden));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Fotos de la pagina publica', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                if (_uploading) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 6),
            const Text('Las imagenes se almacenan en Cloudinary y sus URLs en Firebase.'),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(onPressed: _uploading ? null : () => _upload(cover: true), icon: const Icon(Icons.wallpaper), label: const Text('Subir portada')),
                const SizedBox(width: 8),
                OutlinedButton.icon(onPressed: _uploading ? null : () => _upload(cover: false), icon: const Icon(Icons.add_photo_alternate), label: const Text('Agregar foto')),
              ],
            ),
            if (cover != null) ...[
              const SizedBox(height: 14),
              _ImageRow(image: cover, onToggle: (value) => _toggle(cover, value), onDelete: () => _delete(cover)),
            ],
            if (gallery.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('Galeria (arrastra para ordenar)'),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: gallery.length,
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex--;
                  final reordered = [...gallery]..insert(newIndex, gallery.removeAt(oldIndex));
                  ref.read(publicGalleryProvider.notifier).reorder(reordered.map((image) => image.id).toList());
                },
                itemBuilder: (context, index) {
                  final image = gallery[index];
                  return _ImageRow(key: ValueKey(image.id), image: image, onToggle: (value) => _toggle(image, value), onDelete: () => _delete(image));
                },
              ),
            ],
            if (state.error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          ],
        ),
      ),
    );
  }
}

class _ImageRow extends StatelessWidget {
  const _ImageRow({super.key, required this.image, required this.onToggle, required this.onDelete});
  final PublicGalleryImage image;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: SizedBox(width: 72, height: 52, child: Image.network(image.imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image))),
    title: Text(image.isCover ? 'Portada' : image.altText),
    subtitle: Text('${image.width} x ${image.height}'),
    trailing: Wrap(children: [Switch(value: image.activo, onChanged: onToggle), IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline))]),
  );
}
