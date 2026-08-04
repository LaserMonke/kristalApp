import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../games/stockle/stockle_engine.dart';

/// On-screen keyboard.
///
/// Deliberately not the system keyboard: tickers are letters only, and the
/// key colouring is how a player tracks what they have ruled out.
class StockleKeyboard extends StatelessWidget {
  const StockleKeyboard({
    super.key,
    required this.marks,
    required this.canSubmit,
    required this.canDelete,
    required this.onLetter,
    required this.onBackspace,
    required this.onSubmit,
  });

  final Map<String, LetterMark> marks;
  final bool canSubmit;
  final bool canDelete;
  final void Function(String letter) onLetter;
  final VoidCallback onBackspace;
  final VoidCallback onSubmit;

  static const List<String> _rows = <String>[
    'QWERTYUIOP',
    'ASDFGHJKL',
    'ZXCVBNM',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final String row in _rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (final String letter in row.split(''))
                  _Key(
                    label: letter,
                    mark: marks[letter],
                    onTap: () => onLetter(letter),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _WideKey(
              label: 'Delete',
              icon: Icons.backspace_outlined,
              onTap: canDelete ? onBackspace : null,
            ),
            const SizedBox(width: 10),
            _WideKey(
              label: 'Guess',
              icon: Icons.check_circle_outline,
              filled: true,
              onTap: canSubmit ? onSubmit : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.mark, required this.onTap});

  final String label;
  final LetterMark? mark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    Color background = theme.colorScheme.surfaceContainerHighest;
    Color foreground = theme.colorScheme.onSurface;
    Color? border;

    switch (mark) {
      case LetterMark.exact:
        background = AppColors.bluishGreen;
        foreground = Colors.white;
      case LetterMark.present:
        background = AppColors.orange.withValues(alpha: 0.28);
        border = AppColors.orange;
      case LetterMark.absent:
        // Dimmed AND struck through: a ruled-out key must be obvious without
        // relying on the colour difference alone.
        background = theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        );
        foreground = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
      case null:
        break;
    }

    return Semantics(
      label: switch (mark) {
        LetterMark.exact => '$label, confirmed in the ticker',
        LetterMark.present => '$label, in the ticker',
        LetterMark.absent => '$label, ruled out',
        null => label,
      },
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(5),
          child: Container(
            width: 31,
            height: 46,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(5),
              border: border == null ? null : Border.all(color: border),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
                decoration: mark == LetterMark.absent
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WideKey extends StatelessWidget {
  const _WideKey({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}
