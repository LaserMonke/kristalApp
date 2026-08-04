import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/level_badge_icons.dart';
import '../../../engagement/levels.dart';
import '../../../engagement/streak.dart';
import '../../../providers/engagement_providers.dart';

/// The Home tab's centrepiece: the app's mark in the middle, with streak,
/// points and level orbiting it, and the ring around the mark reading as
/// certificate progress.
///
/// The ring is decoration for a number stated in words further down the tab —
/// it never carries meaning on its own, so nothing is lost if it cannot be
/// seen (CLAUDE.md accessibility). Each stat keeps its own Semantics label; the
/// arrangement is visual only.
class HomeHero extends ConsumerWidget {
  const HomeHero({super.key});

  /// Rough diameter of the central disc. Bounded so it stays sensible on a
  /// small phone and does not balloon on a tablet.
  static const double _minDisc = 128;
  static const double _maxDisc = 168;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final StreakState streak =
        ref.watch(streakControllerProvider).value ?? StreakState.initial;
    final int points = ref.watch(totalPointsProvider);
    final Level level = ref.watch(levelProvider);
    final AsyncValue<CertificateStatus> certificate = ref.watch(
      certificateStatusProvider,
    );

    final DateTime now = DateTime.now();
    final int days = streak.displayCurrent(now);

    final CertificateStatus? status = certificate.value;
    final double fraction = status == null || status.totalLessons == 0
        ? 0
        : status.finishedLessons / status.totalLessons;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double disc = constraints.maxWidth.isFinite
                ? constraints.maxWidth.clamp(_minDisc, _maxDisc * 2.2) * 0.44
                : _minDisc;
            final double diameter = disc.clamp(_minDisc, _maxDisc);

            return SizedBox(
              // Enough room that the orbiting stats clear the progress ring on
              // every side. At the old +108 the level badge sat exactly on the
              // ring's bottom, so once certificate progress filled that far the
              // bright arc rendered straight through the symbol.
              height: diameter + 156,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  _Mark(diameter: diameter, fraction: fraction),
                  Align(
                    alignment: Alignment.topLeft,
                    child: _OrbitStat(
                      icon: Icons.local_fire_department_outlined,
                      value: '$days',
                      label: 'day streak',
                      semanticLabel: days == 0
                          ? 'No streak yet. Any lesson activity today starts '
                                'one.'
                          : 'Streak: $days ${days == 1 ? 'day' : 'days'}.',
                    ),
                  ),
                  Align(
                    alignment: Alignment.topRight,
                    child: _OrbitStat(
                      icon: Icons.stars_outlined,
                      value: '$points',
                      label: points == 1 ? 'point' : 'points',
                      semanticLabel: 'Points: $points.',
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: _OrbitStat(
                      icon: levelBadgeIcon(level.iconName),
                      value: level.name,
                      label: 'level ${level.rank} of ${levels.length}',
                      semanticLabel:
                          'Level ${level.rank} of ${levels.length}: '
                          '${level.name}.',
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        if (streak.needsActivity(now)) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            'No activity yet today — one card keeps the streak going.',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// The disc at the centre: the app's mark, wrapped in a progress ring.
class _Mark extends StatelessWidget {
  const _Mark({required this.diameter, required this.fraction});

  final double diameter;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SizedBox(
      width: diameter,
      height: diameter,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: fraction,
              strokeWidth: 5,
              strokeCap: StrokeCap.round,
              backgroundColor: theme.colorScheme.outline.withValues(
                alpha: 0.28,
              ),
            ),
          ),
          Container(
            width: diameter - 26,
            height: diameter - 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.55,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.candlestick_chart_outlined,
                  size: diameter * 0.34,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 4),
                Text(
                  'OptionsSchool',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.2,
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

/// One stat sitting around the mark. Icon, number, and the word for what it
/// counts — never colour alone.
class _OrbitStat extends StatelessWidget {
  const _OrbitStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.semanticLabel,
  });

  final IconData icon;
  final String value;
  final String label;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        width: 104,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
