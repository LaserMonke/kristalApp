import '../models/entitlement.dart';

/// The store side of the practice-market unlock.
///
/// Two implementations, behind the same seam every other repository here uses:
/// `LocalEntitlementRepo` for builds with no store configured (development,
/// tests, offline), and a RevenueCat-backed one once the App Store and Play
/// products exist (DEPLOY.md, "Phase 9b"). Nothing above this interface knows
/// which one it got.
abstract interface class EntitlementRepo {
  /// The entitlement now, and every later change to it — a restore finishing,
  /// a pending purchase being approved, a refund taking it away again.
  Stream<Entitlement> watch();

  /// The entitlement at startup.
  Future<Entitlement> load();

  /// Opens the store's purchase sheet and waits for it to close.
  ///
  /// Returns rather than throws: cancelling is a normal outcome, not an error,
  /// and so is a purchase left pending parental approval.
  Future<PurchaseResult> purchase();

  /// Re-reads purchases already made on this account.
  ///
  /// Apple requires a visible way to do this for non-consumables, and it is
  /// how a reinstall or a second device gets the unlock back.
  Future<Entitlement> restore();

  /// Attaches purchases to the signed-in learner so the unlock follows the
  /// account rather than the handset. Pass null on sign-out.
  Future<void> identify(String? userId);
}
