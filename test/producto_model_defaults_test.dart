import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_app/Presentation/Models/menu/producto_model.dart';

void main() {
  test('productos sin flags antiguos se muestran activos y disponibles', () {
    final product = ProductoModel.fromMap({
      'id': 'producto-1',
      'restaurant_id': 'la_pena_001',
      'categoria_id': 'categoria-1',
      'nombre': 'Producto de prueba',
      'precio': 5,
      'created_at': '2026-08-04T00:00:00.000Z',
      'updated_at': '2026-08-04T00:00:00.000Z',
    });

    expect(product.activo, isTrue);
    expect(product.disponible, isTrue);
  });

  test('la desactivación explícita continúa ocultando el producto', () {
    final product = ProductoModel.fromMap({
      'id': 'producto-2',
      'restaurant_id': 'la_pena_001',
      'categoria_id': 'categoria-1',
      'nombre': 'Producto oculto',
      'precio': 5,
      'activo': 0,
      'disponible': 0,
      'created_at': '2026-08-04T00:00:00.000Z',
      'updated_at': '2026-08-04T00:00:00.000Z',
    });

    expect(product.activo, isFalse);
    expect(product.disponible, isFalse);
  });
}
