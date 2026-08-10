import 'package:alsamos_flutter/app/theme/app_theme.dart';
import 'package:alsamos_flutter/features/create/presentation/widgets/create_story_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TextEditingController contentController;

  setUp(() {
    contentController = TextEditingController();
  });

  tearDown(() {
    contentController.dispose();
  });

  Widget subject() {
    final theme = AppTheme.light;
    final colors = theme.extension<AlsamosColors>()!;
    return ProviderScope(
      child: MaterialApp(
        theme: theme,
        home: Scaffold(
          body: CreateStoryTab(
            colors: colors,
            primary: theme.colorScheme.primary,
            contentController: contentController,
            composerField: TextField(controller: contentController),
            backgroundColor: const Color(0xFFF97316),
            textSize: 28,
            font: 'bold',
            textAlign: TextAlign.center,
            textPosition: const Offset(0.5, 0.52),
            mentions: const [],
            onEditMedia: () {},
            onRemoveMedia: () {},
            onTextPositionChanged: (_) {},
            onTextAlignChanged: (_) {},
            onFontChanged: (_) {},
            onTextSizeChanged: (_) {},
            onResetTextPosition: () {},
            onBackgroundColorChanged: (_) {},
            onOpenCamera: () {},
            onRecordVideo: () {},
            onPickPhoto: () {},
            onPickVideo: () {},
            onPickMusic: () {},
            onUseTextMode: () {},
            onAddMention: () {},
            onRemoveMention: (_) {},
            onClearMusic: () {},
            profileDisplayName: 'Samandar',
            profileFallback: 'S',
          ),
        ),
      ),
    );
  }

  testWidgets('keeps story tools responsive on a mobile viewport',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(subject());

    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Record'), findsOneWidget);
    expect(find.text('Mention'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the two-column story layout stable on desktop',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(subject());

    expect(find.text('Fon rangi'), findsOneWidget);
    expect(find.text('Matn uslubi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('updates the story preview while caption is typed',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(subject());
    await tester.enterText(find.byType(TextField).first, 'Mening hikoyam');
    await tester.pump();

    expect(find.text('Mening hikoyam'), findsNWidgets(2));
  });
}
