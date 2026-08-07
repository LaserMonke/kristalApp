import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:optionsschool/core/widgets/swipe_away_panel.dart';

/// The drag that closes Settings.
///
/// Settings slides in from the LEFT, so neither direction is obviously "back".
/// Both therefore close it, and a drag too short to be meant leaves it open.
void main() {
  Future<void> pumpPanel(WidgetTester tester) async {
    final GoRouter router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Center(child: Text('home'))),
          routes: <RouteBase>[
            GoRoute(
              path: 'panel',
              builder: (_, _) => const SwipeAwayPanel(
                child: Scaffold(body: Center(child: Text('settings'))),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    router.push('/panel');
    await tester.pumpAndSettle();
    expect(find.text('settings'), findsOneWidget);
  }

  /// Drags across in small steps, as a finger does, so the travel reported to
  /// the panel is what a real swipe would report.
  Future<void> dragBy(WidgetTester tester, double dx) async {
    const int steps = 12;
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text('settings')),
    );
    for (int i = 0; i < steps; i++) {
      await gesture.moveBy(Offset(dx / steps, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('a swipe to the right closes it', (WidgetTester tester) async {
    await pumpPanel(tester);

    await dragBy(tester, 200);

    expect(find.text('settings'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('so does a swipe to the left, back the way it came in', (
    WidgetTester tester,
  ) async {
    await pumpPanel(tester);

    await dragBy(tester, -200);

    expect(find.text('settings'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('a short drag leaves it open and back where it was', (
    WidgetTester tester,
  ) async {
    await pumpPanel(tester);
    final Offset before = tester.getTopLeft(find.text('settings'));

    await dragBy(tester, 40);

    expect(find.text('settings'), findsOneWidget);
    expect(tester.getTopLeft(find.text('settings')), before);
  });
}
