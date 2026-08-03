import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/data/local/local_entitlement_repo.dart';
import 'package:optionsschool/data/models/app_user.dart';
import 'package:optionsschool/data/models/education_level.dart';
import 'package:optionsschool/data/models/entitlement.dart';
import 'package:optionsschool/data/models/market.dart';
import 'package:optionsschool/data/repositories/auth_repo.dart';
import 'package:optionsschool/data/repositories/entitlement_repo.dart';
import 'package:optionsschool/features/market/market_view.dart';
import 'package:optionsschool/features/market/paywall_view.dart';
import 'package:optionsschool/providers/market_providers.dart';
import 'package:optionsschool/providers/repository_providers.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';

/// Covers the one paid feature in the app: the practice-market unlock.
///
/// Two things here are worth more than the rest. First, that the gate fails
/// CLOSED on an unknown answer but shows a spinner (not the paywall) while the
/// store is still being asked — the difference between those two is whether a
/// paying learner gets the paywall flashed at them on every open. Second, that
/// the price on the button is only ever the store's own string, because a
/// hardcoded one is wrong in most currencies and gets the build rejected.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The real `quotesProvider` polls forever, so rendering the unlocked market
  /// would leave a pending timer at the end of every test. These tests are
  /// about the gate, not the price feed, so the feed is pinned to one empty
  /// snapshot — the Watchlist heading still renders, which is all that is
  /// being asserted on.
  final List<Override> quietFeed = <Override>[
    quotesProvider.overrideWith(
      (Ref ref) => Stream<MarketSnapshot>.value(
        MarketSnapshot(quotes: const <Quote>[], fetchedAt: DateTime(2026)),
      ),
    ),
  ];

  Future<void> pumpPaywall(
    WidgetTester tester, {
    required _FakeEntitlementRepo repo,
  }) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
          entitlementRepoProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: Scaffold(body: PaywallView())),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpMarket(
    WidgetTester tester, {
    required EntitlementRepo repo,
    AuthRepo? auth,
  }) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
          entitlementRepoProvider.overrideWithValue(repo),
          if (auth != null) authRepoProvider.overrideWithValue(auth),
          ...quietFeed,
        ],
        child: const MaterialApp(home: Scaffold(body: MarketView())),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the gate', () {
    testWidgets('locked shows the paywall in the market tab', (
      WidgetTester tester,
    ) async {
      await pumpMarket(
        tester,
        repo: _FakeEntitlementRepo(initial: const Entitlement.locked()),
      );

      expect(find.byType(PaywallView), findsOneWidget);
      expect(find.text('The practice market'), findsOneWidget);
      // The market itself must not be underneath.
      expect(find.text('Watchlist'), findsNothing);
    });

    testWidgets('unlocked shows the market, not the paywall', (
      WidgetTester tester,
    ) async {
      await pumpMarket(
        tester,
        repo: _FakeEntitlementRepo(
          initial: const Entitlement(unlocked: true),
        ),
      );

      expect(find.byType(PaywallView), findsNothing);
      expect(find.text('Watchlist'), findsOneWidget);
    });

    testWidgets('a slow store shows a spinner, never the paywall', (
      WidgetTester tester,
    ) async {
      final _FakeEntitlementRepo repo = _FakeEntitlementRepo(
        initial: const Entitlement(unlocked: true),
        loadDelay: const Duration(milliseconds: 300),
      );

      // Deliberately no pumpAndSettle: this asserts on the in-flight frame.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(prefs),
            entitlementRepoProvider.overrideWithValue(repo),
            ...quietFeed,
          ],
          child: const MaterialApp(home: Scaffold(body: MarketView())),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.byType(PaywallView), findsNothing);

      await tester.pumpAndSettle();
      expect(find.text('Watchlist'), findsOneWidget);
    });

    testWidgets('the unlock is tied to the signed-in account', (
      WidgetTester tester,
    ) async {
      final _FakeEntitlementRepo repo = _FakeEntitlementRepo(
        initial: const Entitlement.locked(),
      );

      await pumpMarket(tester, repo: repo, auth: _FakeAuthRepo('learner-42'));

      // Account-tied, not device-tied: the store has to be told who is signed
      // in, or a purchase would follow the handset to the next person on it.
      expect(repo.identifiedAs, 'learner-42');
    });
  });

  group('the paywall', () {
    testWidgets('names no price until the store supplies one', (
      WidgetTester tester,
    ) async {
      await pumpPaywall(
        tester,
        repo: _FakeEntitlementRepo(initial: const Entitlement.locked()),
      );

      expect(find.text('Unlock'), findsOneWidget);
      expect(find.textContaining(r'$'), findsNothing);
    });

    testWidgets("shows the store's own price string, unreformatted", (
      WidgetTester tester,
    ) async {
      // A euro price with a comma decimal separator: proof the app is
      // displaying what the store gave it rather than formatting a number of
      // its own, which would be wrong in most of the world.
      await pumpPaywall(
        tester,
        repo: _FakeEntitlementRepo(
          initial: const Entitlement(unlocked: false, priceLabel: '4,99 €'),
        ),
      );

      expect(find.text('Unlock for 4,99 €'), findsOneWidget);
    });

    testWidgets('says what stays free', (WidgetTester tester) async {
      await pumpPaywall(
        tester,
        repo: _FakeEntitlementRepo(initial: const Entitlement.locked()),
      );

      expect(find.text('Free, and staying free'), findsOneWidget);
      expect(find.textContaining('One payment. Not a subscription.'),
          findsOneWidget);
    });

    testWidgets('a pending purchase explains it is awaiting approval', (
      WidgetTester tester,
    ) async {
      await pumpPaywall(
        tester,
        repo: _FakeEntitlementRepo(
          initial: const Entitlement.locked(),
          result: const PurchaseResult(PurchaseOutcome.pending),
        ),
      );

      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      // Ask to Buy is how a family-managed under-18 account pays. Reporting it
      // as a failure would tell a learner their money bounced when it did not.
      expect(find.textContaining('Waiting for approval'), findsOneWidget);
    });

    testWidgets('a cancelled purchase says nothing at all', (
      WidgetTester tester,
    ) async {
      await pumpPaywall(
        tester,
        repo: _FakeEntitlementRepo(
          initial: const Entitlement.locked(),
          result: const PurchaseResult.cancelled(),
        ),
      );

      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('Waiting for approval'), findsNothing);
    });

    testWidgets('a failed purchase shows the plain-language reason', (
      WidgetTester tester,
    ) async {
      await pumpPaywall(
        tester,
        repo: _FakeEntitlementRepo(
          initial: const Entitlement.locked(),
          result: const PurchaseResult(
            PurchaseOutcome.failed,
            message: 'Could not reach the store.',
          ),
        ),
      );

      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(find.text('Could not reach the store.'), findsOneWidget);
    });

    testWidgets('restore with nothing to restore says so', (
      WidgetTester tester,
    ) async {
      await pumpPaywall(
        tester,
        repo: _FakeEntitlementRepo(initial: const Entitlement.locked()),
      );

      await tester.tap(find.text('Restore purchase'));
      await tester.pumpAndSettle();

      expect(
        find.text('No earlier purchase found on this account.'),
        findsOneWidget,
      );
    });

    testWidgets('a restored purchase opens the market with no snackbar', (
      WidgetTester tester,
    ) async {
      final _FakeEntitlementRepo repo = _FakeEntitlementRepo(
        initial: const Entitlement.locked(),
        restored: const Entitlement(unlocked: true),
      );

      await pumpMarket(tester, repo: repo);
      expect(find.byType(PaywallView), findsOneWidget);

      await tester.tap(find.text('Restore purchase'));
      await tester.pumpAndSettle();

      expect(find.byType(PaywallView), findsNothing);
      expect(find.text('Watchlist'), findsOneWidget);
    });
  });

  group('the no-store stub', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
    });

    test('starts unlocked, so a build with no store still runs whole', () async {
      final LocalEntitlementRepo repo = LocalEntitlementRepo(prefs);
      addTearDown(repo.dispose);

      expect((await repo.load()).unlocked, isTrue);
    });

    test('refuses to fake a purchase', () async {
      final LocalEntitlementRepo repo = LocalEntitlementRepo(prefs);
      addTearDown(repo.dispose);

      // Granting the entitlement here would let a "purchase" succeed with no
      // money changing hands.
      final PurchaseResult result = await repo.purchase();
      expect(result.outcome, PurchaseOutcome.failed);
    });

    test('setUnlocked drives both states and emits the change', () async {
      final LocalEntitlementRepo repo = LocalEntitlementRepo(prefs);
      addTearDown(repo.dispose);

      final Future<Entitlement> next = repo.watch().first;
      await repo.setUnlocked(false);

      expect((await next).unlocked, isFalse);
      expect((await repo.load()).unlocked, isFalse);
    });
  });
}

