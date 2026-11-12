import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liyu_social/app/app.dart';
import 'package:liyu_social/app/bootstrap.dart';
import 'package:liyu_social/core/router/app_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every screen, on a 5-inch handset.
///
/// Layout is the part of this app that cannot be reasoned about on a desktop
/// window: a row that fits at 1200 px overflows at 390 px, and flutter_test
/// turns that overflow into a failed assertion. So the walk runs on a phone
/// surface and visits the routes the seeded demo content makes reachable.
void main() {
  Future<ProviderContainer> pumpPhone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final result = await bootstrap();
    final container = ProviderContainer(overrides: withBootstrapResult(result.overrides, result));
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: LiyuApp(result: result)),
    );
    await tester.pump();
    return container;
  }

  Future<void> signIn(WidgetTester tester) async {
    await tester.tap(find.text('Continue with phone'));
    await tester.pump();

    // The minted code is only on screen once the flow reaches the code step.
    final code = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .firstWhere((data) => data.startsWith('Local backend: your code is'))
        .split(' ')
        .last;

    await tester.enterText(find.byType(TextField).first, code);
    await tester.pump();
    await tester.tap(find.text('Verify'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(NavigationBar), findsOneWidget);
  }

  /// `go` for shell branches, `push` for the screens that cover them.
  Future<void> visit(WidgetTester tester, GoRouter router, String location, {bool cover = false}) async {
    if (cover) {
      router.push(location);
    } else {
      router.go(location);
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull, reason: 'layout failed on $location');
  }

  testWidgets('the shell and every route it links to lay out on a phone', (tester) async {
    final container = await pumpPhone(tester);
    await signIn(tester);
    final router = container.read(appRouterProvider);

    for (final branch in ['/feed', '/search', '/create', '/chats', '/profile']) {
      await visit(tester, router, branch);
    }

    await visit(tester, router, '/settings');
    await visit(tester, router, '/notifications');
    await visit(tester, router, '/edit-profile');
    await visit(tester, router, '/feed/post/p_01', cover: true);
    await visit(tester, router, '/chat/u_dawit_u_selam', cover: true);
    await visit(tester, router, '/connections/u_selam/followers', cover: true);
    await visit(tester, router, '/stories/u_hiwot', cover: true);
    await visit(tester, router, '/profile/u_selam', cover: true);

    await tester.pump(const Duration(seconds: 1));
    container.dispose();
  });
}
