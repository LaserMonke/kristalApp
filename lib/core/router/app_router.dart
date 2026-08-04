import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/app_user.dart';
import '../../features/auth/sign_in_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/learn/learn_screen.dart';
import '../../features/learn/lesson_player_screen.dart';
import '../../features/market/market_screen.dart';
import '../../features/onboarding/disclaimer_screen.dart';
import '../../features/profile/certificate_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/quiz/quiz_screen.dart';
import '../../features/sandbox/sandbox_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/splash/intro_screen.dart';
import '../../features/stockle/stockle_screen.dart';
import '../../providers/auth_controller.dart';
import '../../providers/onboarding_controller.dart';

/// Route paths, referenced by name so links survive path changes.
abstract final class Routes {
  static const String splash = '/';
  static const String disclaimer = '/welcome';
  static const String signIn = '/sign-in';
  static const String home = '/home';
  static const String learn = '/learn';
  static const String sandbox = '/sandbox';
  static const String market = '/market';
  static const String profile = '/profile';

  /// The card/reel player, pushed over the tab shell so a lesson gets the
  /// whole screen.
  static const String lesson = '/lesson/:lessonId';

  /// The graded Q&A that follows a lesson. Also full-screen: answering a
  /// question should not compete with the tab bar for attention.
  static const String quiz = '/lesson/:lessonId/quiz';

  /// The completion certificate (or the checklist on the way to it).
  static const String certificate = '/certificate';

  /// The daily ticker game. Full-screen over the shell rather than a fifth
  /// tab: it is a once-a-day visit, not a place to live.
  static const String stockle = '/stockle';

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
  ref.listen(introCompleteProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.home,
    refreshListenable: refresh,
    redirect: (BuildContext context, GoRouterState state) {
      final AsyncValue<bool> accepted = ref.read(onboardingControllerProvider);
      final AsyncValue<AppUser?> auth = ref.read(authControllerProvider);
      final String here = state.matchedLocation;

      // Hold on the splash until both persisted values have loaded, so we
      // never flash the sign-in screen at an already-signed-in learner — and
      // until the opening sequence has finished, so it is never cut off
      // halfway. A tap skips the intro, which flips the same flag.
      final bool introDone = ref.read(introCompleteProvider);
      if (accepted.isLoading || auth.isLoading || !introDone) {
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
      return gates.contains(here) ? Routes.home : null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: Routes.splash,
        builder: (_, _) => const IntroScreen(),
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
      GoRoute(
        path: Routes.certificate,
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const CertificateScreen(),
      ),
      GoRoute(
        path: Routes.stockle,
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const StockleScreen(),
      ),
      GoRoute(
        path: Routes.profile,
        parentNavigatorKey: _rootKey,
        // Settings opens from the gear in the top-LEFT, so it slides in from
        // the left — the reverse of the platform-default right-to-left push.
        pageBuilder: (BuildContext context, GoRouterState state) =>
            CustomTransitionPage<void>(
              key: state.pageKey,
              child: const ProfileScreen(),
              transitionsBuilder:
                  (
                    BuildContext context,
                    Animation<double> animation,
                    Animation<double> secondaryAnimation,
                    Widget child,
                  ) => SlideTransition(
                    position:
                        Tween<Offset>(
                          begin: const Offset(-1, 0),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                    child: child,
                  ),
            ),
      ),
      StatefulShellRoute.indexedStack(
        builder:
            (
              BuildContext context,
              GoRouterState state,
              StatefulNavigationShell shell,
            ) => AppShell(navigationShell: shell),
        branches: <StatefulShellBranch>[
          _branch(Routes.home, const HomeScreen()),
          _branch(Routes.learn, const LearnScreen()),
          _branch(Routes.sandbox, const SandboxScreen()),
          _branch(Routes.market, const MarketScreen()),
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

