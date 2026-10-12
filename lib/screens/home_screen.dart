import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';

/// The signed-in app. The tabs (Discover, My sessions, Profile) land with
/// their milestones; each one is a route under `/`.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DogPack'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthController>().signOut(),
          ),
        ],
      ),
      body: const Center(child: Text('Study sessions will show up here.')),
    );
  }
}
