import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/app.dart';
import 'package:optionsschool/providers/repository_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase 0 smoke tests: the onboarding gate, then the sign-in gate.
///
/// Both assert the CLAUDE.md rule that the educational-only disclaimer is
/// shown before any content is reachable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Widget> bootApp(Map<String, Object> initialValues) async {
    SharedPreferences.setMockInitialValues(initialValues);
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    return ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const OptionsSchoolApp(),
    );
  }

  testWidgets('a first-run learner sees the disclaimer before anything else', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(await bootApp(<String, Object>{}));
    await tester.pumpAndSettle();

    expect(find.text('Before you start'), findsOneWidget);
    expect(find.text('Educational only'), findsOneWidget);
    expect(
      find.textContaining('recommendation to buy or sell'),
      findsOneWidget,
    );
    // Risk must be stated during onboarding, not buried (CLAUDE.md rule 2).
    // It sits below the fold on a small viewport, so scroll to it.
    await tester.scrollUntilVisible(
      find.textContaining('expire worthless'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('expire worthless'), findsOneWidget);

    // Continue stays disabled until the learner ticks the acknowledgement.
    final Finder continueButton = find.widgetWithText(FilledButton, 'Continue');
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);
  });

  testWidgets('after accepting the disclaimer, sign-in is the next gate', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      await bootApp(<String, Object>{'onboarding.disclaimer_accepted': true}),
    );
    await tester.pumpAndSettle();

    expect(find.text('Stock Options Academy'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Create account'), findsOneWidget);
  });
}
