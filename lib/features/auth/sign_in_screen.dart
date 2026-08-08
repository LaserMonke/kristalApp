import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/device_unlock.dart';
import '../../core/widgets/data_location_text.dart';
import '../../data/models/education_level.dart';
import '../../data/repositories/auth_repo.dart';
import '../../data/supabase/account_identity.dart';
import '../../providers/auth_controller.dart';
import '../../providers/repository_providers.dart';
import '../../providers/saved_login_controller.dart';

/// Sign-in / sign-up.
///
/// Drives whichever AuthRepo is active: Supabase Auth when a backend is
/// configured, the device-only stub otherwise. The screen itself is unchanged
/// by that swap — only the footer, which must say honestly where the account
/// lives (CLAUDE.md rule 8).
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();

  bool _isSignUp = true;
  bool _obscure = true;
  bool _busy = false;
  EducationLevel _level = EducationLevel.undergraduate;
  String? _error;

  /// Whether to keep this sign-in on the device once it succeeds.
  ///
  /// Starts on. It is a labelled switch sitting directly above the button that
  /// acts on it, and Settings can drop the saved sign-in at any time — so it is
  /// a default, not a trick (CLAUDE.md rule 9). Only ever shown on a device
  /// that has a screen lock to put in front of it.
  bool _remember = true;

  /// Set when the learner chooses to sign in some other way, so the saved-login
  /// card gets out of the way for the rest of this visit. Deliberately not the
  /// same as forgetting the credential — that lives in Settings.
  bool _useForm = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final AuthController auth = ref.read(authControllerProvider.notifier);
    final SavedLoginController saved = ref.read(
      savedLoginControllerProvider.notifier,
    );
    try {
      if (_isSignUp) {
        await auth.signUp(
          username: _username.text,
          password: _password.text,
          educationLevel: _level,
        );
      } else {
        await auth.signIn(username: _username.text, password: _password.text);
      }
      // A failed guard leaves the controller in an error state rather than
      // throwing, so surface that here.
      final Object? error = ref.read(authControllerProvider).error;
      if (error != null) throw error;

      final String username = _username.text.trim();
      if (_remember && (ref.read(savedLoginControllerProvider).value?.canOffer ?? false)) {
        await saved.remember(username: username, password: _password.text);
      } else if (normaliseUsername(
            ref.read(savedLoginControllerProvider).value?.username ?? '',
          ) !=
          normaliseUsername(username)) {
        // Somebody else just signed in on this device. Leaving the previous
        // learner's credential saved would offer their account to whoever
        // signs out next.
        await saved.forget();
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The one-tap path: device lock, then straight in.
  Future<void> _submitSavedLogin() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(savedLoginControllerProvider.notifier).signIn();
    } on AuthException catch (e) {
      // The saved credential has already been dropped by the controller, so
      // fall back to the form rather than leaving a card that cannot work.
      if (mounted) {
        setState(() {
          _error = e.message;
          _isSignUp = false;
          _useForm = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SavedLoginState saved =
        ref.watch(savedLoginControllerProvider).value ??
        SavedLoginState.unavailable;

    // The saved card takes over the whole screen when there is one: a learner
    // coming back to their own phone should see their name and one button, not
    // a form they are not going to fill in.
    final bool showSaved = saved.hasSavedLogin && !_useForm;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Icon(
                      Icons.candlestick_chart_outlined,
                      size: 36,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Stock Options Academy',
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      showSaved || !_isSignUp
                          ? 'Welcome back.'
                          : 'Create an account to track your progress.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (showSaved) ...<Widget>[
                      _SavedLoginCard(
                        username: saved.username!,
                        lock: saved.lock,
                        busy: _busy,
                        onTap: _submitSavedLogin,
                      ),
                      if (_error != null) ...<Widget>[
                        const SizedBox(height: 18),
                        _ErrorText(_error!),
                      ],
                      const SizedBox(height: 18),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _useForm = true;
                                _isSignUp = false;
                                _error = null;
                              }),
                        child: const Text('Use my password instead'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _useForm = true;
                                _isSignUp = true;
                                _error = null;
                              }),
                        child: const Text('Sign in as someone else'),
                      ),
                    ] else ...<Widget>[
                    TextFormField(
                      controller: _username,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      // Sign-up is held to the full rule — shape and words —
                      // so a refused name is explained on the spot instead of
                      // after a round trip. Signing in only checks that
                      // something was typed: an account made under an older
                      // rule must still be able to get in, and the server
                      // decides whether the credentials are right anyway.
                      validator: (String? value) {
                        final String username = (value ?? '').trim();
                        if (!_isSignUp) {
                          return username.isEmpty
                              ? 'Enter your username'
                              : null;
                        }
                        return UsernameRule.validateNew(username);
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        // Stated while choosing, not after being refused. The
                        // server enforces the same rule but can only say so
                        // after a round trip, and it says it as a failure.
                        helperText: _isSignUp ? PasswordRule.describe : null,
                        helperMaxLines: 2,
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      // Sign-up is held to the full rule; signing in is only
                      // checked for emptiness. An account made under an older
                      // rule must still be able to get in, and the server is
                      // what decides whether the password is right anyway.
                      validator: (String? value) {
                        final String password = value ?? '';
                        if (!_isSignUp) {
                          return password.isEmpty
                              ? 'Enter your password'
                              : null;
                        }
                        return PasswordRule.validate(password);
                      },
                    ),
                    if (_isSignUp) ...<Widget>[
                      const SizedBox(height: 22),
                      Text(
                        'Where are you in your studies?',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Used to pitch lessons at the right depth. Nothing else.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _EducationPicker(
                        value: _level,
                        onChanged: (EducationLevel value) =>
                            setState(() => _level = value),
                      ),
                    ],
                    if (saved.canOffer) ...<Widget>[
                      const SizedBox(height: 8),
                      _RememberSwitch(
                        value: _remember,
                        lock: saved.lock,
                        onChanged: _busy
                            ? null
                            : (bool value) =>
                                  setState(() => _remember = value),
                      ),
                    ],
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: 18),
                      _ErrorText(_error!),
                    ],
                    const SizedBox(height: 26),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isSignUp ? 'Create account' : 'Sign in'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _isSignUp = !_isSignUp;
                              _error = null;
                            }),
                      child: Text(
                        _isSignUp
                            ? 'I already have an account'
                            : 'Create an account instead',
                      ),
                    ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      DataLocation.accounts(
                        cloudBacked: ref.watch(isCloudBackedProvider),
                      ),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The one-tap way back in: who this device remembers, and the lock that
