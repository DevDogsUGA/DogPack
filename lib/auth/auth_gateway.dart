import 'package:devdogsuga_sdk/devdogsuga_sdk.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// What the sign-in gate needs from the backend, so tests can stand in for it.
abstract interface class AuthGateway {
  /// The signed-in member's Supabase user id, restored from the device's
  /// stored session; null when signed out.
  String? get currentUserId;

  /// The member id after every change: sign-in, sign-out, an expired or
  /// revoked refresh token (null).
  Stream<String?> get userChanges;

  /// Opens the DevDogs sign-in page. The session arrives on [userChanges].
  Future<bool> signIn();

  Future<void> signOut();

  /// Whether the member finished onboarding (`profiles.onboardedAt` is set).
  Future<bool> isOnboarded(String userId);
}

/// The real gateway, on `supabase_flutter`.
///
/// `Supabase.initialize` persists the session in the device's storage and
/// restores it (refreshing the token if it has expired) before the app runs,
/// which is what lets a member stay signed in across launches.
class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this._client) : _devdogs = DevDogsAuth(_client.auth);

  final SupabaseClient _client;
  final DevDogsAuth _devdogs;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Stream<String?> get userChanges =>
      _client.auth.onAuthStateChange.map((state) => state.session?.user.id);

  @override
  Future<bool> signIn() => _devdogs.signIn(redirectTo: oauthRedirect);

  @override
  Future<void> signOut() => _devdogs.signOut();

  @override
  Future<bool> isOnboarded(String userId) async {
    final row = await _client
        .from('profiles')
        .select('onboardedAt')
        .eq('userId', userId)
        .maybeSingle();
    return row != null && row['onboardedAt'] != null;
  }
}
