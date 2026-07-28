import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/local/local_auth_repo.dart';
import '../data/local/local_profile_repo.dart';
import '../data/local/local_progress_repo.dart';
import '../data/repositories/auth_repo.dart';
import '../data/repositories/profile_repo.dart';
import '../data/repositories/progress_repo.dart';

/// Overridden in `main()` once shared_preferences has loaded.
final Provider<SharedPreferences> sharedPreferencesProvider =
    Provider<SharedPreferences>(
      (Ref ref) => throw UnimplementedError(
        'sharedPreferencesProvider must be overridden in main()',
      ),
    );

/// The single seam between the app and its data layer.
///
/// Everything above these providers depends only on the abstract interfaces,
/// so Phase 6 swaps in Supabase implementations by changing these three lines
/// (or overriding them in `ProviderScope`) and nothing else.
final Provider<LocalAuthRepo> localAuthRepoProvider = Provider<LocalAuthRepo>((
  Ref ref,
) {
  final LocalAuthRepo repo = LocalAuthRepo(
    ref.watch(sharedPreferencesProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final Provider<AuthRepo> authRepoProvider = Provider<AuthRepo>(
  (Ref ref) => ref.watch(localAuthRepoProvider),
);

final Provider<ProfileRepo> profileRepoProvider = Provider<ProfileRepo>(
  (Ref ref) => LocalProfileRepo(
    ref.watch(sharedPreferencesProvider),
    ref.watch(localAuthRepoProvider),
  ),
);

final Provider<ProgressRepo> progressRepoProvider = Provider<ProgressRepo>(
  (Ref ref) => LocalProgressRepo(ref.watch(sharedPreferencesProvider)),
);
