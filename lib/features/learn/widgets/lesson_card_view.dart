import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/payoff_diagram.dart';
import '../../../data/models/lesson.dart';

/// Renders one lesson card.
///
/// The switch is exhaustive over the sealed [LessonCard] hierarchy, so adding
/// a card type to the data model forces a visual treatment to be written here
/// rather than silently rendering nothing.
class LessonCardView extends StatelessWidget {
  const LessonCardView({required this.card, super.key});

  final LessonCard card;

  @override
  Widget build(BuildContext context) {
    final Widget content = switch (card) {
      final TitleCard c => _TitleCardView(card: c),
      final TextCard c => _TextCardView(card: c),
      final TermCard c => _TermCardView(card: c),
      final PayoffCard c => _PayoffCardView(card: c),
      final WarningCard c => _WarningCardView(card: c),
      final SummaryCard c => _SummaryCardView(card: c),
    };

    return Semantics(
      label: card.semanticLabel,
      container: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        child: content,
      ),
    );
  }
}

class _TitleCardView extends StatelessWidget {
  const _TitleCardView({required this.card});

  final TitleCard card;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 40),
        if (card.kicker != null) ...<Widget>[
          Text(
            card.kicker!.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
        ],
        Text(card.title, style: theme.textTheme.displaySmall),
        const SizedBox(height: 16),
        Text(
          card.subtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 18,
          ),
        ),
      ],
    );
  }
}

class _TextCardView extends StatelessWidget {
  const _TextCardView({required this.card});

  final TextCard card;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 24),
        Text(card.heading, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 14),
        Text(
          card.body,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.55),
        ),
        if (card.bullets.isNotEmpty) const SizedBox(height: 18),
        for (final String bullet in card.bullets)
          _Bullet(text: bullet, colour: theme.colorScheme.primary),
      ],
    );
  }
}

class _TermCardView extends StatelessWidget {
  const _TermCardView({required this.card});

  final TermCard card;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 32),
        Text(
          'DEFINITION',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Text(card.term, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 14),
        Text(
          card.definition,
          style: theme.textTheme.bodyLarge?.copyWith(fontSize: 18, height: 1.5),
        ),
        if (card.example != null) ...<Widget>[
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              border: Border(
                left: BorderSide(color: theme.colorScheme.primary, width: 3),
                top: BorderSide(color: theme.colorScheme.outline),
                right: BorderSide(color: theme.colorScheme.outline),
                bottom: BorderSide(color: theme.colorScheme.outline),
              ),
            ),
            child: Text(
              card.example!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PayoffCardView extends StatelessWidget {
  const _PayoffCardView({required this.card});

  final PayoffCard card;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 20),
        Text(card.heading, style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 14, 12, 12),
            child: PayoffDiagram(
              legs: card.legs,
              spotMin: card.spotMin,
              spotMax: card.spotMax,
              currencySymbol: card.currencySymbol,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          card.caption,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
        const SizedBox(height: 14),
        // CLAUDE.md rules 4 and 5: say what the model leaves out, next to the
        // model — not only in a settings screen.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.science_outlined,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Idealised: value at expiry only, with no fees, bid/ask spread, '
                'dividends or early exercise.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WarningCardView extends StatelessWidget {
  const _WarningCardView({required this.card});

  final WarningCard card;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = theme.pnl.loss;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 28),
        Row(
          children: <Widget>[
            Icon(Icons.report_problem_outlined, size: 20, color: accent),
            const SizedBox(width: 10),
            Text(
              'KNOW THE RISK',
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(card.heading, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 14),
        Text(
          card.body,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.55),
        ),
        if (card.points.isNotEmpty) const SizedBox(height: 18),
        for (final String point in card.points)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Icon(Icons.arrow_right_alt, size: 18, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    point,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SummaryCardView extends StatelessWidget {
  const _SummaryCardView({required this.card});

  final SummaryCard card;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 32),
        Text(card.heading, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 20),
        for (final String takeaway in card.takeaways)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.check_circle_outline,
                    size: 18,
                    color: theme.pnl.correct,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    takeaway,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text, required this.colour});

  final String text;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            margin: const EdgeInsets.only(top: 8),
            height: 6,
            width: 6,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.5,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
