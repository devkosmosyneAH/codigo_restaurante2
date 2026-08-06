import 'package:flutter/material.dart';
import 'package:restaurant_app/Presentation/entities/pagina_publica/public_gallery_image.dart';
import 'package:restaurant_app/Presentation/widgets/skeleton_loader.dart';

class PublicGalleryView extends StatelessWidget {
  const PublicGalleryView({super.key, required this.images});
  final List<PublicGalleryImage> images;

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Conoce nuestro espacio',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 4
                  : constraints.maxWidth >= 600
                  ? 3
                  : 2;
              final size =
                  (constraints.maxWidth - (columns - 1) * 10) / columns;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: images
                    .map(
                      (image) => ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          image.imageUrl,
                          width: size,
                          height: size * .78,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) =>
                              progress == null
                              ? child
                              : SizedBox(
                                  width: size,
                                  height: size * .78,
                                  child: const AppLoadingView(compact: true),
                                ),
                          errorBuilder: (_, __, ___) => Container(
                            width: size,
                            height: size * .78,
                            color: Colors.black12,
                            child: const Icon(Icons.broken_image),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
