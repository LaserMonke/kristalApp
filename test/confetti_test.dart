import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/core/widgets/confetti_overlay.dart';

/// Confetti is decoration, and decoration has to stay out of the way. What is
/// pinned here is not how it looks but what it must never do: swallow a tap,
/// keep going, or animate at someone who asked the OS for less motion.
void main() {
  Widget host({
    required bool play,
    required VoidCallback onTap,
    bool reduceMotion = false,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(
        body: ConfettiOverlay(
          play: play,
          child: Center(
            child: ElevatedButton(
              onPressed: onTap,
              child: const Text('Back to the path'),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('the screen underneath stays tappable while it falls', (
    WidgetTester tester,
  ) async {
    int taps = 0;
    await tester.pumpWidget(host(play: true, onTap: () => taps++));
    await tester.pump(const Duration(milliseconds: 300));

    // Mid-burst: the button must still work.
    await tester.tap(find.text('Back to the path'));
    expect(taps, 1);

    await tester.pumpAndSettle();
  });

  testWidgets('it stops on its own and does not loop', (
    WidgetTester tester,
  ) async {
    bool finished = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConfettiOverlay(
            play: true,
            onFinished: () => finished = true,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));
    expect(finished, isFalse, reason: 'still falling');

    // pumpAndSettle would time out on a repeating animation.
    await tester.pumpAndSettle();
    expect(finished, isTrue);
  });

  testWidgets('nothing is painted when it is not playing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(play: false, onTap: () {}));
    await tester.pump();
    expect(find.byType(CustomPaint), findsWidgets); // Material paints its own
    // The overlay itself adds no painter until it is asked to play.
    expect(
      find.descendant(
        of: find.byType(ConfettiOverlay),
        matching: find.byType(IgnorePointer),
      ),
      findsNothing,
    );
  });

  testWidgets('reduce motion means no animation at all', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(play: true, onTap: () {}, reduceMotion: true),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(ConfettiOverlay),
        matching: find.byType(IgnorePointer),
      ),
      findsNothing,
      reason: 'no confetti layer is built when motion is reduced',
    );
    // The screen it wraps is untouched either way.
    expect(find.text('Back to the path'), findsOneWidget);
  });

  testWidgets('a burst happens once, not on every rebuild', (
    WidgetTester tester,
  ) async {
    int finishes = 0;
    Widget build(bool play) => MaterialApp(
      home: Scaffold(
        body: ConfettiOverlay(
          play: play,
          onFinished: () => finishes++,
          child: const SizedBox.expand(),
        ),
      ),
    );

    await tester.pumpWidget(build(true));
    await tester.pumpAndSettle();
    expect(finishes, 1);

    // Toggling the flag off and on again must not re-fire: levelling up is a
    // one-time event, and a rebuild is not a new level.
    await tester.pumpWidget(build(false));
    await tester.pump();
    await tester.pumpWidget(build(true));
    await tester.pumpAndSettle();
    expect(finishes, 1);
  });
}
