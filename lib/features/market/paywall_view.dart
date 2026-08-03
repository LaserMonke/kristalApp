import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/feedback/haptics.dart';
import '../../core/widgets/disclaimer_text.dart';
import '../../data/models/entitlement.dart';
import '../../providers/entitlement_providers.dart';

/// What a learner sees on the Market tab before buying the practice market.
///
/// A view rather than a screen: it renders inside [MarketScreen]'s Scaffold,
/// in the same slot the market itself occupies, so the tab never disappears
/// from the nav and nobody has to guess where the feature went.
///
/// Copy rules that are not negotiable here (CLAUDE.md): no profit-promise
/// framing of any kind (rule 3), the simulation label stays visible (rule 4),
/// and the page states plainly what payment does and does not unlock, because
/// the whole learning core is free and should be seen to be.
///
/// Still to add before submission: links to the terms of use and the privacy
/// policy, which App Review expects on a screen that sells something and which
/// need live URLs that do not exist yet (Phase 10). They are not stubbed out
/// here, because a link that goes nowhere is worse than an absent one.
class PaywallView extends ConsumerStatefulWidget {
  const PaywallView({super.key});

  @override
  ConsumerState<PaywallView> createState() => _PaywallViewState();
}

class _PaywallViewState extends ConsumerState<PaywallView> {
  /// Blocks a second tap while the store sheet is up. Both store SDKs reject
  /// overlapping purchase calls, and a learner double-tapping a button is not
  /// an edge case.
  bool _busy = false;

  /// Set when a purchase is waiting on someone else — Ask to Buy approval, or
  /// a slow payment method. It stays on screen until the entitlement actually
  /// arrives, because there is nothing further for the learner to do.
  bool _awaitingApproval = false;

  Future<void> _buy() async {
    if (_busy) return;
    setState(() => _busy = true);
    ref.read(hapticsProvider).tick();

    try {
      final PurchaseResult result = await ref
          .read(entitlementControllerProvider.notifier)
          .buy();
      if (!mounted) return;

      switch (result.outcome) {
        case PurchaseOutcome.unlocked:
          // Nothing to announce: the tab rebuilds into the market itself,
          // which is the clearest possible confirmation.
          ref.read(hapticsProvider).impact();
        case PurchaseOutcome.cancelled:
          // Backing out is a normal thing to do. Say nothing.
          break;
        case PurchaseOutcome.pending:
          setState(() => _awaitingApproval = true);
        case PurchaseOutcome.failed:
          _say(result.message ?? 'That did not go through. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);
    ref.read(hapticsProvider).tick();

    try {
      final Entitlement restored = await ref
          .read(entitlementControllerProvider.notifier)
          .restore();
      if (!mounted) return;

      if (!restored.unlocked) {
        _say('No earlier purchase found on this account.');
      }
    } catch (_) {
      if (mounted) _say('Could not reach the store. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Entitlement? entitlement = ref
        .watch(entitlementControllerProvider)
        .value;
    final String? price = entitlement?.priceLabel;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      children: <Widget>[
        Icon(
          Icons.candlestick_chart_outlined,
          size: 44,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 14),
        Text(
          'The practice market',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Put the lessons to work. Place trades with simulated money against '
          'delayed real prices, then watch what happens to the positions you '
          'opened — including the ones that go against you.',
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
        const SizedBox(height: 22),

        const _Included('Trade with simulated cash — never real money'),
        const _Included('Delayed real market prices, labelled as delayed'),
        const _Included(
          'Positions valued with the same models the lessons teach',
        ),
        const _Included('Weekly settlement, and points for taking part'),

        const SizedBox(height: 22),
        const DisclaimerBanner(),
        const SizedBox(height: 20),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Free, and staying free',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Every lesson and quiz, all the pricers including the '
                  'advanced ones, points, streaks, levels, your certificate '
                  'and the leaderboard. This unlocks the practice market and '
                  'nothing else.',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                ),
              ],
            ),
          ),
        ),

        if (_awaitingApproval) ...<Widget>[
          const SizedBox(height: 16),
          _PendingNote(),
        ],

        const SizedBox(height: 22),
        FilledButton(
          onPressed: _busy ? null : _buy,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
          child: _busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              // No price until the store supplies one, in the store's own
              // formatting. See Entitlement.priceLabel for why this is never
              // a hardcoded number.
              : Text(price == null ? 'Unlock' : 'Unlock for $price'),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'One payment. Not a subscription.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Apple requires a visible restore path for non-consumables, and it is
        // how a reinstall or a second device gets the unlock back.
        TextButton(
          onPressed: _busy ? null : _restore,
          child: const Text('Restore purchase'),
        ),
      ],
    );
  }
}

class _Included extends StatelessWidget {
  const _Included(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.check, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown while a purchase waits on Ask to Buy approval or a slow payment
/// method. There is no action to offer, so it offers none — it just explains
/// why nothing has changed yet.
class _PendingNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.hourglass_empty,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Waiting for approval. Some accounts need a parent or account '
              'holder to approve a purchase. The practice market opens here '
              'as soon as that happens — you do not need to pay again.',
              style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
