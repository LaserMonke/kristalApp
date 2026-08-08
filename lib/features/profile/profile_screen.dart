import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/device_unlock.dart';
import '../../core/feedback/feedback_settings.dart';
import '../../core/feedback/haptics.dart';
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
import '../../providers/saved_login_controller.dart';
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
          _SectionLabel('Sound & vibration', theme: theme),
          const SizedBox(height: 8),
          const _FeedbackSection(),
          const SizedBox(height: 24),
          _SectionLabel('Learning level', theme: theme),
          const SizedBox(height: 8),
          if (user != null) _EducationLevelTile(user: user),
          const SizedBox(height: 24),
          const _SavedLoginSection(),
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
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _confirmDeleteAccount(context, ref),
            icon: const Icon(Icons.person_remove_outlined),
            label: const Text('Delete account'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(color: theme.colorScheme.error),
            ),
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

  /// Permanent, unrecoverable, and required by Google Play to exist in-app.
  ///
  /// Asks the learner to type their username rather than tap "Delete". With no
  /// email on file there is no recovery and no way for us to verify a change of
  /// mind, so a mis-tap has to be impossible rather than merely unlikely.
  Future<void> _confirmDeleteAccount(BuildContext context, WidgetRef ref) async {
    final AppUser? user = ref.read(currentUserProvider);
    if (user == null) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => _DeleteAccountDialog(user.username),
    );
    if (confirmed != true) return;

    try {
      await ref.read(authControllerProvider.notifier).deleteAccount();
    } on AuthException catch (error) {
      // Still signed in, account still there. Say so — the message from the
      // repo is explicit that nothing was deleted.
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
    // On success the router sends them to sign-in, because the session ended.
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

/// Type-to-confirm dialog for account deletion.
///
/// Stateful because the Delete button stays disabled until the typed username
/// matches — the friction is the point.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog(this.username);

  final String username;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final TextEditingController _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool get _matches =>
      _typed.text.trim().toLowerCase() == widget.username.toLowerCase();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Delete your account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'This deletes your account and everything attached to it — your '
            'lessons, Q&A scores, points, streak and leaderboard entry — on '
            'this device and on the server.\n\n'
            'It cannot be undone. Because we hold no email address for you, we '
            'cannot restore the account or verify it was you afterwards.',
          ),
          const SizedBox(height: 16),
          Text(
            'Type ${widget.username} to confirm.',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _typed,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep my account'),
        ),
        FilledButton(
          onPressed: _matches
              ? () => Navigator.of(context).pop(true)
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          child: const Text('Delete for ever'),
        ),
      ],
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

/// Both feedback channels, off in one tap each.
///
/// They default on because they make the app feel finished, but neither ever
/// carries information on its own: every buzz confirms something already on
/// screen, and the chime says nothing at all. A learner who turns both off
/// loses nothing (CLAUDE.md accessibility, rule 9).
class _FeedbackSection extends ConsumerWidget {
  const _FeedbackSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool haptics = ref.watch(hapticsEnabledProvider);
    final bool sound = ref.watch(introSoundEnabledProvider);

    return Card(
      child: Column(
        children: <Widget>[
          SwitchListTile(
            secondary: const Icon(Icons.vibration),
            title: const Text('Vibration'),
            subtitle: const Text(
              'A short buzz when a trade fills or an answer is marked',
            ),
            value: haptics,
            onChanged: (bool on) {
              ref.read(hapticsEnabledProvider.notifier).set(on);
              // Feel the setting you just turned on.
              if (on) ref.read(hapticsProvider).tick();
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.music_note_outlined),
            title: const Text('Opening sound'),
            subtitle: const Text(
              'The chime when the app starts. Plays once per launch, nowhere '
              'else',
            ),
            value: sound,
            onChanged: (bool on) =>
                ref.read(introSoundEnabledProvider.notifier).set(on),
          ),
        ],
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

/// The saved sign-in on this device: what is stored, and the way to remove it.
///
/// Only rendered when there IS one. The offer to save is made at sign-in,
/// where the password is in hand — Settings cannot create one, only end it, so
/// showing an empty row here would be a switch that does nothing.
class _SavedLoginSection extends ConsumerWidget {
  const _SavedLoginSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final SavedLoginState saved =
        ref.watch(savedLoginControllerProvider).value ??
        SavedLoginState.unavailable;
    if (!saved.hasSavedLogin) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SectionLabel('Signing in', theme: theme),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.phonelink_lock_outlined),
            title: Text('Saved on this device as ${saved.username}'),
            // States plainly where the credential is and what unlocks it —
            // a learner should never have to guess whether their password
            // left the phone (CLAUDE.md rule 8).
            subtitle: Text(
              'Your sign-in is kept on this phone only and never sent '
              'anywhere. ${_capitalise(saved.lock.label)} unlocks it.',
            ),
            isThreeLine: true,
            trailing: TextButton(
              onPressed: () => _confirmForget(context, ref),
              child: const Text('Remove'),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  static String _capitalise(String text) =>
      text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

  /// Asks first: with no email on file, a learner who removes this and has
  /// forgotten their password has no way back into the account.
  Future<void> _confirmForget(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Remove the saved sign-in?'),
        content: const Text(
          'This phone will forget your username and password, and you will '
          'type them the next time you sign in. Your account, progress and '
          'points are not affected.\n\n'
          'There is no email on your account, so make sure you still know '
          'your password before removing it.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(savedLoginControllerProvider.notifier).forget();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved sign-in removed from this device.')),
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
