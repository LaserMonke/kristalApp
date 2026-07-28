import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/lesson.dart';

/// A tap-to-check question inside the reel.
///
/// The learner has to commit to an answer before any explanation appears —
/// reading an explanation you have already predicted teaches more than reading
/// one you have not. Wrong answers are explained, not just marked; the point
/// is understanding, not a score. Nothing here is recorded.
class ChoiceCardView extends StatefulWidget {
  const ChoiceCardView({required this.card, super.key});

  final ChoiceCard card;

  @override
  State<ChoiceCardView> createState() => _ChoiceCardViewState();
}

class _ChoiceCardViewState extends State<ChoiceCardView> {
  int? _selected;

  @override
  void didUpdateWidget(ChoiceCardView old) {
    super.didUpdateWidget(old);
    if (old.card != widget.card) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ChoiceCard card = widget.card;
    final int? selected = _selected;
    final bool answered = selected != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              Icons.psychology_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'QUICK CHECK',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (card.prompt != null) ...<Widget>[
          Text(
            card.prompt!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(card.question, style: theme.textTheme.titleLarge),
        const SizedBox(height: 18),
        for (int i = 0; i < card.options.length; i++)
          _OptionTile(
            option: card.options[i],
            index: i,
            isSelected: selected == i,
            // Nothing is revealed until the learner has answered.
            isRevealed: answered,
            onTap: () => setState(() => _selected = i),
          ),
        const SizedBox(height: 6),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: answered
              ? _Explanation(option: card.options[selected])
              : Text(
                  'Pick one to see why.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
        ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.index,
    required this.isSelected,
    required this.isRevealed,
    required this.onTap,
  });

  final ChoiceOption option;
  final int index;
  final bool isSelected;
  final bool isRevealed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PnlColors pnl = theme.pnl;

    final bool markRight = isRevealed && option.isCorrect;
    final bool markWrong = isRevealed && isSelected && !option.isCorrect;

    final Color border = markRight
        ? pnl.correct
        : markWrong
        ? pnl.incorrect
        : (isSelected ? theme.colorScheme.primary : theme.colorScheme.outline);
    final Color fill = markRight
        ? pnl.correct.withValues(alpha: 0.12)
        : markWrong
        ? pnl.incorrect.withValues(alpha: 0.12)
        : Colors.transparent;

    // The tick/cross and the letter badge carry the verdict as well as colour.
    final IconData? verdict = markRight
        ? Icons.check_circle
        : markWrong
        ? Icons.cancel
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        selected: isSelected,
        label: isRevealed
            ? '${option.text}. ${option.isCorrect ? 'Correct answer' : 'Not correct'}'
            : option.text,
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: border,
                  width: isSelected || markRight ? 1.8 : 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    height: 24,
                    width: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: border),
                    ),
                    child: Text(
                      String.fromCharCode(65 + index),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      option.text,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
                  ),
                  if (verdict != null) ...<Widget>[
                    const SizedBox(width: 8),
                    Icon(verdict, size: 20, color: border),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Explanation extends StatelessWidget {
  const _Explanation({required this.option});

  final ChoiceOption option;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color tone = option.isCorrect
        ? theme.pnl.correct
        : theme.pnl.incorrect;

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tone.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              option.isCorrect ? 'That one is right' : 'Not that one',
              style: theme.textTheme.labelLarge?.copyWith(
                color: tone,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              option.explanation,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 8),
            Text(
              'Not scored — tap the other answers to see why they do or '
              "don't work.",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