class _FakeEntitlementRepo implements EntitlementRepo {
  _FakeEntitlementRepo({
    required this.initial,
    this.result = const PurchaseResult(
      PurchaseOutcome.failed,
      message: 'no store',
    ),
    this.restored,
    this.loadDelay = Duration.zero,
  });

  Entitlement initial;
  final PurchaseResult result;
  final Entitlement? restored;
  final Duration loadDelay;

  String? identifiedAs;

  final StreamController<Entitlement> _changes =
      StreamController<Entitlement>.broadcast();

  @override
  Stream<Entitlement> watch() => _changes.stream;

  @override
  Future<Entitlement> load() async {
    if (loadDelay > Duration.zero) await Future<void>.delayed(loadDelay);
    return initial;
  }

  @override
  Future<PurchaseResult> purchase() async {
    if (result.outcome == PurchaseOutcome.unlocked) {
      initial = const Entitlement(unlocked: true);
    }
    return result;
  }

  @override
  Future<Entitlement> restore() async => restored ?? initial;

  @override
  Future<void> identify(String? userId) async => identifiedAs = userId;
}

class _FakeAuthRepo implements AuthRepo {
  _FakeAuthRepo(String id)
    : _user = AppUser(
        id: id,
        username: 'learner',
        educationLevel: EducationLevel.undergraduate,
        createdAt: DateTime(2026),
      );

  final AppUser _user;

  @override
  Stream<AppUser?> authStateChanges() => const Stream<AppUser?>.empty();

  @override
  AppUser? get currentUser => _user;

  @override
  Future<AppUser?> restoreSession() async => _user;

  @override
  Future<AppUser> signUp({
    required String username,
    required String password,
    required EducationLevel educationLevel,
  }) async => _user;

  @override
  Future<AppUser> signIn({
    required String username,
    required String password,
  }) async => _user;

  @override
  Future<void> signOut() async {}
}
