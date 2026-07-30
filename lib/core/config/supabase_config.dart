import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Backend credentials, read from the bundled `.env` (gitignored — see
/// `.env.example` and DEPLOY.md §1a).
///
/// Only the project URL and the PUBLISHABLE (anon) key live here. Those are
/// designed to ship inside a client and are safe to do so *because* Row Level
/// Security is on for every user table (`supabase/migrations`). The
/// `service_role` key bypasses RLS and must never reach the app bundle; any
/// paid data-API key stays in an Edge Function (CLAUDE.md rule 8).
@immutable
class SupabaseConfig {
  const SupabaseConfig({required this.url, required this.publishableKey});

  const SupabaseConfig.unset() : url = '', publishableKey = '';

  final String url;
  final String publishableKey;

  /// False when `.env` is missing or blank. The app then runs entirely on the
  /// on-device repositories — no network, no sync, still fully usable.
  bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;

  /// Loads `.env` if present. Never throws: a developer without a `.env` (or a
  /// learner whose bundle predates one) gets the offline build rather than a
  /// crash on launch.
  static Future<SupabaseConfig> load() async {
    try {
      await dotenv.load(isOptional: true);
    } catch (error) {
      debugPrint('Could not read .env; running on-device only. ($error)');
      return const SupabaseConfig.unset();
    }

    final String url = (dotenv.maybeGet('SUPABASE_URL') ?? '').trim();
    final String key = (dotenv.maybeGet('SUPABASE_PUBLISHABLE_KEY') ?? '')
        .trim();

    if (url.isEmpty || key.isEmpty) return const SupabaseConfig.unset();

    // A pasted service_role key would silently hand every learner full
    // read/write access to every other learner's rows. Refuse it outright
    // rather than shipping it.
    if (looksLikeServiceRoleKey(key)) {
      throw StateError(
        'SUPABASE_PUBLISHABLE_KEY in .env looks like a service_role key. '
        'That key bypasses Row Level Security and must never ship in the app '
        '— use the publishable/anon key instead.',
      );
    }

    return SupabaseConfig(url: url, publishableKey: key);
  }

  /// Legacy Supabase keys are JWTs whose payload carries `"role":"service_role"`.
  /// Newer secret keys are recognisable by their `sb_secret_` prefix.
  @visibleForTesting
  static bool looksLikeServiceRoleKey(String key) {
    if (key.startsWith('sb_secret_')) return true;

    final List<String> parts = key.split('.');
    if (parts.length != 3) return false;
    try {
      final String payload = utf8.decode(base64Url.decode(base64.normalize(parts[1])));
      return payload.replaceAll(' ', '').contains('"role":"service_role"');
    } catch (_) {
      // Not a JWT we can read — leave it to Supabase to reject.
      return false;
    }
  }
}
