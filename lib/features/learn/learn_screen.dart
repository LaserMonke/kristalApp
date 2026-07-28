import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/disclaimer_text.dart';
import '../../core/widgets/theme_toggle_button.dart';
import '../../data/models/app_user.dart';
import '../../providers/auth_controller.dart';

/// The Learn tab — home of the lesson path.
///
/// Phase 0 renders the shell and the learner's header; Phase 1 replaces the
/// body with the data-driven lesson list and card/reel player.
class LearnScreen extends ConsumerWidget {
  const LearnScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AppUser? user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Learn'),
        actions: <Widget>[const ThemeToggleButton(), const SizedBox(width: 4)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          Text(
            user == null ? 'Welcome' : 'Welcome, ${user.username}',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            user == null
                ? 'Start with what an option actually is.'
                : 'Lessons pitched for: ${user.educationLevel.label}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          const DisclaimerBanner(
            text: Disclaimers.noAdviceShort,
            icon: Icons.info_outline,
          ),
          const SizedBox(height: 20),
          Text('Your path', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          const _UpcomingLesson(
            index: 1,
            title: 'What is an option?',
            summary: 'Calls and puts — a right, not an obligation.',
          ),
          const _UpcomingLesson(
            index: 2,
            title: 'Payoff at expiry',
            summary: 'Reading a payoff diagram, and where break-even sits.',
          ),
          const _UpcomingLesson(
            index: 3,
            title: 'Why use options — and what can go wrong',
            summary:
                'The benefits, plus the honest downside: premium can go to '
                'zero, and short positions can lose much more.',
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Lesson content arrives in Phase 1.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingLesson extends StatelessWidget {
  const _UpcomingLesson({
    required this.index,
    required this.title,
    required this.summary,
  });

  final int index;
  final String title;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                height: 30,
                width: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.surfaceContainerHighest,
                  border: Border.all(color: theme.colorScheme.outline),
                ),
                child: Text('$index', style: theme.textTheme.labelLarge),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      summary,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.lock_outline,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
