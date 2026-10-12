import 'dart:async';

import 'package:dogpack/auth/auth_gateway.dart';

/// A gateway that signs in and out without a backend.
class FakeGateway implements AuthGateway {
  FakeGateway({String? userId, this.onboarded = false}) : _userId = userId;

  final _changes = StreamController<String?>.broadcast();
  String? _userId;
  bool onboarded;
  bool failProfile = false;
  Completer<bool>? profileGate;
  int signInCalls = 0;

  @override
  String? get currentUserId => _userId;

  @override
  Stream<String?> get userChanges => _changes.stream;

  /// What the browser flow does when it completes.
  void completeSignIn(String id) {
    _userId = id;
    _changes.add(id);
  }

  @override
  Future<bool> signIn() async {
    signInCalls++;
    return true;
  }

  @override
  Future<void> signOut() async {
    _userId = null;
    _changes.add(null);
  }

  @override
  Future<bool> isOnboarded(String userId) async {
    if (failProfile) throw StateError('offline');
    final gate = profileGate;
    if (gate != null) return gate.future;
    return onboarded;
  }
}
