import 'package:alsamos_flutter/app/theme/app_theme.dart';
import 'package:alsamos_flutter/features/create/presentation/widgets/create_reel_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  late TextEditingController contentController;

  setUp(() {
    contentController = TextEditingController();
  });

  tearDown(() {
    contentController.dispose();
  });

  Widget subject({XFile? selectedMedia}) {
    final theme = AppTheme.light;
    final colors = theme.extension<AlsamosColors>()!;
    return ProviderScope(
      child: MaterialApp(
        theme: theme,
        home: Scaffold(
          body: CreateReelTab(
            colors: colors,
            primary: theme.colorScheme.primary,
            selectedMedia: selectedMedia,
            contentController: contentController,
            identityRow: const Text('Identity'),
            composerField: TextField(controller: contentController),
            metaInputs: const Text('Meta inputs'),
            profileFallback: 'S',
            profileUsername: 'samandar',
            onEditMedia: () {},
            onRemoveMedia: () {},
            onPickVideo: () {},
            onPickMusic: () {},
            onClearMusic: () {},
            onFocusCaption: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('keeps reel tools responsive on a mobile viewport',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(subject());

    expect(find.byKey(const Key('create-reel-compact-layout')), findsOneWidget);
    expect(find.byKey(const Key('create-reel-wide-layout')), findsNothing);
    expect(find.text('Reel video tanlang'), findsOneWidget);
    expect(find.text('Video yuklash'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the two-column reel layout stable on desktop',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(subject());

    expect(find.byKey(const Key('create-reel-wide-layout')), findsOneWidget);
    expect(find.byKey(const Key('create-reel-compact-layout')), findsNothing);
    expect(find.text('Musiqa'), findsOneWidget);
    expect(find.text('Caption'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('updates the reel preview while caption is typed',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      subject(selectedMedia: XFile('reel-preview.unsupported')),
    );
    await tester.enterText(find.byType(TextField), 'Mening reelim');
    await tester.pump();

    expect(find.text('Mening reelim'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
