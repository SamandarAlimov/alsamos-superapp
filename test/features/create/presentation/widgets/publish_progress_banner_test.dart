import 'package:alsamos_flutter/app/theme/app_theme.dart';
import 'package:alsamos_flutter/features/create/presentation/widgets/publish_progress_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keeps long publish status stable and exposes retry',
      (tester) async {
    var retries = 0;
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: PublishProgressBanner(
            status:
                'Yuklash yakunlanmadi. Internetni tekshirib qayta urinib ko\'ring.',
            progress: 0.5,
            failed: true,
            onRetry: () => retries++,
          ),
        ),
      ),
    );

    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });

  testWidgets('offers a non-blocking cancel action while uploading',
      (tester) async {
    var cancellations = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: PublishProgressBanner(
            status: 'Media yuklanmoqda...',
            progress: 0.25,
            failed: false,
            onRetry: null,
            onCancel: () => cancellations++,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Yuklashni to\'xtatish'));
    expect(cancellations, 1);
  });
}
