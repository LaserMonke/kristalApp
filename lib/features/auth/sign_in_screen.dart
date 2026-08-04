import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/data_location_text.dart';
import '../../data/models/education_level.dart';
import '../../data/repositories/auth_repo.dart';
import '../../providers/auth_controller.dart';
import '../../providers/repository_providers.dart';

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
    try {
      if (_isSignUp) {
        await auth.signUp(
          username: _username.text,
          password: _password.text,
          educationLevel: _level,
        );
      } else {
        await auth.signIn(
          username: _username.text,
          password: _password.text,
        );
      }
      // A failed guard leaves the controller in an error state rather than
      // throwing, so surface that here.
      final Object? error = ref.read(authControllerProvider).error;
      if (error != null) throw error;
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

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
                      _isSignUp
                          ? 'Create an account to track your progress.'
                          : 'Welcome back.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _username,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (String? value) =>
                          (value ?? '').trim().length < 3
                          ? 'At least 3 characters'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (String? value) => (value ?? '').length < 6
                          ? 'At least 6 characters'
                          : null,
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
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
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
