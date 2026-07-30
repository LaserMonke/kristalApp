import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'app.dart';
import 'core/config/supabase_config.dart';
import 'providers/repository_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Loaded once up front so the repositories (and therefore the router's
  // redirect logic) can read persisted state synchronously.
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  final sb.SupabaseClient? supabase = await _initSupabase();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        supabaseClientProvider.overrideWithValue(supabase),
      ],
      child: const OptionsSchoolApp(),
    ),
  );
}

/// Brings up Supabase if `.env` supplies a project, otherwise returns null and
/// the app runs entirely on-device (see `supabaseClientProvider`).
///
/// `initialize` also restores any persisted session, which is why it is awaited
/// before the first frame: the router must not flash the sign-in screen at a
/// learner who is already signed in. A failure here is degraded, not fatal —
/// better an offline-only app than no app.
Future<sb.SupabaseClient?> _initSupabase() async {
  final SupabaseConfig config = await SupabaseConfig.load();
  if (!config.isConfigured) {
    debugPrint('No Supabase project in .env — running on-device only.');
    return null;
  }

  try {
    await sb.Supabase.initialize(
      url: config.url,
      publishableKey: config.publishableKey,
      authOptions: const sb.FlutterAuthClientOptions(
        // Tokens are exchanged with PKCE and refreshed in the background; the
        // session is held in the platform's own secure storage by the plugin.
        authFlowType: sb.AuthFlowType.pkce,
        // No OAuth or magic-link deep links to watch for, so don't run the
        // link observer — one less surface accepting URLs from outside.
        detectSessionInUri: false,
      ),
    );
    return sb.Supabase.instance.client;
  } catch (error) {
    debugPrint('Supabase init failed (${error.runtimeType}); on-device only.');
    return null;
  }
}
