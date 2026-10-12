import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/auth_controller.dart';
import '../config.dart';
import '../widgets/brand_mark.dart';

/// Shown to a signed-in member who has not finished onboarding.
///
/// Today it holds the privacy notice and a way out. The steps themselves
/// (profile, then courses, then `complete_onboarding()`) are the Onboarding +
/// Enrollments milestone; when the last step succeeds, call
/// `AuthController.retry()` and the gate moves the member on.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to DogPack')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: BrandMark()),
              const SizedBox(height: 24),
              Text(
                'DogPack keeps your name, class year, major, the courses you '
                'enter and the sessions you host or join. You can delete all of '
                'it from the app.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              TextButton(
                key: const Key('privacy-link'),
                onPressed: () =>
                    launchUrl(privacyUrl, mode: LaunchMode.externalApplication),
                child: const Text('Read what DogPack collects'),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () => context.read<AuthController>().signOut(),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
