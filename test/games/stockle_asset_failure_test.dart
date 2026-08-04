import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/features/stockle/stockle_screen.dart';
import 'package:optionsschool/providers/repository_providers.dart';
import 'package:optionsschool/providers/stockle_providers.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';

/// What a player sees when the ticker asset cannot be loaded.
///
/// This is the case that trapped a tester on an iOS simulator: a blank screen
/// with no app bar and no way back. A failure to load the game's data must
/// degrade into a message you can navigate away from — never a dead end.
void main() {
  testWidgets('a failed asset load shows an error, not a blank dead end', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
          stockleDictionaryProvider.overrideWith(
            (_) async => throw Exception('Unable to load asset'),
          ),
        ],
        child: const MaterialApp(home: StockleScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // The app bar must survive, because it carries the only way out.
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Stockle'), findsOneWidget);
    expect(find.textContaining('could not be loaded'), findsOneWidget);
  });
}
