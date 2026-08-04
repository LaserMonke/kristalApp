import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:optionsschool/core/router/app_router.dart';
import 'package:optionsschool/features/stockle/stockle_screen.dart';
import 'package:optionsschool/providers/repository_providers.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';

/// Navigating to Stockle THROUGH THE REAL ROUTER.
///
/// The screen tests build StockleScreen directly, which skips the redirect
/// rules and the shell — exactly where a new top-level route goes wrong.
void main() {
  testWidgets('/stockle resolves to the Stockle screen, not a blank page', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final GoRouter router = GoRouter(
      initialLocation: Routes.stockle,
      routes: <RouteBase>[
        GoRoute(
          path: Routes.stockle,
          builder: (_, _) => const StockleScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(StockleScreen), findsOneWidget);
    expect(find.text('Stockle'), findsOneWidget);
    // The board must actually be there, not just the scaffold.
    expect(find.widgetWithText(FilledButton, 'Guess'), findsOneWidget);
  });
}