/// releases it.
///
/// Names the account it is offering. A device can be handed round, and
/// "unlock to sign in" without saying whose account would be a way to end up
/// in someone else's progress.
class _SavedLoginCard extends StatelessWidget {
  const _SavedLoginCard({
    required this.username,
    required this.lock,
    required this.busy,
    required this.onTap,
  });

  final String username;
  final DeviceLockKind lock;
  final bool busy;
  final VoidCallback onTap;

  IconData get _icon => switch (lock) {
    DeviceLockKind.face => Icons.face_outlined,
    DeviceLockKind.fingerprint => Icons.fingerprint,
    DeviceLockKind.iris => Icons.remove_red_eye_outlined,
    DeviceLockKind.passcode || DeviceLockKind.none => Icons.lock_open_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outline),
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 18,
                backgroundColor: theme.colorScheme.primary.withValues(
                  alpha: 0.15,
                ),
                child: Text(
                  username.characters.first.toUpperCase(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(username, style: theme.textTheme.titleSmall),
                    Text(
                      'Saved on this device',
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
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: busy ? null : onTap,
          icon: busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(_icon),
          label: Text('Sign in with ${lock.label}'),
        ),
      ],
    );
  }
}

/// The offer to keep this sign-in on the device.
///
/// Says what is stored and where in the same breath as asking — CLAUDE.md
/// rule 9, and a password is exactly the thing not to be vague about.
class _RememberSwitch extends StatelessWidget {
  const _RememberSwitch({
    required this.value,
    required this.lock,
    required this.onChanged,
  });

  final bool value;
  final DeviceLockKind lock;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      title: Text('Stay signed in on this phone', style: theme.textTheme.titleSmall),
      subtitle: Text(
        'Your sign-in is kept on this device only, and ${lock.label} unlocks '
        'it. Remove it any time in Settings.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _EducationPicker extends StatelessWidget {
  const _EducationPicker({required this.value, required this.onChanged});

  final EducationLevel value;
  final ValueChanged<EducationLevel> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      children: EducationLevel.values.map((EducationLevel level) {
        final bool selected = level == value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => onChanged(level),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                  width: selected ? 1.6 : 1,
                ),
                color: selected
                    ? theme.colorScheme.primary.withValues(alpha: 0.08)
                    : null,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(level.label, style: theme.textTheme.titleSmall),
                        Text(
                          level.description,
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
        );
      }).toList(),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }
}
