import 'package:devdogsuga_sdk/devdogsuga_sdk.dart';
import 'package:dogpack/config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('missing defines are named together, with the way to fix it', () {
    expect(
      () => AppConfig.fromEnv(DevDogsEnv.fromMap(const {})),
      throwsA(
        isA<MissingEnvException>().having(
          (e) => e.toString(),
          'message',
          allOf(contains('SUPABASE_URL'), contains('SUPABASE_PUBLISHABLE_KEY'),
              contains('devtools')),
        ),
      ),
    );
  });

  test('both values present builds the config', () {
    final config = AppConfig.fromEnv(
      DevDogsEnv.fromMap(const {
        'SUPABASE_URL': 'http://127.0.0.1:54321',
        'SUPABASE_PUBLISHABLE_KEY': 'sb_publishable_x',
      }),
    );
    expect(config.supabaseUrl, 'http://127.0.0.1:54321');
  });
}
