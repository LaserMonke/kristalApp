import 'package:flutter/material.dart';

import '../../../games/stockle/stockle_engine.dart';

/// The clue that unlocks after [guessesBeforeHint] guesses.
///
/// Opt-in on purpose. A player who wants the puzzle clean should not have the
/// answer narrowed for them the moment they miss three times, so the unlocked
/// hint sits behind a button and only appears when it is asked for.
class StockleHintPanel extends StatelessWidget {
  const StockleHintPanel({
    super.key,
    required this.game,
    required this.revealed,
    required this.onReveal,
  });

  final StockleState game;
  final bool revealed;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final StockleHint? hint = game.hint;

    // Still locked: say so, rather than leaving the player wondering whether
    // help exists. The countdown is information, not pressure.
    if (hint == null) {
      final int remaining = guessesBeforeHint - game.guessesUsed;
      return _Line(
        icon: Icons.lock_outline,
        text: remaining == 1
            ? 'A hint unlocks after one more guess.'
            : 'A hint unlocks after $remaining more guesses.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    if (!revealed) {
      return TextButton.icon(
        onPressed: onReveal,
        icon: const Icon(Icons.lightbulb_outline, size: 18),
        label: const Text('Show a hint'),
      );
    }

    return Semantics(
      label:
          'Hint. Sector: ${hint.sector}. The company name starts with '
          '${hint.nameInitial}.',
      excludeSemantics: true,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.lightbulb_outline,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Hint',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${hint.sector} · the company’s name starts with '
                      '${hint.nameInitial}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, required this.style});

  final IconData icon;
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(icon, size: 14, color: style?.color),
        const SizedBox(width: 6),
        Flexible(child: Text(text, style: style)),
      ],
    );
  }
}
