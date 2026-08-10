import 'package:alsamos_flutter/app/theme/app_theme.dart';
import 'package:alsamos_flutter/features/create/presentation/widgets/create_media_preview_stage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget subject({
    required bool reelOnly,
    ValueChanged<String>? onAspectChanged,
  }) {
    final theme = AppTheme.light;
    final colors = theme.extension<AlsamosColors>()!;
    return MaterialApp(
      theme: theme,
      home: Scaffold(
        body: SizedBox(
          width: 1000,
          child: CreateMediaPreviewStage(
            colors: colors,
            primary: theme.colorScheme.primary,
            mediaFiles: const [],
            currentMediaIndex: 0,
            aspectPresetId: 'original',
            emptyTitle: 'Media tanlang',
            emptySubtitle: 'Gallery yoki fayldan tanlang',
            reelOnly: reelOnly,
            videoExporting: false,
            videoExportProgress: 0,
            onPickImage: () {},
            onPickVideo: () {},
            onPickFile: () {},
            onEditSelected: () {},
            onRemoveSelected: () {},
            onMediaSelected: (_) {},
            onAspectChanged: onAspectChanged ?? (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('post mode keeps image, video, file, and aspect controls',
      (tester) async {
    await tester.pumpWidget(subject(reelOnly: false));

    expect(find.text('Rasm'), findsOneWidget);
    expect(find.text('Video'), findsOneWidget);
    expect(find.text('Fayl'), findsOneWidget);
    expect(find.text('1:1'), findsOneWidget);
    expect(find.text('4:5'), findsOneWidget);
    expect(find.text('9:16'), findsOneWidget);
  });

  testWidgets('reel mode exposes only video and vertical aspect controls',
      (tester) async {
    String? selectedAspect;
    await tester.pumpWidget(
      subject(
        reelOnly: true,
        onAspectChanged: (value) => selectedAspect = value,
      ),
    );

    expect(find.text('Rasm'), findsNothing);
    expect(find.text('Video'), findsOneWidget);
    expect(find.text('Fayl'), findsNothing);
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('9:16'), findsOneWidget);
    expect(find.text('1:1'), findsNothing);

    await tester.tap(find.text('9:16'));
    expect(selectedAspect, '9:16');
  });
}
