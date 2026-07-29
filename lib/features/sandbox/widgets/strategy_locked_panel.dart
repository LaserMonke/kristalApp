import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';

/// Stands in for the Strategy tab until the "options-strategies" lesson is
/// finished — so a learner meets bull/bear spreads, the straddle, the
/// covered call and the protective put in Learn first, and the preset
/// picker here is recognising something rather than introducing it cold.
class StrategyLockedPanel extends StatelessWidget {
  const StrategyLockedPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.lock_outline, size: 36, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 18),
              Text('Strategy tab locked', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Finish the "Options strategies" lesson in Learn to unlock spreads, the '
                'straddle, the covered call and the protective put here — so the presets '
                'make sense before you meet them.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => context.go(Routes.learn),
                icon: const Icon(Icons.school_outlined),
                label: const Text('Go to Learn'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
