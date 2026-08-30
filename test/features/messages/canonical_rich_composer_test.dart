import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alsamos_flutter/features/messages/presentation/widgets/canonical_rich_composer.dart';

void main() {
  group('CanonicalRichComposerController', () {
    test('loads transport markers as marker-free display text', () {
      final controller = CanonicalRichComposerController(
        transportText:
            '> **Bold** and __italic__ with ++under++ and ||secret||',
      );
      addTearDown(controller.dispose);

      expect(controller.text, 'Bold and italic with under and secret');
      expect(controller.text, isNot(contains('**')));
      expect(controller.text, isNot(contains('||')));
      expect(
        controller.transportText,
        '> **Bold** and __italic__ with ++under++ and ||secret||',
      );
    });

    test('selection formatting serializes to canonical web markers', () {
      final controller =
          CanonicalRichComposerController(transportText: 'hello world');
      addTearDown(controller.dispose);

      controller.selection =
          const TextSelection(baseOffset: 0, extentOffset: 5);
      controller.toggleInlineFormat(ComposerInlineFormat.bold);

      controller.selection =
          const TextSelection(baseOffset: 6, extentOffset: 11);
      controller.toggleInlineFormat(ComposerInlineFormat.underline);

      expect(controller.text, 'hello world');
      expect(controller.transportText, '**hello** ++world++');
    });

    test('quote is visual state but serializes with canonical prefix', () {
      final controller = CanonicalRichComposerController(
        transportText: 'first\nsecond',
      );
      addTearDown(controller.dispose);

      controller.selection =
          const TextSelection(baseOffset: 0, extentOffset: 12);
      controller.toggleQuote();

      expect(controller.text, 'first\nsecond');
      expect(controller.transportText, '> first\n> second');
    });

    test('typing inside formatted text keeps the active format', () {
      final controller =
          CanonicalRichComposerController(transportText: '**bold**');
      addTearDown(controller.dispose);

      controller.value = const TextEditingValue(
        text: 'bolXd',
        selection: TextSelection.collapsed(offset: 4),
      );

      expect(controller.transportText, '**bolXd**');
    });

    testWidgets('composer renders selected formatting controls on all targets',
        (tester) async {
      final controller =
          CanonicalRichComposerController(transportText: 'format me');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      controller.selection =
          const TextSelection(baseOffset: 0, extentOffset: 6);

      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: CanonicalRichComposerField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 5,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 16),
              cursorColor: Colors.orange,
              decoration: const InputDecoration(),
            ),
          ),
        ),
      );

      expect(find.byTooltip('Qalin'), findsOneWidget);
      expect(find.byTooltip('Kursiv'), findsOneWidget);
      expect(find.byTooltip('Spoiler'), findsOneWidget);
      expect(find.byTooltip('Iqtibos'), findsOneWidget);
    });
  });
}
