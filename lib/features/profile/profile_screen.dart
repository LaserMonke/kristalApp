import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/data_location_text.dart';
import '../../core/widgets/disclaimer_text.dart';
import '../../core/widgets/theme_toggle_button.dart';
import '../../data/models/app_user.dart';
import '../../data/models/education_level.dart';
import '../../data/repositories/auth_repo.dart';
import '../../data/repositories/progress_repo.dart';
import '../../providers/auth_controller.dart';
import '../../providers/engagement_providers.dart';
import '../../providers/progress_controller.dart';
import '../../providers/repository_providers.dart';
import '../../providers/theme_controller.dart';
import 'widgets/progress_section.dart';
import 'widgets/reminders_section.dart';

/// Profile and settings: identity, appearance, and the always-reachable
/// disclaimer required by CLAUDE.md rule 1.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AppUser? user = ref.watch(currentUserProvider);

    // Whether progress leaves the device. Every claim about storage below is
    // keyed on this rather than hardcoded (CLAUDE.md rule 8).
    final bool synced = ref.watch(isCloudBackedProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: const <Widget>[ThemeToggleButton(), SizedBox(width: 4)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          if (user != null) _IdentityCard(user: user),
          const SizedBox(height: 24),
          _SectionLabel('Progress', theme: theme),
          const SizedBox(height: 8),
          const ProgressSection(),
          const SizedBox(height: 24),
          _SectionLabel('Reminders', theme: theme),
          const SizedBox(height: 8),
          const RemindersSection(),
          const SizedBox(height: 24),
          _SectionLabel('Appearance', theme: theme),
          const SizedBox(height: 8),
          const _ThemeModeSelector(),
          const SizedBox(height: 24),
          _SectionLabel('Learning level', theme: theme),
          const SizedBox(height: 8),
          if (user != null) _EducationLevelTile(user: user),
          const SizedBox(height: 24),
          _SectionLabel('Legal & safety', theme: theme),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.gavel_outlined),
                  title: const Text('Educational use & disclaimers'),
                  subtitle: const Text('What this app is, and is not'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showDisclaimers(context),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Data we collect'),
                  subtitle: Text(DataLocation.collected(cloudBacked: synced)),
                  onTap: () => _showPrivacy(context, cloudBacked: synced),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _confirmReset(context, ref),
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset learning progress'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
          const SizedBox(height: 20),
          Text(
            Disclaimers.educationalOnly,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Destructive and irreversible, so it asks first and says exactly what goes
  /// — including whether the server copy goes with it.
  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final bool cloudBacked = ref.read(isCloudBackedProvider);

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Reset learning progress?'),
        content: Text(DataLocation.reset(cloudBacked: cloudBacked)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep my progress'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(progressControllerProvider.notifier).reset();
    } on ProgressException catch (error) {
      // Nothing was wiped — say so rather than showing a zeroed screen that
      // repopulates on the next sync.
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
      return;
    }

    // The streak lives beside the lesson records; reload it from the cleared
    // store so the UI drops to zero immediately.
    ref.invalidate(streakControllerProvider);
  }

  void _showDisclaimers(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) => const _DisclaimerSheet(),
    );
  }

  void _showPrivacy(BuildContext context, {required bool cloudBacked}) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Data we collect',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(DataLocation.privacy(cloudBacked: cloudBacked)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisclaimerSheet extends StatelessWidget {
  const _DisclaimerSheet();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      builder: (BuildContext context, ScrollController controller) {
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          children: <Widget>[
            Text('Disclaimers', style: theme.textTheme.titleLarge),
            const SizedBox(height: 20),
            const _Clause(
              title: 'Educational only',
              body: Disclaimers.educationalOnly,
            ),
            const _Clause(title: 'Risk', body: Disclaimers.riskIsReal),
            const _Clause(
              title: 'Simulations',
              body: Disclaimers.simulationOnly,
            ),
            const _Clause(
              title: 'Model limitations',
              body: Disclaimers.modelAssumptions,
            ),
          ],
        );
      },
    );
  }
}

class _Clause extends StatelessWidget {
  const _Clause({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              radius: 26,
              backgroundColor: theme.colorScheme.primary.withValues(
                alpha: 0.16,
              ),
              child: Text(
                user.initial,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(user.username, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    user.educationLevel.label,
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
    );
  }
}

class _ThemeModeSelector extends ConsumerWidget {
  const _ThemeModeSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode mode = ref.watch(themeControllerProvider);

    return SegmentedButton<ThemeMode>(
      segments: const <ButtonSegment<ThemeMode>>[
        ButtonSegment<ThemeMode>(
          value: ThemeMode.system,
          icon: Icon(Icons.brightness_auto_outlined),
          label: Text('System'),
        ),
        ButtonSegment<ThemeMode>(
          value: ThemeMode.light,
          icon: Icon(Icons.light_mode_outlined),
          label: Text('Light'),
        ),
        ButtonSegment<ThemeMode>(
          value: ThemeMode.dark,
          icon: Icon(Icons.dark_mode_outlined),
          label: Text('Dark'),
        ),
      ],
      selected: <ThemeMode>{mode},
      onSelectionChanged: (Set<ThemeMode> selection) =>
          ref.read(themeControllerProvider.notifier).set(selection.first),
    );
  }
}

class _EducationLevelTile extends ConsumerWidget {
  const _EducationLevelTile({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.school_outlined),
        title: Text(user.educationLevel.label),
        subtitle: Text(user.educationLevel.description),
        trailing: const Icon(Icons.edit_outlined, size: 18),
        onTap: () async {
          final EducationLevel? picked = await showModalBottomSheet<
            EducationLevel
          >(
            context: context,
            showDragHandle: true,
            builder: (BuildContext context) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: EducationLevel.values.map((EducationLevel level) {
                  final bool selected = level == user.educationLevel;
                  return ListTile(
                    leading: Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text(level.label),
                    subtitle: Text(level.description),
                    selected: selected,
                    onTap: () => Navigator.of(context).pop(level),
                  );
                }).toList(),
              ),
            ),
          );

          if (picked == null || picked == user.educationLevel) return;

          try {
            await ref
                .read(authControllerProvider.notifier)
                .updateProfile(educationLevel: picked);
          } on AuthException catch (error) {
            // The write goes to the server when one is configured, so it can
            // fail. Saying nothing would leave the old level on screen with no
            // explanation.
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(error.message)));
            }
          }
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 1.1,
      ),
    );
  }
}
