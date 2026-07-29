import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/app_user.dart';
import '../../providers/auth_controller.dart';
import '../../providers/engagement_providers.dart';
import '../../providers/lesson_providers.dart';

/// The completion certificate — the top of the engagement ladder.
///
/// Earned by finishing every lesson's Q&A, so it certifies engagement with
/// the material, not points. It is explicitly labelled as study recognition:
/// not a professional qualification, licence, or any statement about trading
/// ability (CLAUDE.md rules 1 and 3).
class CertificateScreen extends ConsumerWidget {
  const CertificateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<CertificateStatus> status = ref.watch(
      certificateStatusProvider,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Certificate')),
      body: status.when(
        loading: () => const Center(
          child: SizedBox(
            height: 26,
            width: 26,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
        error: (Object error, StackTrace _) => const Center(
          child: Text('Progress could not be loaded.'),
        ),
        data: (CertificateStatus data) => data.earned
            ? _EarnedCertificate(earnedOn: data.earnedOn)
            : _Requirements(status: data),
      ),
    );
  }
}

class _EarnedCertificate extends ConsumerWidget {
  const _EarnedCertificate({required this.earnedOn});

  final DateTime? earnedOn;

  static const List<String> _months = <String>[
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];

  String get _date {
    final DateTime d = earnedOn ?? DateTime.now();
    return '${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AppUser? user = ref.watch(currentUserProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border.all(color: theme.colorScheme.primary, width: 2),
          ),
          child: Column(
            children: <Widget>[
              Container(
                height: 72,
                width: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary.withValues(alpha: 0.14),
                  border: Border.all(color: theme.colorScheme.primary),
                ),
                child: Icon(
                  Icons.workspace_premium_outlined,
                  size: 38,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'CERTIFICATE OF COMPLETION',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 2,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                user?.username ?? 'Learner',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'completed the OptionsSchool core curriculum: what options '
                'are, payoffs at expiry, uses and risks, Black-Scholes '
                'pricing, the Greeks, and option strategies — including the '
                'Q&A for every lesson.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 16),
              Text(
                _date,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'This certificate recognises completed study inside the '
          'OptionsSchool app. It is not a professional qualification or '
          'licence, says nothing about trading skill, and is not financial '
          'advice.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

/// The road to the certificate, lesson by lesson — a checklist, not a wall.
class _Requirements extends ConsumerWidget {
  const _Requirements({required this.status});

  final CertificateStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<LessonNode>> path = ref.watch(lessonPathProvider);
    final List<LessonNode> nodes = path.value ?? <LessonNode>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: <Widget>[
        Icon(
          Icons.workspace_premium_outlined,
          size: 48,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 12),
        Text(
          'Not earned yet',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Finish every lesson and its Q&A to earn the completion '
          'certificate. ${status.finishedLessons} of ${status.totalLessons} '
          'done so far.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        for (final LessonNode node in nodes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(
              label:
                  '${node.lesson.title}: '
                  '${node.isFinished ? 'finished' : 'not finished yet'}.',
              excludeSemantics: true,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 14,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.6),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      node.isFinished
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: node.isFinished
                          ? theme.pnl.correct
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        node.lesson.title,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => context.go(Routes.learn),
          child: const Text('Back to the path'),
        ),
      ],
    );
  }
}
