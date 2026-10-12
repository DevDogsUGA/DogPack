import 'package:devdogsuga_sdk/devdogsuga_sdk.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../widgets/brand_mark.dart';

/// The only screen a signed-out member sees.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final launched = await context.read<AuthController>().signIn();
      if (!launched && mounted) {
        setState(() => _error = 'The sign-in page did not open. Try again.');
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Sign-in failed. Check your connection and try again.');
      }
    } finally {
      // The session arrives on the auth stream once the browser returns; until
      // then the button is usable again so a cancelled browser is not a dead end.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BrandMark(size: 96)),
                  const SizedBox(height: 24),
                  Text(
                    BrandApps.dogpack.name,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    BrandApps.dogpack.blurb,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _busy ? null : _signIn,
                    child: Text(_busy ? 'Opening...' : 'Sign in with DevDogs'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
