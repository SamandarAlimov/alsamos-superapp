import 'package:alsamos_flutter/app/theme/app_theme.dart';
import 'package:alsamos_flutter/features/create/data/models/create_product_tag.dart';
import 'package:alsamos_flutter/features/create/presentation/widgets/create_product_tag_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

void main() {
  const headphones = CreateProductTag(
    id: 'p1',
    title: 'Studio headphones',
    price: 129.99,
    currency: 'USD',
  );
  const camera = CreateProductTag(
    id: 'p2',
    title: 'Creator camera',
    price: 299,
    currency: 'USD',
  );

  Widget subject({
    required CreateProductTagSearch onSearch,
    ValueChanged<CreateProductTag?>? onSelected,
    CreateProductTagError? onError,
    List<CreateProductTag> selected = const <CreateProductTag>[],
    ValueChanged<CreateProductTag>? onRemove,
  }) {
    return MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              ElevatedButton(
                onPressed: () async {
                  final product = await showCreateProductTagPicker(
                    context: context,
                    onSearch: onSearch,
                    onError: onError,
                  );
                  onSelected?.call(product);
                },
                child: const Text('Open'),
              ),
              CreateSelectedProductTagsSection(
                products: selected,
                onAdd: () {},
                onRemove: onRemove ?? (_) {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('loads initial products and returns the selected product',
      (tester) async {
    final queries = <String>[];
    CreateProductTag? selected;

    await tester.pumpWidget(
      subject(
        onSearch: (query) async {
          queries.add(query);
          return const [headphones, camera];
        },
        onSelected: (product) => selected = product,
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(queries, contains(''));
    expect(find.text('Mahsulot tag qilish'), findsOneWidget);
    expect(find.text('Studio headphones'), findsOneWidget);
    expect(find.text('129.99 USD'), findsOneWidget);

    await tester.tap(find.text('Studio headphones'));
    await tester.pumpAndSettle();

    expect(selected, headphones);
  });

  testWidgets('searches by text and reports errors without closing the sheet',
      (tester) async {
    final errors = <Object>[];

    await tester.pumpWidget(
      subject(
        onSearch: (query) async {
          if (query == 'fail') throw StateError('search failed');
          return query == 'cam' ? const [camera] : const [headphones];
        },
        onError: errors.add,
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'cam');
    await tester.pumpAndSettle();

    expect(find.text('Creator camera'), findsOneWidget);
    expect(find.text('Studio headphones'), findsNothing);

    await tester.enterText(find.byType(TextField), 'fail');
    await tester.pumpAndSettle();

    expect(errors, hasLength(1));
    expect(find.text('Mahsulot tag qilish'), findsOneWidget);
  });

  testWidgets('selected products section removes tags and stays responsive',
      (tester) async {
    CreateProductTag? removed;
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      subject(
        onSearch: (_) async => const [],
        selected: const [headphones],
        onRemove: (product) => removed = product,
      ),
    );

    expect(find.text('Mahsulotlar'), findsOneWidget);
    expect(find.text('Tag qilish'), findsOneWidget);
    expect(find.text('Studio headphones'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(LucideIcons.x).first);
    await tester.pump();

    expect(removed, headphones);
  });
}
