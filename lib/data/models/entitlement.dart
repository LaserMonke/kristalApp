/// The app's one paid unlock: the fake-money practice market.
///
/// Everything else stays free and is meant to (CLAUDE.md, "Monetization
/// rules") — lessons, Q&A, points, streaks, levels, the certificate, the
/// leaderboard, and every pricer including the advanced one. This model
/// describes a single yes/no: has the practice market been bought.
class Entitlement {
  const Entitlement({required this.unlocked, this.priceLabel});

  /// Not bought, and nothing known from the store yet.
  const Entitlement.locked() : unlocked = false, priceLabel = null;

  final bool unlocked;

  /// The price exactly as the store formats it for this learner — `$4.99`,
  /// `4,99 €`, `¥800`.
  ///
  /// Null until the store answers, and deliberately never hardcoded: the
  /// stores set the actual charge per region and tier, so a number typed into
  /// the app would be wrong in most currencies and is grounds for App Review
  /// rejection when it disagrees with what is billed. When this is null the
  /// paywall names no figure at all.
  final String? priceLabel;

  Entitlement copyWith({bool? unlocked, String? priceLabel}) {
    return Entitlement(
      unlocked: unlocked ?? this.unlocked,
      priceLabel: priceLabel ?? this.priceLabel,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Entitlement &&
      other.unlocked == unlocked &&
      other.priceLabel == priceLabel;

  @override
  int get hashCode => Object.hash(unlocked, priceLabel);
}

/// How a trip to the store's purchase sheet ended.
enum PurchaseOutcome {
  /// Paid, and the entitlement is now active.
  unlocked,

  /// The learner backed out. Not a failure — the UI should say nothing.
  cancelled,

  /// Somebody else has to act before this completes: Ask to Buy parental
  /// approval, or a payment method that settles later.
  ///
  /// A first-class state rather than an error, because this app carries a 16+
  /// rating and Ask to Buy is exactly how a family-managed account under 18
  /// buys things. Treating it as a failure would tell a learner their money
  /// did not go through when it is simply waiting on a parent.
  pending,

  /// The store or the network refused. [PurchaseResult.message] carries the
  /// plain-language reason.
  failed,
}

/// The result of one purchase attempt.
class PurchaseResult {
  const PurchaseResult(this.outcome, {this.message});

  const PurchaseResult.cancelled()
    : outcome = PurchaseOutcome.cancelled,
      message = null;

  final PurchaseOutcome outcome;

  /// Shown to the learner as-is, so it is written in plain language and never
  /// contains a store error code. Only set when [outcome] is
  /// [PurchaseOutcome.failed].
  final String? message;
}
