import 'package:devdogsuga_sdk/devdogsuga_sdk.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'auth/auth_controller.dart';
import 'auth/auth_gateway.dart';
import 'config.dart';
import 'screens/config_error_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final env = DevDogsEnv.fromDefines();
  final AppConfig config;
  try {
    config = AppConfig.fromEnv(env);
  } on MissingEnvException catch (e) {
    runApp(MaterialApp(home: ConfigErrorScreen(message: e.toString())));
    return;
  }

  // Sentry is off unless SENTRY_DSN is set (it is empty in a local .env).
  await initTelemetry(
    dsn: env.sentryDsn,
    environment: env.environment,
    service: 'dogpack',
    appRunner: () async {
      // Restores the stored session (and refreshes it if it has expired)
      // before the first frame, so a returning member never sees sign-in.
      await Supabase.initialize(
        url: config.supabaseUrl,
        publishableKey: config.supabasePublishableKey,
        postgrestOptions: const PostgrestClientOptions(schema: 'dogpack'),
      );
      runApp(
        DogPackApp(
          auth: AuthController(SupabaseAuthGateway(Supabase.instance.client)),
        ),
      );
    },
  );
}
