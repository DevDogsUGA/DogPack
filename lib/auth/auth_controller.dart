import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_gateway.dart';

/// Where the member stands relative to the gate.
enum AuthStatus {
  /// Restoring the stored session or reading the profile.
  loading,
  signedOut,

  /// Signed in, but has not finished onboarding.
  needsOnboarding,

  /// Signed in and onboarded: the app proper.
  ready,

  /// Signed in, but the profile could not be read (offline, backend down).
  /// The session is kept; [AuthController.retry] tries again.
  failed,
}

/// The sign-in gate's state, for `provider` and for the router's
/// `refreshListenable`.
class AuthController extends ChangeNotifier {
  AuthController(this._gateway) {
    _subscription = _gateway.userChanges.listen(_onUser);
    _onUser(_gateway.currentUserId);
  }

  final AuthGateway _gateway;
  late final StreamSubscription<String?> _subscription;
  AuthStatus _status = AuthStatus.loading;
  String? _userId;
  // Bumped on every user change so a slow profile read for a member who has
  // since signed out cannot put the app back in a signed-in state.
  int _generation = 0;

  AuthStatus get status => _status;
  String? get userId => _userId;

  Future<bool> signIn() => _gateway.signIn();

  Future<void> signOut() async {
    await _gateway.signOut();
  }

  /// Re-reads the profile after [AuthStatus.failed], and after onboarding
  /// finishes.
  Future<void> retry() => _resolve(_userId);

  Future<void> _onUser(String? userId) async {
    // The same member again (a token refresh) changes nothing.
    if (userId != null && userId == _userId && _status != AuthStatus.loading) {
      return;
    }
    _userId = userId;
    await _resolve(userId);
  }

  Future<void> _resolve(String? userId) async {
    final generation = ++_generation;
    if (userId == null) {
      _set(AuthStatus.signedOut);
      return;
    }
    _set(AuthStatus.loading);
    try {
      final onboarded = await _gateway.isOnboarded(userId);
      if (generation != _generation) return;
      _set(onboarded ? AuthStatus.ready : AuthStatus.needsOnboarding);
    } catch (_) {
      if (generation != _generation) return;
      _set(AuthStatus.failed);
    }
  }

  void _set(AuthStatus status) {
    if (_status == status) return;
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
