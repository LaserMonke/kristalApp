import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/app_user.dart';
import '../data/models/entitlement.dart';
import '../data/repositories/entitlement_repo.dart';
import 'auth_controller.dart';
import 'repository_providers.dart';

/// Holds the practice-market entitlement and runs the two store actions a
/// learner can take: buy it, or restore a purchase they already made.
class EntitlementController extends AsyncNotifier<Entitlement> {
  EntitlementRepo get _repo => ref.read(entitlementRepoProvider);

  @override
  Future<Entitlement> build() async {
    final EntitlementRepo repo = ref.watch(entitlementRepoProvider);

    final StreamSubscription<Entitlement> subscription = repo.watch().listen((
      Entitlement entitlement,
    ) {
      state = AsyncValue<Entitlement>.data(entitlement);
    });
    ref.onDispose(subscription.cancel);

    // The unlock belongs to the account, not the handset, so the store has to
    // be told who is signed in before it can answer. Watching auth means this
    // rebuilds on sign-in and sign-out, which is what stops one learner's
    // purchase showing up for the next person to use the device.
    final AppUser? user = ref.watch(authControllerProvider).value;
    await repo.identify(user?.id);

    return repo.load();
  }

  /// Opens the store's purchase sheet. The returned result is what the
  /// paywall reports; the entitlement itself arrives through [build]'s
  /// subscription or the explicit reload below.
  Future<PurchaseResult> buy() async {
    final PurchaseResult result = await _repo.purchase();
    if (result.outcome == PurchaseOutcome.unlocked) {
      state = AsyncValue<Entitlement>.data(await _repo.load());
    }
    return result;
  }

  /// Re-reads purchases already made on this account.
  Future<Entitlement> restore() async {
    final Entitlement restored = await _repo.restore();
    state = AsyncValue<Entitlement>.data(restored);
    return restored;
  }
}

final AsyncNotifierProvider<EntitlementController, Entitlement>
entitlementControllerProvider =
    AsyncNotifierProvider<EntitlementController, Entitlement>(
      EntitlementController.new,
    );
