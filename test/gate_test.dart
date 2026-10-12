import 'package:dogpack/app.dart';
import 'package:dogpack/auth/auth_controller.dart';
import 'package:dogpack/config.dart';
import 'package:dogpack/router.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:devdogsuga_sdk/devdogsuga_sdk.dart';

import 'support/fake_gateway.dart';

Future<void> pumpApp(WidgetTester tester, FakeGateway gateway) async {
  await tester.pumpWidget(DogPackApp(auth: AuthController(gateway)));
  await tester.pumpAndSettle();
}

void main() {
  group('gateRedirect', () {
    test('every status maps to exactly one route', () {
      expect(gateRedirect(AuthStatus.loading, '/'), Routes.loading);
      expect(gateRedirect(AuthStatus.signedOut, '/'), Routes.signIn);
      expect(gateRedirect(AuthStatus.needsOnboarding, '/'), Routes.onboarding);
      expect(gateRedirect(AuthStatus.failed, '/'), Routes.retry);
      expect(gateRedirect(AuthStatus.ready, '/'), isNull);
    });

    test('a signed-out member cannot reach any other route', () {
      expect(gateRedirect(AuthStatus.signedOut, '/anything'), Routes.signIn);
      expect(gateRedirect(AuthStatus.signedOut, Routes.signIn), isNull);
    });

    test('a ready member is bounced off the gate routes', () {
      expect(gateRedirect(AuthStatus.ready, Routes.signIn), Routes.home);
      expect(gateRedirect(AuthStatus.ready, Routes.onboarding), Routes.home);
    });
  });

  testWidgets('signed out shows the brand and Sign in with DevDogs',
      (tester) async {
    final gateway = FakeGateway();
    await pumpApp(tester, gateway);
    expect(find.text('Sign in with DevDogs'), findsOneWidget);
    expect(find.text(BrandApps.dogpack.name), findsOneWidget);
    await tester.tap(find.text('Sign in with DevDogs'));
    await tester.pumpAndSettle();
    expect(gateway.signInCalls, 1);
  });

  testWidgets('a stored session skips sign-in and lands on home',
      (tester) async {
    await pumpApp(tester, FakeGateway(userId: 'u1', onboarded: true));
    expect(find.text('Sign in with DevDogs'), findsNothing);
    expect(find.text('Study sessions will show up here.'), findsOneWidget);
  });

  testWidgets(
      'a new member lands on onboarding, which links to the privacy notice',
      (tester) async {
    await pumpApp(tester, FakeGateway(userId: 'u1'));
    expect(find.text('Welcome to DogPack'), findsOneWidget);
    expect(find.byKey(const Key('privacy-link')), findsOneWidget);
    expect(
        privacyUrl.toString(), 'https://devdogsuga.org/legal/privacy#dogpack');
  });

  testWidgets('signing out from home returns to sign-in', (tester) async {
    await pumpApp(tester, FakeGateway(userId: 'u1', onboarded: true));
    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with DevDogs'), findsOneWidget);
  });

  testWidgets('an unreachable profile shows retry, not sign-in',
      (tester) async {
    final gateway = FakeGateway(userId: 'u1', onboarded: true)
      ..failProfile = true;
    await pumpApp(tester, gateway);
    expect(find.text('Try again'), findsOneWidget);
    gateway.failProfile = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Study sessions will show up here.'), findsOneWidget);
  });
}
