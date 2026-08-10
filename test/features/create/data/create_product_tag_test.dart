import 'package:alsamos_flutter/features/create/data/models/create_product_tag.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CreateProductTag.fromMap', () {
    test('maps product fields and picks the first ordered image', () {
      final product = CreateProductTag.fromMap({
        'id': 'product-1',
        'title': 'Camera',
        'price': 125.5,
        'currency': 'UZS',
        'images': [
          {'url': 'https://cdn.test/second.jpg', 'position': 2},
          {'url': 'https://cdn.test/first.jpg', 'position': 1},
        ],
      });

      expect(product.id, 'product-1');
      expect(product.title, 'Camera');
      expect(product.price, 125.5);
      expect(product.currency, 'UZS');
      expect(product.imageUrl, 'https://cdn.test/first.jpg');
    });

    test('uses safe defaults for sparse or malformed rows', () {
      final product = CreateProductTag.fromMap({
        'price': '18.25',
        'images': [
          {'position': 1},
        ],
      });

      expect(product.id, isEmpty);
      expect(product.title, 'Product');
      expect(product.price, 18.25);
      expect(product.currency, 'USD');
      expect(product.imageUrl, isNull);
    });
  });

  group('CreateProductTag.fromRows', () {
    test('drops malformed rows and excludes selected ids after mapping', () {
      final products = CreateProductTag.fromRows(
        [
          {
            'id': 'selected',
            'title': 'Selected',
            'price': 1,
            'currency': 'USD',
          },
          {
            'id': 'available',
            'title': 'Available',
            'price': 2,
            'currency': 'USD',
          },
          {'id': ''},
          'not-a-row',
        ],
        selectedIds: const ['selected'],
      );

      expect(products.map((product) => product.id), ['available']);
    });

    test('caps mapped rows to twenty products', () {
      final rows = List.generate(
        25,
        (index) => {
          'id': 'product-$index',
          'title': 'Product $index',
        },
      );

      expect(CreateProductTag.fromRows(rows), hasLength(20));
    });
  });
}
