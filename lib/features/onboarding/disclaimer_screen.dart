import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/disclaimer_text.dart';
import '../../providers/onboarding_controller.dart';

/// One-time onboarding gate. Nothing else in the app is reachable until the
/// learner has read and acknowledged this (CLAUDE.md rule 1).
class DisclaimerScreen extends ConsumerStatefulWidget {
  const DisclaimerScreen({super.key});

  @override
  ConsumerState<DisclaimerScreen> createState() => _DisclaimerScreenState();
}

class _DisclaimerScreenState extends ConsumerState<DisclaimerScreen> {
  bool _acknowledged = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              children: <Widget>[
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
                    children: <Widget>[
                      Icon(
                        Icons.candlestick_chart_outlined,
                        size: 40,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Before you start',
                        style: theme.textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'OptionsSchool teaches how options work — the '
                        'mechanics, the payoffs, and the risks.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 28),
                      const _Point(
                        icon: Icons.school_outlined,
                        title: 'Educational only',
                        body: Disclaimers.educationalOnly,
                      ),
                      const _Point(
                        icon: Icons.warning_amber_outlined,
                        title: 'The downside is real',
                        body: Disclaimers.riskIsReal,
                      ),
                      const _Point(
                        icon: Icons.science_outlined,
                        title: 'Simulations are idealised',
                        body: Disclaimers.simulationOnly,
                      ),
                      const _Point(
                        icon: Icons.lock_outline,
                        title: 'We keep your data minimal',
                        body:
                            'A username and your education level, so lessons '
                            'can be pitched at the right level. Nothing more.',
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    children: <Widget>[
                      CheckboxListTile(
                        value: _acknowledged,
                        onChanged: (bool? value) =>
                            setState(() => _acknowledged = value ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'I understand this app is for learning, not advice.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: _acknowledged
                            ? () => ref
                                  .read(onboardingControllerProvider.notifier)
                                  .accept()
                            : null,
                        child: const Text('Continue'),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'You can reread this any time in Profile → Settings.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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
