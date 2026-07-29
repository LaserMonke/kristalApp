import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/disclaimer_text.dart';
import '../../../providers/sandbox_tutorial_controller.dart';

/// One-time walkthrough shown the first time a learner opens the Sandbox,
/// and reachable again afterwards from the app bar's help icon.
class SandboxTutorialSheet extends ConsumerWidget {
  const SandboxTutorialSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const SandboxTutorialSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.tune_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Welcome to the Sandbox', style: theme.textTheme.titleLarge),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const _TutorialPoint(
              icon: Icons.tune_outlined,
              text:
                  'Drag the market inputs — spot, volatility, time to expiry, rate — and watch '
                  'the price and Greeks respond live, using the same pricer from the '
                  'Black-Scholes-Merton lesson.',
            ),
            const _TutorialPoint(
              icon: Icons.calculate_outlined,
              text:
                  'Single option prices one call or put. Strategy composes several legs into '
                  'a named strategy and shows the combined payoff.',
            ),
            const _TutorialPoint(
              icon: Icons.lock_outline,
              text:
                  'Strategy unlocks once you finish the Strategies lesson in Learn, so the '
                  'presets make sense before you meet them here.',
            ),
            const SizedBox(height: 8),
            const DisclaimerBanner(),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                ref.read(sandboxTutorialSeenProvider.notifier).markSeen();
                Navigator.of(context).pop();
              },
              child: const Text('Got it'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TutorialPoint extends StatelessWidget {
  const _TutorialPoint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
          ),
        ],
      ),
    );
  }
}
