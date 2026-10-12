import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../widgets/brand_mark.dart';

/// Signed in, but the profile could not be read. The session is kept, so this
/// is a retry and not a sign-in.
class RetryScreen extends StatelessWidget {
  const RetryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(),
              const SizedBox(height: 24),
              const Text("DogPack couldn't reach the server."),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: auth.retry, child: const Text('Try again')),
              TextButton(
                  onPressed: auth.signOut, child: const Text('Sign out')),
            ],
          ),
        ),
      ),
    );
  }
}
