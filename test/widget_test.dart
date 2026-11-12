import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liyu_social/app/app.dart';
import 'package:liyu_social/app/bootstrap.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The whole app, booted the way `main()` boots it.
///
/// Nothing here is a fake: `bootstrap()` on mock preferences comes up on the
/// on-device backend, so the router, the redirect, the provider graph and the
/// seeded content are all the real thing. That is what makes a test like the
/// sign-in walk meaningful — it fails if the gate, the OTP hand-off or the
/// shell breaks, not if a stubbed widget changed.
void main() {
  Future<ProviderContainer> pumpApp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final result = await bootstrap();
    final container = ProviderContainer(overrides: withBootstrapResult(result.overrides, result));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LiyuApp(result: result),
      ),
    );
    await tester.pump();
    return container;
  }

  /// Puts the app down the way a real shutdown would.
  ///
  /// The store batches writes on a short timer, so the fake clock has to pass
  /// that debounce before anything is released — otherwise the test finishes
  /// with a flush still scheduled, which flutter_test reports as a leak.
  Future<void> closeApp(WidgetTester tester, ProviderContainer container) async {
    await tester.pump(const Duration(seconds: 1));
    container.dispose();
  }

  String devCode(WidgetTester tester) {
    final line = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .firstWhere((data) => data.startsWith('Local backend: your code is'));
    return line.split(' ').last;
  }

  testWidgets('a cold start waits at the sign-in gate', (tester) async {
    final container = await pumpApp(tester);

    expect(find.text('Liyu'), findsOneWidget);
    expect(find.text('Continue with phone'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await closeApp(tester, container);
  });

  testWidgets('the code the local backend minted reaches the shell', (tester) async {
    final container = await pumpApp(tester);

    await tester.tap(find.text('Continue with phone'));
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, devCode(tester));
    await tester.pump();
    await tester.tap(find.text('Verify'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Continue with phone'), findsNothing);

    await closeApp(tester, container);
  });
}
