import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/app_user.dart';
import '../../providers/auth_controller.dart';
import '../../providers/engagement_providers.dart';
import '../../providers/lesson_providers.dart';
import 'certificate_pdf.dart';
import 'widgets/certificate_seal.dart';

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

  /// A stable reference for one learner's award.
  ///
  /// Derived from the account and the date rather than random, so reprinting
  /// gives the same number. It identifies a record in this app and certifies
  /// nothing on its own — there is no registry behind it, which is why the
  /// printed page says so.
  String _certificateId(AppUser? user) {
    final DateTime d = earnedOn ?? DateTime.now();
    final int hash = Object.hash(user?.id ?? 'learner', d.year, d.month, d.day);
    final String body = (hash & 0xFFFFFF).toRadixString(36).toUpperCase();
    return 'SOA-${d.year}-${body.padLeft(5, '0')}';
  }

  static const List<String> _topics = <String>[
    'what options are',
    'payoffs at expiry',
    'uses and honest risks',
    'Black-Scholes-Merton pricing',
    'the Greeks',
    'option strategies',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AppUser? user = ref.watch(currentUserProvider);
    final String name = user?.username ?? 'Learner';
    final String id = _certificateId(user);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: <Widget>[
        CertificateFrame(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
            color: theme.colorScheme.surface,
            child: Column(
              children: <Widget>[
                Text(
                  'STOCK OPTIONS ACADEMY',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 3,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Certificate of Completion',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Container(width: 96, height: 1.5, color: CertificateGold.mid),
                const SizedBox(height: 20),
                Text(
                  'This is to certify that',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'has completed every lesson and its assessment in the '
                  'Stock Options Academy curriculum, covering what options '
                  'are, payoffs at expiry, uses and honest risks, '
                  'Black-Scholes-Merton pricing, the Greeks, and option '
                  'strategies.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
                const SizedBox(height: 18),
                const CertificateSeal(size: 84),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    _Endorsement(label: 'Awarded', value: _date),
                    _Endorsement(label: 'Certificate ID', value: id),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => _print(context, name: name, id: id),
          icon: const Icon(Icons.print_outlined),
          label: const Text('Print or save as PDF'),
        ),
        const SizedBox(height: 16),
        Text(
          // The same sentence the printed page carries, so what a learner
          // reads here is exactly what anyone they show it to will read.
          '$certificateDisclaimer This same wording is printed on the '
          'certificate itself.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  /// Hands a vector PDF to the OS print sheet, which also covers "save as PDF"
  /// and AirDrop on iOS — one action, every sensible destination.
  Future<void> _print(
    BuildContext context, {
    required String name,
    required String id,
  }) async {
    try {
      await Printing.layoutPdf(
        name: 'Stock Options Academy certificate — $name',
        onLayout: (_) async => Uint8List.fromList(
          await buildCertificatePdf(
            learnerName: name,
            awardedOn: _date,
            certificateId: id,
            topics: _topics,
          ),
        ),
      );
    } catch (_) {
      // No printing service on this platform, or the sheet was dismissed with
      // an error. Nothing is lost — the certificate is still on screen.
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Printing is not available on this device.'),
        ),
      );
    }
  }
}

/// A value over a gold rule, the way a certificate signs itself off.
class _Endorsement extends StatelessWidget {
  const _Endorsement({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SizedBox(
      width: 132,
      child: Column(
        children: <Widget>[
          Text(
            value,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: 4),
          Container(height: 1, color: CertificateGold.mid),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              fontSize: 9,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
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
