import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/core/theme/app_theme.dart';
import 'package:optionsschool/features/stockle/stockle_screen.dart';
import 'package:optionsschool/features/stockle/widgets/stockle_grid.dart';
import 'package:optionsschool/features/stockle/widgets/stockle_keyboard.dart';
import 'package:optionsschool/games/stockle/stockle_engine.dart';
import 'package:optionsschool/providers/repository_providers.dart';
import 'package:optionsschool/providers/stockle_providers.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';

/// Stockle under the conditions the SHIPPED app actually runs in: the real
/// bundled ticker list, the real theme, and a real phone's size and insets.
///
/// The other Stockle tests build a bare MaterialApp, whose default theme sizes
/// buttons to their content. The app's theme does not: it gives every filled
/// and outlined button `Size.fromHeight(52)`, a minimum whose WIDTH is
/// infinity, so buttons run full-width down a Column. Inside a Row — which
/// offers its children unbounded width — that infinite minimum is a layout
/// assertion, and it took out the whole screen: blank body, no way back.
/// Nothing caught it because no test had ever rendered this screen in the
/// app's own theme.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StockleDictionary real;

  // Loaded out here, where a plain await works. Awaiting a real asset load
  // inside testWidgets deadlocks against the fake async clock.
  setUpAll(() async {
    real = StockleDictionary.fromJson(
      jsonDecode(
            await rootBundle.loadString('assets/games/nasdaq100_4letter.json'),
          )
          as Map<String, dynamic>,
    );
  });

  Future<void> pump(WidgetTester tester, ThemeData theme) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        stockleDictionaryProvider.overrideWith((_) async => real),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: theme, home: const StockleScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final (String name, ThemeData theme) in <(String, ThemeData)>[
    ('dark', AppTheme.dark),
    ('light', AppTheme.light),
  ]) {
    testWidgets('lays out in the real $name theme on a real phone', (
      tester,
    ) async {
      // 402x874 logical at 3x, with the notch and home-indicator insets.
      tester.view.devicePixelRatio = 3.0;
      tester.view.physicalSize = const Size(1206, 2622);
      tester.view.padding = const FakeViewPadding(top: 177, bottom: 102);
      addTearDown(tester.view.reset);

      await pump(tester, theme);

      // The board and keyboard must be laid out, not merely present in the
      // tree: a layout assertion leaves the widgets there and paints nothing.
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(StockleGrid)).height, greaterThan(0));
      expect(
        tester.getSize(find.byType(StockleKeyboard)).height,
        greaterThan(0),
      );
      expect(find.widgetWithText(FilledButton, 'Guess'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Delete'), findsOneWidget);
    });
  }

  testWidgets('the real ticker list is playable', (tester) async {
    // Guards the data itself: every ticker the right length, and enough of
    // them to rotate through without repeating tomorrow.
    expect(real.length, greaterThan(20));
    for (final StockleTicker t in real.tickers) {
      expect(t.symbol.length, tickerLength, reason: '${t.symbol} is wrong');
      expect(t.name, isNotEmpty, reason: '${t.symbol} has no company name');
    }
  });
}
