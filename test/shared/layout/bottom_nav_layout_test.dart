import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Bottom navigation bar layout at narrow widths', () {
    Widget buildTestScaffold() {
      return MaterialApp(
        home: Scaffold(
          body: ListView(
            children: List.generate(
              20,
              (i) => ListTile(title: Text('Item $i')),
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Container(
              key: const Key('bottom_nav'),
              height: 60,
              margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(
                  5,
                  (i) => ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 56),
                    child: SizedBox(
                      height: 60,
                      child: Center(
                        child: Icon(Icons.home, key: Key('nav_item_$i')),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('renders at 360px width without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(buildTestScaffold());
      await tester.pumpAndSettle();

      final navFinder = find.byKey(const Key('bottom_nav'));
      expect(navFinder, findsOneWidget);

      final navBox = tester.renderObject(navFinder) as RenderBox;
      final navPosition = navBox.localToGlobal(Offset.zero);
      final navSize = navBox.size;

      expect(navPosition.dx, greaterThanOrEqualTo(0));
      expect(navPosition.dy, greaterThanOrEqualTo(0));
      expect(navPosition.dx + navSize.width, lessThanOrEqualTo(360));
      expect(navPosition.dy + navSize.height, lessThanOrEqualTo(640));

      for (var i = 0; i < 5; i++) {
        expect(find.byKey(Key('nav_item_$i')), findsOneWidget);
      }
    });

    testWidgets('renders at 320px width without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(buildTestScaffold());
      await tester.pumpAndSettle();

      final navFinder = find.byKey(const Key('bottom_nav'));
      expect(navFinder, findsOneWidget);

      final navBox = tester.renderObject(navFinder) as RenderBox;
      final navPosition = navBox.localToGlobal(Offset.zero);
      final navSize = navBox.size;

      expect(navPosition.dx, greaterThanOrEqualTo(0));
      expect(navPosition.dy, greaterThanOrEqualTo(0));
      expect(navPosition.dx + navSize.width, lessThanOrEqualTo(320));
      expect(navPosition.dy + navSize.height, lessThanOrEqualTo(480));

      for (var i = 0; i < 5; i++) {
        expect(find.byKey(Key('nav_item_$i')), findsOneWidget);
      }
    });

    testWidgets('body content does not extend behind bottom nav', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(buildTestScaffold());
      await tester.pumpAndSettle();

      final navFinder = find.byKey(const Key('bottom_nav'));
      final navBox = tester.renderObject(navFinder) as RenderBox;
      final navTop = navBox.localToGlobal(Offset.zero).dy;

      final listFinder = find.byType(ListView);
      expect(listFinder, findsOneWidget);
      final listBox = tester.renderObject(listFinder) as RenderBox;
      final listBottom =
          listBox.localToGlobal(Offset.zero).dy + listBox.size.height;

      expect(listBottom, lessThanOrEqualTo(navTop + 1));
    });

    testWidgets('no render overflow at 320px', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final errors = <FlutterErrorDetails>[];
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details);

      await tester.pumpWidget(buildTestScaffold());
      await tester.pumpAndSettle();

      FlutterError.onError = oldHandler;

      final overflowErrors = errors.where(
        (e) => e.toString().contains('overflowed'),
      );
      expect(overflowErrors, isEmpty);
    });

    testWidgets('no render overflow at 360px', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final errors = <FlutterErrorDetails>[];
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details);

      await tester.pumpWidget(buildTestScaffold());
      await tester.pumpAndSettle();

      FlutterError.onError = oldHandler;

      final overflowErrors = errors.where(
        (e) => e.toString().contains('overflowed'),
      );
      expect(overflowErrors, isEmpty);
    });
  });
}
