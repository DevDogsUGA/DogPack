import 'dart:async';

import 'package:dogpack/auth/auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_gateway.dart';

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('a stored session of an onboarded member goes straight to ready',
      () async {
    final auth = AuthController(FakeGateway(userId: 'u1', onboarded: true));
    expect(auth.status, AuthStatus.loading);
    await settle();
    expect(auth.status, AuthStatus.ready);
  });

  test('no stored session is signed out, with no profile read', () {
    final auth = AuthController(FakeGateway());
    expect(auth.status, AuthStatus.signedOut);
  });

  test('a signed-in member who has not onboarded needs onboarding', () async {
    final auth = AuthController(FakeGateway(userId: 'u1'));
    await settle();
    expect(auth.status, AuthStatus.needsOnboarding);
  });

  test(
      'signing in through the browser moves the gate; signing out moves it back',
      () async {
    final gateway = FakeGateway(onboarded: true);
    final auth = AuthController(gateway);
    gateway.completeSignIn('u1');
    await settle();
    expect(auth.status, AuthStatus.ready);
    await auth.signOut();
    await settle();
    expect(auth.status, AuthStatus.signedOut);
  });

  test(
      'an unreadable profile is failed, and retry recovers without a new sign-in',
      () async {
    final gateway = FakeGateway(userId: 'u1', onboarded: true)
      ..failProfile = true;
    final auth = AuthController(gateway);
    await settle();
    expect(auth.status, AuthStatus.failed);
    gateway.failProfile = false;
    await auth.retry();
    expect(auth.status, AuthStatus.ready);
  });

  test('a slow profile read cannot sign a member back in after sign-out',
      () async {
    final gateway = FakeGateway(userId: 'u1')..profileGate = Completer<bool>();
    final auth = AuthController(gateway);
    await auth.signOut();
    await settle();
    gateway.profileGate!.complete(true);
    await settle();
    expect(auth.status, AuthStatus.signedOut);
  });

  test('a token refresh for the same member does not reload the profile',
      () async {
    final gateway = FakeGateway(userId: 'u1', onboarded: true);
    final auth = AuthController(gateway);
    await settle();
    var notified = 0;
    auth.addListener(() => notified++);
    gateway.completeSignIn('u1');
    await settle();
    expect(notified, 0);
    expect(auth.status, AuthStatus.ready);
  });
}
