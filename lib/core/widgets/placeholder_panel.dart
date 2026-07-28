import 'package:flutter/material.dart';

/// Placeholder for a destination whose feature lands in a later phase.
///
/// Better than an empty screen: it tells the learner what is coming and keeps
/// the shell navigable while Phases 1–9 fill it in.
class PlaceholderPanel extends StatelessWidget {
  const PlaceholderPanel({
    required this.icon,
    required this.title,
    required this.body,
    required this.phase,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;

  /// Which build phase delivers this, e.g. 'Phase 4'.
  final String phase;

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
              Icon(icon, size: 36, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 18),
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: theme.colorScheme.outline),
                ),
                child: Text(
                  'Coming in $phase',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
