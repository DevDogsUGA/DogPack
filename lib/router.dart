import 'package:go_router/go_router.dart';

import 'auth/auth_controller.dart';
import 'screens/home_screen.dart';
import 'screens/loading_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/retry_screen.dart';
import 'screens/sign_in_screen.dart';

abstract final class Routes {
  static const loading = '/loading';
  static const signIn = '/sign-in';
  static const onboarding = '/onboarding';
  static const retry = '/retry';
  static const home = '/';
}

/// The gate lives in one place: [gateRedirect] decides, from [AuthStatus]
/// alone, which route a member may be on. Every screen added later sits behind
/// `/` and inherits it.
String? gateRedirect(AuthStatus status, String location) {
  final target = switch (status) {
    AuthStatus.loading => Routes.loading,
    AuthStatus.signedOut => Routes.signIn,
    AuthStatus.needsOnboarding => Routes.onboarding,
    AuthStatus.failed => Routes.retry,
    AuthStatus.ready => null,
  };
  if (target == null) {
    // Signed in and onboarded: gate-only routes bounce to home.
    const gateRoutes = {
      Routes.loading,
      Routes.signIn,
      Routes.onboarding,
      Routes.retry,
    };
    return gateRoutes.contains(location) ? Routes.home : null;
  }
  return location == target ? null : target;
}

GoRouter buildRouter(AuthController auth) {
  return GoRouter(
    initialLocation: Routes.home,
    refreshListenable: auth,
    redirect: (context, state) => gateRedirect(auth.status, state.uri.path),
    routes: [
      GoRoute(path: Routes.home, builder: (_, __) => const HomeScreen()),
      GoRoute(path: Routes.loading, builder: (_, __) => const LoadingScreen()),
      GoRoute(path: Routes.signIn, builder: (_, __) => const SignInScreen()),
      GoRoute(
        path: Routes.onboarding,
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(path: Routes.retry, builder: (_, __) => const RetryScreen()),
    ],
  );
}
