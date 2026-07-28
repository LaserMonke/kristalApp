import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/app_user.dart';
import '../../features/auth/sign_in_screen.dart';
import '../../features/leaderboard/leaderboard_screen.dart';
import '../../features/learn/learn_screen.dart';
import '../../features/learn/lesson_player_screen.dart';
import '../../features/onboarding/disclaimer_screen.dart';
import '../../features/practice/practice_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/quiz/quiz_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../providers/auth_controller.dart';
import '../../providers/onboarding_controller.dart';

/// Route paths, referenced by name so links survive path changes.
abstract final class Routes {
  static const String splash = '/';
  static const String disclaimer = '/welcome';
  static const String signIn = '/sign-in';
  static const String learn = '/learn';
  static const String practice = '/practice';
  static const String leaderboard = '/ranks';
  static const String profile = '/profile';

  /// The card/reel player, pushed over the tab shell so a lesson gets the
  /// whole screen.
  static const String lesson = '/lesson/:lessonId';

  /// The graded Q&A that follows a lesson. Also full-screen: answering a
  /// question should not compete with the tab bar for attention.
  static const String quiz = '/lesson/:lessonId/quiz';

  static String lessonPath(String lessonId) => '/lesson/$lessonId';

  static String quizPath(String lessonId) => '/lesson/$lessonId/quiz';
}

final GlobalKey<NavigatorState> _rootKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  // go_router needs a Listenable to re-evaluate `redirect`; bumping this
  // counter whenever auth or onboarding state changes is enough.
  final ValueNotifier<int> refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.listen(onboardingControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.learn,
    refreshListenable: refresh,
    redirect: (BuildContext context, GoRouterState state) {
      final AsyncValue<bool> accepted = ref.read(onboardingControllerProvider);
      final AsyncValue<AppUser?> auth = ref.read(authControllerProvider);
      final String here = state.matchedLocation;

      // Hold on the splash until both persisted values have loaded, so we
      // never flash the sign-in screen at an already-signed-in learner.
      if (accepted.isLoading || auth.isLoading) {
        return here == Routes.splash ? null : Routes.splash;
      }

      // The disclaimer gates everything (CLAUDE.md rule 1).
      if (accepted.value != true) {
        return here == Routes.disclaimer ? null : Routes.disclaimer;
      }

      final bool signedIn = auth.value != null;
      if (!signedIn) {
        return here == Routes.signIn ? null : Routes.signIn;
      }

      // Signed in and acknowledged — don't sit on a gate screen.
      const Set<String> gates = <String>{
        Routes.splash,
        Routes.disclaimer,
        Routes.signIn,
      };
      return gates.contains(here) ? Routes.learn : null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: Routes.splash,
        builder: (_, _) => const _SplashScreen(),
      ),
      GoRoute(
        path: Routes.disclaimer,
        builder: (_, _) => const DisclaimerScreen(),
      ),
      GoRoute(
        path: Routes.signIn,
        builder: (_, _) => const SignInScreen(),
      ),
      GoRoute(
        path: Routes.lesson,
        parentNavigatorKey: _rootKey,
        builder: (BuildContext context, GoRouterState state) =>
            LessonPlayerScreen(
              lessonId: state.pathParameters['lessonId'] ?? '',
            ),
      ),
      GoRoute(
        path: Routes.quiz,
        parentNavigatorKey: _rootKey,
        builder: (BuildContext context, GoRouterState state) =>
            QuizScreen(lessonId: state.pathParameters['lessonId'] ?? ''),
      ),
      StatefulShellRoute.indexedStack(
        builder:
            (
              BuildContext context,
              GoRouterState state,
              StatefulNavigationShell shell,
            ) => AppShell(navigationShell: shell),
        branches: <StatefulShellBranch>[
          _branch(Routes.learn, const LearnScreen()),
          _branch(Routes.practice, const PracticeScreen()),
          _branch(Routes.leaderboard, const LeaderboardScreen()),
          _branch(Routes.profile, const ProfileScreen()),
        ],
      ),
    ],
  );
});

StatefulShellBranch _branch(String path, Widget child) {
  return StatefulShellBranch(
    routes: <RouteBase>[GoRoute(path: path, builder: (_, _) => child)],
  );
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          height: 28,
          width: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}
