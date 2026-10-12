import 'package:devdogsuga_sdk/devdogsuga_sdk.dart';

/// Where "Sign in with DevDogs" returns to. Registered in the Android manifest
/// and `Info.plist`, in `supabase/config.toml`, and in `devtools.config.json`.
const oauthRedirect = 'dev.dogpack://login-callback';

/// The privacy notice's DogPack section. Onboarding links here before a member
/// gives the app anything.
final Uri privacyUrl = Uri.parse('$hostsSiteProduction/legal/privacy#dogpack');

/// The app's public configuration, from `--dart-define-from-file=.env`.
///
/// Everything here ships inside the app: a secret in the `.env` ships to every
/// phone (`.env.example` is checked in CI for exactly that).
class AppConfig {
  const AppConfig(
      {required this.supabaseUrl, required this.supabasePublishableKey});

  /// Reads the defines the app was built with and throws a
  /// [MissingEnvException] naming everything that is unset.
  factory AppConfig.fromEnv(DevDogsEnv env) {
    env.requireAll(const [
      DevDogsEnvKeys.supabaseUrl,
      DevDogsEnvKeys.supabasePublishableKey,
    ]);
    return AppConfig(
      supabaseUrl: env.supabaseUrl,
      supabasePublishableKey: env.supabasePublishableKey,
    );
  }

  final String supabaseUrl;
  final String supabasePublishableKey;
}
