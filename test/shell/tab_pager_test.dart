import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:optionsschool/features/shell/tab_pager.dart';

/// The tab container the shell route uses instead of an IndexedStack.
///
/// What matters here is that a drag only changes tab when it was clearly meant
/// to, that it never runs off either end of the tab strip, and that each tab
/// keeps its own state across the move — the reason the shell holds live
/// Navigators rather than rebuilding a page at a time.
void main() {
  Future<GoRouter> pumpTabs(WidgetTester tester) async {
    final GoRouter router = GoRouter(
      initialLocation: '/a',
      routes: <RouteBase>[
        StatefulShellRoute(
          builder:
              (
                BuildContext context,
                GoRouterState state,
                StatefulNavigationShell shell,
              ) => Scaffold(body: shell),
          navigatorContainerBuilder:
              (
                BuildContext context,
                StatefulNavigationShell shell,
                List<Widget> children,
              ) => TabPager(shell: shell, branches: children),
          branches: <StatefulShellBranch>[
            for (final String name in const <String>['a', 'b', 'c'])
              StatefulShellBranch(
                routes: <RouteBase>[
                  GoRoute(
                    path: '/$name',
                    builder: (_, _) => _CountingTab(name: name),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  /// Drags across in small steps, as a finger does.
  ///
  /// One big jump is not equivalent: while the buttons in the tabs are also in
  /// the gesture arena, the drag recogniser only wins once the touch slop is
  /// passed, and the move event that passes it is spent doing so. A single
  /// move therefore reports no travel at all.
  Future<void> dragBy(WidgetTester tester, double dx) async {
    const int steps = 12;
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(TabPager)),
    );
    for (int i = 0; i < steps; i++) {
      await gesture.moveBy(Offset(dx / steps, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('dragging left moves on to the next tab', (
    WidgetTester tester,
  ) async {
    await pumpTabs(tester);
    expect(find.text('tab a'), findsOneWidget);

    await dragBy(tester, -300);

    expect(find.text('tab b'), findsOneWidget);
    // The tab left behind is offstage, so the default finder cannot see it.
    expect(find.text('tab a'), findsNothing);
  });

  testWidgets('dragging back to the right returns to the previous tab', (
    WidgetTester tester,
  ) async {
    await pumpTabs(tester);
    await dragBy(tester, -300);
    expect(find.text('tab b'), findsOneWidget);

    await dragBy(tester, 300);
    expect(find.text('tab a'), findsOneWidget);
  });

  testWidgets('a half-hearted drag springs back to the tab it started on', (
    WidgetTester tester,
  ) async {
    await pumpTabs(tester);

    await dragBy(tester, -40);

    expect(find.text('tab a'), findsOneWidget);
    expect(find.text('tab b'), findsNothing);
  });

  testWidgets('there is nothing past either end of the tab strip', (
    WidgetTester tester,
  ) async {
    await pumpTabs(tester);

    // Already on the first tab: dragging back stays put rather than sliding
    // the tab off to reveal an empty screen.
    await dragBy(tester, 400);
    expect(find.text('tab a'), findsOneWidget);

    await dragBy(tester, -400);
    await dragBy(tester, -400);
    expect(find.text('tab c'), findsOneWidget);

    // And nothing past the last one either.
    await dragBy(tester, -400);
    expect(find.text('tab c'), findsOneWidget);
  });

  testWidgets('a tab keeps its state while another one is in use', (
    WidgetTester tester,
  ) async {
    await pumpTabs(tester);

    await tester.tap(find.text('count 0'));
    await tester.pump();
    expect(find.text('count 1'), findsOneWidget);

    await dragBy(tester, -300);
    await dragBy(tester, 300);

    // The Navigator behind tab a was never torn down, so its count survived.
    expect(find.text('count 1'), findsOneWidget);
  });
}

/// A tab that remembers something, to prove the branch was kept alive.
class _CountingTab extends StatefulWidget {
  const _CountingTab({required this.name});

  final String name;

  @override
  State<_CountingTab> createState() => _CountingTabState();
}

class _CountingTabState extends State<_CountingTab> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('tab ${widget.name}'),
          TextButton(
            onPressed: () => setState(() => _count++),
            child: Text('count $_count'),
          ),
        ],
      ),
    );
  }
}
