import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/payoff_diagram.dart';
import '../../../data/models/lesson.dart';
import '../../../pricing/payoff.dart';
import 'choice_card_view.dart';
import 'explore_card_view.dart';
import 'lesson_icons.dart';
import 'pricer_explore_card_view.dart';

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
      final ExploreCard c => ExploreCardView(card: c),
      final PricerExploreCard c => PricerExploreCardView(card: c),
      final ChoiceCard c => ChoiceCardView(card: c),
      final CompareCard c => _CompareCardView(card: c),
      final WarningCard c => _WarningCardView(card: c),
      final SummaryCard c => _SummaryCardView(card: c),
    };

    return Semantics(
      label: card.semanticLabel,
      container: true,
      child: _CardShell(child: content),
    );
  }
}

/// The physical card every page sits on.
///
/// Giving each page a visible edge is what makes the reel read as a deck: the
/// swipe animation in the player moves this surface off-screen, and a card
/// with no border would just look like text sliding around.
class _CardShell extends StatelessWidget {
  const _CardShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.colorScheme.outline),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.07),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          // A card that fits does not scroll, which leaves the vertical drag
          // to the PageView; a long card scrolls internally instead.
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 26),
            child: child,
          ),
        ),
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
    final Color primary = theme.colorScheme.primary;
    final IconData? icon = lessonIcon(card.icon);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 12),
        if (icon != null)
          _FadeInUp(
            child: Container(
              height: 76,
              width: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    primary.withValues(alpha: 0.28),
                    primary.withValues(alpha: 0.06),
                  ],
                ),
                border: Border.all(color: primary.withValues(alpha: 0.45)),
              ),
              child: Icon(icon, size: 34, color: primary),
            ),
          ),
        if (icon != null) const SizedBox(height: 26),
        if (card.kicker != null) ...<Widget>[
          _FadeInUp(
            delay: 60,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: primary.withValues(alpha: 0.35)),
              ),
              child: Text(
                card.kicker!.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: primary,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],
        _FadeInUp(
          delay: 110,
          child: Text(card.title, style: theme.textTheme.displaySmall),
        ),
        const SizedBox(height: 16),
        _FadeInUp(
          delay: 170,
          child: Text(
            card.subtitle,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 18,
              height: 1.45,
            ),
          ),
        ),
        const SizedBox(height: 24),
        _FadeInUp(
          delay: 230,
          child: Container(
            height: 4,
            width: 56,
            decoration: BoxDecoration(
              color: primary,
              borderRadius: BorderRadius.circular(2),
            ),
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
    final IconData? icon = lessonIcon(card.icon);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              _IconBadge(icon: icon, colour: theme.colorScheme.primary),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(card.heading, style: theme.textTheme.headlineSmall),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(card.body, style: theme.textTheme.bodyLarge?.copyWith(height: 1.55)),
        if (card.bullets.isNotEmpty) const SizedBox(height: 20),
        for (int i = 0; i < card.bullets.length; i++)
          _FadeInUp(
            delay: 60 * i,
            child: _NumberedPoint(
              index: i + 1,
              text: card.bullets[i],
              colour: theme.colorScheme.primary,
            ),
          ),
        if (card.highlight != null) ...<Widget>[
          const SizedBox(height: 8),
          _HighlightPanel(text: card.highlight!),
        ],
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
    final Color primary = theme.colorScheme.primary;
    final IconData? icon = lessonIcon(card.icon);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              _IconBadge(icon: icon, colour: primary, size: 44, iconSize: 22),
              const SizedBox(width: 14),
            ],
            Text(
              'DEFINITION',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(card.term, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        Container(
          height: 3,
          width: 40,
          decoration: BoxDecoration(
            color: primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          card.definition,
          style: theme.textTheme.bodyLarge?.copyWith(fontSize: 18, height: 1.5),
        ),
        if (card.example != null) ...<Widget>[
          const SizedBox(height: 22),
          _FadeInUp(
            delay: 120,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: primary.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.lightbulb_outline, size: 14, color: primary),
                      const SizedBox(width: 6),
                      Text(
                        'IN PRACTICE',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: primary,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    card.example!,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                  ),
                ],
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
        Text(card.heading, style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        // The position in chips, so the reader can check the legs against the
        // curve without re-reading the heading.
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final StrategyLeg leg in card.legs)
              _LegChip(leg: leg, currencySymbol: card.currencySymbol),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(6, 14, 12, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.colorScheme.outline),
          ),
          child: PayoffDiagram(
            legs: card.legs,
            spotMin: card.spotMin,
            spotMax: card.spotMax,
            currencySymbol: card.currencySymbol,
          ),
        ),
        const SizedBox(height: 14),
        Text(card.caption, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
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

/// One leg of a strategy, as a compact chip: side, kind, strike, premium.
class _LegChip extends StatelessWidget {
  const _LegChip({required this.leg, required this.currencySymbol});

  final StrategyLeg leg;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // Long positions hold a right, short ones an obligation — tinted with the
    // gain/loss pair only as a secondary cue; the words say which is which.
    final Color tone = leg.isLong ? theme.pnl.gain : theme.pnl.loss;

    final String kind = switch (leg.kind) {
      LegKind.call => 'call',
      LegKind.put => 'put',
      LegKind.underlying => 'underlying',
    };
    final String terms = leg.kind == LegKind.underlying
        ? 'at $currencySymbol${_short(leg.premium)}'
        : 'K $currencySymbol${_short(leg.strike)} · '
              '${leg.isLong ? 'paid' : 'received'} '
              '$currencySymbol${_short(leg.premium)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tone.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            leg.isLong ? Icons.add : Icons.remove,
            size: 13,
            color: tone,
          ),
          const SizedBox(width: 5),
          Text(
            '${leg.isLong ? 'Long' : 'Short'} $kind  $terms',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _short(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

class _CompareCardView extends StatelessWidget {
  const _CompareCardView({required this.card});

  final CompareCard card;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(card.heading, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Widget left = _ComparePanelView(panel: card.left);
            final Widget right = _ComparePanelView(panel: card.right);

            // Two narrow columns beat one wide one for comparison, but below
            // ~340dp the text gets unreadable, so they stack instead.
            if (constraints.maxWidth < 340) {
              return Column(
                children: <Widget>[
                  left,
                  const SizedBox(height: 12),
                  right,
                ],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(child: left),
                  const SizedBox(width: 12),
                  Expanded(child: right),
                ],
              ),
            );
          },
        ),
        if (card.footnote != null) ...<Widget>[
          const SizedBox(height: 16),
          _HighlightPanel(text: card.footnote!),
        ],
      ],
    );
  }
}

