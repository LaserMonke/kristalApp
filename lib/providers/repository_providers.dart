import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../core/auth/device_unlock.dart';
import '../data/local/asset_lesson_repo.dart';
import '../data/local/disclaimer_store.dart';
import '../data/local/local_auth_repo.dart';
import '../data/local/local_leaderboard_repo.dart';
import '../data/local/local_market_repo.dart';
import '../data/local/local_portfolio_repo.dart';
import '../data/local/lesson_resume_store.dart';
import '../data/local/local_profile_repo.dart';
import '../data/local/local_progress_repo.dart';
import '../data/local/secure_saved_login_store.dart';
import '../data/repositories/auth_repo.dart';
import '../data/repositories/leaderboard_repo.dart';
import '../data/repositories/lesson_repo.dart';
import '../data/repositories/market_repo.dart';
import '../data/repositories/portfolio_repo.dart';
import '../data/repositories/profile_repo.dart';
import '../data/repositories/progress_repo.dart';
import '../data/repositories/saved_login_store.dart';
import '../data/supabase/supabase_auth_repo.dart';
import '../data/supabase/supabase_leaderboard_repo.dart';
import '../data/supabase/supabase_market_repo.dart';
import '../data/supabase/supabase_profile_repo.dart';
import '../data/supabase/supabase_progress_repo.dart';

/// Overridden in `main()` once shared_preferences has loaded.
final Provider<SharedPreferences> sharedPreferencesProvider =
    Provider<SharedPreferences>(
      (Ref ref) => throw UnimplementedError(
        'sharedPreferencesProvider must be overridden in main()',
      ),
    );

/// The live Supabase client, or null when no backend is configured.
///
/// Overridden in `main()` after `Supabase.initialize`. Null is a supported,
/// tested state — a missing/blank `.env`, a backend that failed to initialise,
/// or a widget test — and puts the app on the on-device repositories below.
final Provider<sb.SupabaseClient?> supabaseClientProvider =
    Provider<sb.SupabaseClient?>((Ref ref) => null);

/// True when progress and profiles are syncing to the server. Drives the copy
/// that tells the learner where their data actually lives (CLAUDE.md rule 8:
/// data honesty) — never claim cloud sync we are not doing.
final Provider<bool> isCloudBackedProvider = Provider<bool>(
  (Ref ref) => ref.watch(supabaseClientProvider) != null,
);

// ---------------------------------------------------------------------------
// The single seam between the app and its data layer.
//
// Everything above these providers depends only on the abstract interfaces, so
// swapping local for Supabase happens here and nowhere else — no screen, no
// controller and no test above this line knows which implementation it got.
// ---------------------------------------------------------------------------

final Provider<LocalAuthRepo> localAuthRepoProvider = Provider<LocalAuthRepo>((
  Ref ref,
) {
  final LocalAuthRepo repo = LocalAuthRepo(
    ref.watch(sharedPreferencesProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final Provider<SupabaseAuthRepo?> supabaseAuthRepoProvider =
    Provider<SupabaseAuthRepo?>((Ref ref) {
      final sb.SupabaseClient? client = ref.watch(supabaseClientProvider);
      if (client == null) return null;

      final SupabaseAuthRepo repo = SupabaseAuthRepo(client);
      ref.onDispose(repo.dispose);
      return repo;
    });

final Provider<AuthRepo> authRepoProvider = Provider<AuthRepo>((Ref ref) {
  final SupabaseAuthRepo? remote = ref.watch(supabaseAuthRepoProvider);
  // Only build the device-only stub when there is no backend, so its account
  // records are never touched in a server build.
  return remote ?? ref.watch(localAuthRepoProvider);
});

final Provider<ProfileRepo> profileRepoProvider = Provider<ProfileRepo>((
  Ref ref,
) {
  final SharedPreferences prefs = ref.watch(sharedPreferencesProvider);
  final sb.SupabaseClient? client = ref.watch(supabaseClientProvider);

  if (client == null) {
    return LocalProfileRepo(prefs, ref.watch(localAuthRepoProvider));
  }
  return SupabaseProfileRepo(
    client: client,
    // Device-scoped either way — see DisclaimerStore.
    disclaimers: DisclaimerStore(prefs),
    auth: ref.watch(supabaseAuthRepoProvider),
  );
});

final Provider<ProgressRepo> progressRepoProvider = Provider<ProgressRepo>((
  Ref ref,
) {
  final SharedPreferences prefs = ref.watch(sharedPreferencesProvider);
  final LocalProgressRepo local = LocalProgressRepo(prefs);

  final sb.SupabaseClient? client = ref.watch(supabaseClientProvider);
  if (client == null) return local;

  // The local store stays in play as the offline cache, so a lesson finished
  // without signal is never lost.
  return SupabaseProgressRepo(client: client, cache: local, prefs: prefs);
});

/// One saved sign-in for this device, in the platform keystore, and the device
/// lock that releases it.
///
/// Kept apart from [authRepoProvider]: the account still lives wherever the
/// auth repository says it does. This only decides whether the learner has to
/// type their password to get back to it.
final Provider<SavedLoginStore> savedLoginStoreProvider =
    Provider<SavedLoginStore>(
      (Ref ref) =>
          const SecureSavedLoginStore(SecureSavedLoginStore.defaultStorage),
    );

final Provider<DeviceUnlock> deviceUnlockProvider = Provider<DeviceUnlock>(
  (Ref ref) => LocalAuthDeviceUnlock(LocalAuthentication()),
);

/// Where the learner left off in each lesson — the card on screen and any Q&A
/// run in progress.
///
/// Device-local with no server half, unlike the progress repository above: a
/// bookmark is not an achievement (see `LessonResume`).
final Provider<LessonResumeStore> lessonResumeStoreProvider =
    Provider<LessonResumeStore>(
      (Ref ref) => LessonResumeStore(ref.watch(sharedPreferencesProvider)),
    );

final Provider<LeaderboardRepo> leaderboardRepoProvider =
    Provider<LeaderboardRepo>((Ref ref) {
      final sb.SupabaseClient? client = ref.watch(supabaseClientProvider);
      if (client != null) return SupabaseLeaderboardRepo(client);

      // No server means no other learners to rank against. The local repo says
      // so honestly rather than inventing rivals (CLAUDE.md rule 7).
      return LocalLeaderboardRepo(
        auth: ref.watch(authRepoProvider),
        progress: ref.watch(progressRepoProvider),
      );
    });

/// Delayed quotes for the practice market. With a backend, reads go through the
/// `market-data-proxy` Edge Function (Finnhub key stays server-side, rule 8);
/// without one, the synthetic walk keeps the tab usable offline.
final Provider<MarketRepo> marketRepoProvider = Provider<MarketRepo>((Ref ref) {
  final LocalMarketRepo offline = LocalMarketRepo();

  final sb.SupabaseClient? client = ref.watch(supabaseClientProvider);
  if (client == null) return offline;

  return SupabaseMarketRepo(client: client, offline: offline);
});

/// The fake-money practice portfolio — device-local for now.
final Provider<PortfolioRepo> portfolioRepoProvider = Provider<PortfolioRepo>((
  Ref ref,
) {
  return LocalPortfolioRepo(ref.watch(sharedPreferencesProvider));
});

/// Lesson content. Bundled as an asset for now; a Supabase-backed
/// implementation would let content ship without an app-store release.
final Provider<LessonRepo> lessonRepoProvider = Provider<LessonRepo>(
  (Ref ref) => AssetLessonRepo(),
);
