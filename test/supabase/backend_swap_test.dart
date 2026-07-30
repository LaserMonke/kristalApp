import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:optionsschool/core/config/supabase_config.dart';
import 'package:optionsschool/data/local/local_auth_repo.dart';
import 'package:optionsschool/data/local/local_profile_repo.dart';
import 'package:optionsschool/data/local/local_progress_repo.dart';
import 'package:optionsschool/data/supabase/supabase_auth_repo.dart';
import 'package:optionsschool/data/supabase/supabase_profile_repo.dart';
import 'package:optionsschool/data/supabase/supabase_progress_repo.dart';
import 'package:optionsschool/features/auth/sign_in_screen.dart';
import 'package:optionsschool/providers/repository_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// The local → Supabase swap, which is the whole point of Phase 6: one seam,
/// and the app is honest about which side of it the learner is on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> emptyPrefs() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    return SharedPreferences.getInstance();
  }

  group('repository selection', () {
    test('no backend configured → every repository stays on the device', () async {
      final SharedPreferences prefs = await emptyPrefs();
      final ProviderContainer container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      expect(container.read(isCloudBackedProvider), isFalse);
      expect(container.read(supabaseAuthRepoProvider), isNull);
      expect(container.read(authRepoProvider), isA<LocalAuthRepo>());
      expect(container.read(profileRepoProvider), isA<LocalProfileRepo>());
      expect(container.read(progressRepoProvider), isA<LocalProgressRepo>());
    });

    test('a backend configured → all three swap, nothing above them changes', () async {
      final SharedPreferences prefs = await emptyPrefs();
      final sb.SupabaseClient client = sb.SupabaseClient(
        'https://stub.supabase.co',
        'stub-publishable-key',
        httpClient: _SilentHttpClient(),
      );
      addTearDown(client.dispose);

      final ProviderContainer container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          supabaseClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(isCloudBackedProvider), isTrue);
      expect(container.read(authRepoProvider), isA<SupabaseAuthRepo>());
      expect(container.read(profileRepoProvider), isA<SupabaseProfileRepo>());
      expect(container.read(progressRepoProvider), isA<SupabaseProgressRepo>());
    });
  });

  group('data honesty (CLAUDE.md rule 8)', () {
    Future<void> pumpSignIn(WidgetTester tester, {required bool cloud}) async {
      final SharedPreferences prefs = await emptyPrefs();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            isCloudBackedProvider.overrideWithValue(cloud),
          ],
          child: const MaterialApp(home: SignInScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('on-device mode does not claim cloud sync', (tester) async {
      await pumpSignIn(tester, cloud: false);

      expect(find.textContaining('stored on this device only'), findsOneWidget);
      expect(find.textContaining('follow you to a new device'), findsNothing);
    });

    testWidgets('server mode says data leaves the device, and that a password '
        'cannot be reset', (tester) async {
      await pumpSignIn(tester, cloud: true);

      expect(find.textContaining('saved to the OptionsSchool server'), findsOneWidget);
      // No email on file means no reset link; promising one would be a lie.
      expect(find.textContaining('cannot be reset'), findsOneWidget);
      expect(find.textContaining('this device only'), findsNothing);
    });
  });

  group('key safety', () {
    test('a publishable/anon key is accepted', () {
      // Payload: {"role":"anon", ...}
      final String anon = _jwt(<String, dynamic>{
        'iss': 'supabase',
        'role': 'anon',
      });
      expect(SupabaseConfig.looksLikeServiceRoleKey(anon), isFalse);
      expect(
        const SupabaseConfig(url: 'https://x.supabase.co', publishableKey: 'k')
            .isConfigured,
        isTrue,
      );
    });

    test('a service_role key is refused — it would bypass RLS for everyone', () {
      final String serviceRole = _jwt(<String, dynamic>{
        'iss': 'supabase',
        'role': 'service_role',
      });
      expect(SupabaseConfig.looksLikeServiceRoleKey(serviceRole), isTrue);
      expect(
        SupabaseConfig.looksLikeServiceRoleKey('sb_secret_abc123'),
        isTrue,
      );
    });

    test('a blank config means on-device only, not a crash', () {
      expect(const SupabaseConfig.unset().isConfigured, isFalse);
      expect(
        const SupabaseConfig(url: 'https://x.supabase.co', publishableKey: '')
            .isConfigured,
        isFalse,
      );
    });
  });
}

/// A JWT-shaped string with [payload] in the middle segment. The signature is
/// irrelevant — we only ever read the claims to spot a misplaced secret.
String _jwt(Map<String, dynamic> payload) {
  String segment(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${segment(<String, String>{'alg': 'HS256'})}'
      '.${segment(payload)}.signature';
}

/// Never answers; these tests only inspect which repository was constructed.
class _SilentHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw http.ClientException('no network in tests', request.url);
  }
}
