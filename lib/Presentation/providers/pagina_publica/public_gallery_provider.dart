import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restaurant_app/Presentation/core/di/injection_container.dart';
import 'package:restaurant_app/Presentation/core/tenant/tenant_context.dart';
import 'package:restaurant_app/Presentation/Models/pagina_publica/public_gallery_image_model.dart';
import 'package:restaurant_app/Presentation/data/pagina_publica/public_gallery_datasource.dart';
import 'package:restaurant_app/Presentation/entities/pagina_publica/public_gallery_image.dart';

class PublicGalleryState {
  final List<PublicGalleryImage> images;
  final bool isLoading;
  final String? error;

  const PublicGalleryState({this.images = const [], this.isLoading = false, this.error});

  PublicGalleryState copyWith({List<PublicGalleryImage>? images, bool? isLoading, String? error, bool clearError = false}) =>
      PublicGalleryState(
        images: images ?? this.images,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : error ?? this.error,
      );
}

class PublicGalleryNotifier extends StateNotifier<PublicGalleryState> {
  PublicGalleryNotifier({required PublicGalleryDatasource datasource})
      : _datasource = datasource,
        super(const PublicGalleryState()) {
    load();
  }

  final PublicGalleryDatasource _datasource;
  String get _restaurantId => sl<TenantContext>().restaurantId;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final images = await _datasource.getAll(_restaurantId);
      state = state.copyWith(images: images, isLoading: false);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<bool> save(PublicGalleryImage image) async {
    try {
      await _datasource.save(PublicGalleryImageModel.fromEntity(image));
      await load();
      return true;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      return false;
    }
  }

  Future<bool> delete(PublicGalleryImage image) async {
    try {
      await _datasource.delete(image.id, _restaurantId);
      await load();
      return true;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      return false;
    }
  }

  Future<void> reorder(List<String> ids) async {
    try {
      await _datasource.reorder(_restaurantId, ids);
      await load();
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }
}

final publicGalleryProvider = StateNotifierProvider<PublicGalleryNotifier, PublicGalleryState>((ref) {
  return PublicGalleryNotifier(datasource: sl());
});