class _ComparePanelView extends StatelessWidget {
  const _ComparePanelView({required this.panel});

  final ComparePanel panel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color tone = switch (panel.tone) {
      PanelTone.gain => theme.pnl.gain,
      PanelTone.loss => theme.pnl.loss,
      PanelTone.neutral => theme.colorScheme.primary,
    };
    final IconData? icon = lessonIcon(panel.icon);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 24, color: tone),
            const SizedBox(height: 10),
          ],
          Text(
            panel.label,
            style: theme.textTheme.titleMedium?.copyWith(
              color: tone,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            panel.tagline,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          if (panel.points.isNotEmpty) const SizedBox(height: 12),
          for (final String point in panel.points)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    margin: const EdgeInsets.only(top: 7),
                    height: 5,
                    width: 5,
                    decoration: BoxDecoration(
                      color: tone,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      point,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
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

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                height: 34,
                width: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.report_problem_outlined,
                  size: 19,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
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
          const SizedBox(height: 18),
          Text(card.heading, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 14),
          Text(card.body, style: theme.textTheme.bodyLarge?.copyWith(height: 1.55)),
          if (card.points.isNotEmpty) const SizedBox(height: 18),
          for (int i = 0; i < card.points.length; i++)
            _FadeInUp(
              delay: 70 * i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Icon(
                        Icons.arrow_right_alt,
                        size: 18,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        card.points[i],
                        style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
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
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            _IconBadge(
              icon: Icons.flag_outlined,
              colour: theme.pnl.correct,
              size: 40,
              iconSize: 20,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(card.heading, style: theme.textTheme.headlineSmall),
            ),
          ],
        ),
        const SizedBox(height: 24),
        for (int i = 0; i < card.takeaways.length; i++)
          _FadeInUp(
            delay: 90 * i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outline),
                ),
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
                        card.takeaways[i],
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.5,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({
    required this.icon,
    required this.colour,
    this.size = 38,
    this.iconSize = 19,
  });

  final IconData icon;
  final Color colour;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(size / 3.2),
        border: Border.all(color: colour.withValues(alpha: 0.35)),
      ),
      child: Icon(icon, size: iconSize, color: colour),
    );
  }
}

class _NumberedPoint extends StatelessWidget {
  const _NumberedPoint({
    required this.index,
    required this.text,
    required this.colour,
  });

  final int index;
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
            height: 22,
            width: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colour.withValues(alpha: 0.13),
              shape: BoxShape.circle,
              border: Border.all(color: colour.withValues(alpha: 0.35)),
            ),
            child: Text(
              '$index',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colour,
                fontWeight: FontWeight.w700,
              ),
            ),
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

class _HighlightPanel extends StatelessWidget {
  const _HighlightPanel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color primary = theme.colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.push_pin_outlined, size: 16, color: primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A one-shot rise-and-fade, staggered by [delay].
///
/// Deliberately a single finite animation rather than anything looping: a
/// repeating animation would never let the widget tree settle, and a lesson
/// screen that never settles is one that never stops drawing.
class _FadeInUp extends StatelessWidget {
  const _FadeInUp({required this.child, this.delay = 0});

  final Widget child;
  final int delay;

  @override
  Widget build(BuildContext context) {
    const int total = 900;
    final double start = (delay / total).clamp(0.0, 0.8);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: total),
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      builder: (BuildContext context, double t, Widget? child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: child),
      ),
      child: child,
    );
  }
}
