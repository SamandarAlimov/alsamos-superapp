import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Video player controls Row — overflow regression', () {
    Widget buildControlsRow({required double width, bool volumeExpanded = false}) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.play_arrow, size: 20),
                    ),
                    const SizedBox(width: 8),
                    const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.skip_previous, size: 18),
                    ),
                    const SizedBox(width: 4),
                    const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.skip_next, size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Flexible(
                      child: Text(
                        '01:23:45 / 02:00:00',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: const Text('1.5x', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    // Mobile: just a volume button (no slider)
                    const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.volume_up, size: 18),
                    ),
                    const SizedBox(width: 8),
                    const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.fullscreen, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('no overflow at 320px mobile (volume collapsed)', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(buildControlsRow(width: 296));
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow at 360px mobile (volume collapsed)', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(buildControlsRow(width: 336));
      expect(tester.takeException(), isNull);
    });

    testWidgets('timestamp text is present and can ellipsize', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(buildControlsRow(width: 336));
      expect(find.text('01:23:45 / 02:00:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
