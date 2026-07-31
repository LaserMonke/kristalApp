import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/providers/market_providers.dart';
import 'package:optionsschool/providers/repository_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The practice market pays out once a week, on what the week actually
/// returned. The rules that keep that honest — a losing week costs nothing, a
/// good week cannot dwarf the lessons — are pinned here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> boot([
    Map<String, Object> initial = const <String, Object>{},
  ]) async {
    SharedPreferences.setMockInitialValues(initial);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
  }

  group('points for a week', () {
    test(r'one point per $200 of simulated gain', () {
      expect(pointsForGain(200), 1);
      expect(pointsForGain(1000), 5);
      expect(pointsForGain(199), 0);
    });

    test('a losing week earns nothing and never subtracts', () {
      expect(pointsForGain(-5000), 0);
      expect(pointsForGain(0), 0);
    });

    test('a spectacular week is capped so the market cannot dwarf learning', () {
      expect(pointsForGain(10000000), kMaxWeeklyPoints);
    });
  });

  group('the week clock', () {
    final DateTime start = DateTime(2026, 7, 1, 9);

    test('is not due before seven days are up', () {
      const SettlementState s = SettlementState(
        weekStarted: null,
        openingEquity: 0,
        awardedTotal: 0,
      );
      expect(s.isDue(start), isFalse, reason: 'no week has started yet');

      final SettlementState running = SettlementState(
        weekStarted: start,
        openingEquity: 100000,
        awardedTotal: 0,
      );
      expect(running.isDue(start.add(const Duration(days: 6, hours: 23))),
          isFalse);
      expect(running.isDue(start.add(const Duration(days: 7))), isTrue);
      expect(running.isDue(start.add(const Duration(days: 30))), isTrue);
    });

    test('time remaining counts down and never goes negative', () {
      final SettlementState s = SettlementState(
        weekStarted: start,
        openingEquity: 100000,
        awardedTotal: 0,
      );
      expect(s.timeRemaining(start), kSettlementPeriod);
      expect(s.timeRemaining(start.add(const Duration(days: 2))).inDays, 5);
      expect(s.timeRemaining(start.add(const Duration(days: 99))), Duration.zero);
    });
  });

  group('settling', () {
    final DateTime start = DateTime(2026, 7, 1, 9);

    test('the first reading starts the clock and awards nothing', () async {
      final ProviderContainer c = await boot();
      addTearDown(c.dispose);

      final int? earned = await c
          .read(marketSettlementProvider.notifier)
          .reconcile(100000, start);

      expect(earned, isNull);
      final SettlementState s = c.read(marketSettlementProvider);
      expect(s.weekStarted, start);
      expect(s.openingEquity, 100000);
      expect(s.awardedTotal, 0);
    });

    test('nothing settles mid-week', () async {
      final ProviderContainer c = await boot();
      addTearDown(c.dispose);
      final MarketBonusController ctrl = c.read(
        marketSettlementProvider.notifier,
      );

      await ctrl.reconcile(100000, start);
      final int? earned = await ctrl.reconcile(
        140000,
        start.add(const Duration(days: 3)),
      );

      expect(earned, isNull, reason: 'a good run mid-week pays nothing yet');
      expect(c.read(marketBonusPointsProvider), 0);
    });

    test('a week up pays out and starts the next week from here', () async {
      final ProviderContainer c = await boot();
      addTearDown(c.dispose);
      final MarketBonusController ctrl = c.read(
        marketSettlementProvider.notifier,
      );

      await ctrl.reconcile(100000, start);
      final DateTime later = start.add(const Duration(days: 7));
      final int? earned = await ctrl.reconcile(102000, later);

      expect(earned, 10, reason: r'$2000 of gain at $200 a point');
      expect(c.read(marketBonusPointsProvider), 10);

      final SettlementState s = c.read(marketSettlementProvider);
      expect(s.weekStarted, later);
      expect(s.openingEquity, 102000, reason: 'next week measures from here');
    });

    test('a week down settles at zero and keeps what was already earned',
        () async {
      final ProviderContainer c = await boot();
      addTearDown(c.dispose);
      final MarketBonusController ctrl = c.read(
        marketSettlementProvider.notifier,
      );

      await ctrl.reconcile(100000, start);
      final DateTime week1 = start.add(const Duration(days: 7));
      await ctrl.reconcile(104000, week1);
      expect(c.read(marketBonusPointsProvider), 20);

      // A bad second week must not claw the first week's points back.
      final DateTime week2 = week1.add(const Duration(days: 7));
      final int? earned = await ctrl.reconcile(60000, week2);

      expect(earned, 0);
      expect(c.read(marketBonusPointsProvider), 20);
    });

    test('the total survives a restart', () async {
      final ProviderContainer first = await boot();
      final MarketBonusController ctrl = first.read(
        marketSettlementProvider.notifier,
      );
      await ctrl.reconcile(100000, start);
      await ctrl.reconcile(101000, start.add(const Duration(days: 7)));
      expect(first.read(marketBonusPointsProvider), 5);
      first.dispose();

      // Same store, new container — as if the app had been reopened.
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer second = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(second.dispose);
      expect(second.read(marketBonusPointsProvider), 5);
      expect(second.read(marketSettlementProvider).openingEquity, 101000);
    });

    test('resetting the account clears the week and the points', () async {
      final ProviderContainer c = await boot();
      addTearDown(c.dispose);
      final MarketBonusController ctrl = c.read(
        marketSettlementProvider.notifier,
      );

      await ctrl.reconcile(100000, start);
      await ctrl.reconcile(105000, start.add(const Duration(days: 7)));
      expect(c.read(marketBonusPointsProvider), 25);

      await ctrl.clear();

      expect(c.read(marketBonusPointsProvider), 0);
      expect(c.read(marketSettlementProvider).weekStarted, isNull);
    });
  });
}
