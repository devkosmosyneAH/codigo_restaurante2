import 'package:restaurant_app/Presentation/Models/pagina_publica/public_gallery_image_model.dart';

abstract class PublicGalleryDatasource {
  Future<List<PublicGalleryImageModel>> getAll(String restaurantId);
  Future<void> save(PublicGalleryImageModel image);
  Future<void> delete(String id, String restaurantId);
  Future<void> reorder(String restaurantId, List<String> orderedIds);
}
