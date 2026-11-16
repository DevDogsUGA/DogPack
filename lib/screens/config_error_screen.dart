import 'package:flutter/material.dart';

/// Shown instead of a crash when the app was started without its `.env`.
class ConfigErrorScreen extends StatelessWidget {
  const ConfigErrorScreen({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Configuration needed',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText(message),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
