import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/lifecycle/resume_refresher.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'providers/theme_controller.dart';

/// Root widget: themes + router. Everything else hangs off the router.
class OptionsSchoolApp extends ConsumerWidget {
  const OptionsSchoolApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoRouter router = ref.watch(routerProvider);
    final ThemeMode themeMode = ref.watch(themeControllerProvider);

    return ResumeRefresher(
      child: MaterialApp.router(
        title: 'Stock Options Academy',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        routerConfig: router,
      ),
    );
  }
}
