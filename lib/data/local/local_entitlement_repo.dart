import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/entitlement.dart';
import '../repositories/entitlement_repo.dart';

/// The entitlement used when no store is configured.
///
/// This is not a paywall bypass hiding in the release build: a shipped build
/// carries RevenueCat keys and is handed the store-backed repository instead
/// (see `entitlementRepoProvider`). This one exists so the app still runs,
/// whole, on a machine with no developer account and no network — the same
/// call the rest of the app already makes for a missing `.env`.
///
/// It therefore starts UNLOCKED. A build with no store cannot verify a
/// purchase, so locking the market would leave a tab nobody could ever open,
/// and would break the offline practice market that Phase 9 shipped.
/// [setUnlocked] flips it, so the paywall can be seen during development and
/// driven from both sides in tests.
class LocalEntitlementRepo implements EntitlementRepo {
  LocalEntitlementRepo(this._prefs);

  final SharedPreferences _prefs;

  static const String _key = 'entitlement_practice_market_stub_v1';

  final StreamController<Entitlement> _changes =
      StreamController<Entitlement>.broadcast();

  @override
  Stream<Entitlement> watch() => _changes.stream;

  @override
  Future<Entitlement> load() async => _read();

  @override
  Future<PurchaseResult> purchase() async {
    // There is no store to charge. Unlocking here would let a "purchase"
    // succeed with no money changing hands, which is worse than saying no.
    return const PurchaseResult(
      PurchaseOutcome.failed,
      message: 'Purchases are not available in this build.',
    );
  }

  @override
  Future<Entitlement> restore() async => _read();

  @override
  Future<void> identify(String? userId) async {
    // Nothing to attach: no store means no purchases to tie to an account.
  }

  /// Development and tests only — see the class note.
  Future<void> setUnlocked(bool unlocked) async {
    await _prefs.setBool(_key, unlocked);
    if (!_changes.isClosed) _changes.add(_read());
  }

  Entitlement _read() =>
      Entitlement(unlocked: _prefs.getBool(_key) ?? true);

  void dispose() => _changes.close();
}
