import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_app/Presentation/widgets/menu/menu_image_loader.dart';

void main() {
  group('buildImageCandidates', () {
    test('conserva una URL Cloudinary segura', () {
      final candidates = buildImageCandidates(
        'https://res.cloudinary.com/ttviexhh/image/upload/v1/restaurante/menu/a.jpg',
      );
      expect(candidates, [
        'https://res.cloudinary.com/ttviexhh/image/upload/v1/restaurante/menu/a.jpg',
      ]);
    });

    test('ignora valores vacios y conserva assets locales', () {
      expect(buildImageCandidates('   '), isEmpty);
      expect(buildImageCandidates('assets/images/logo.png'), [
        'assets/images/logo.png',
      ]);
    });
  });
}
