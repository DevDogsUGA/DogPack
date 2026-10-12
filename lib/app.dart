import 'package:devdogsuga_sdk/devdogsuga_sdk.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'auth/auth_controller.dart';
import 'router.dart';

/// The app, given an [AuthController] so tests can run it without Supabase.
class DogPackApp extends StatefulWidget {
  const DogPackApp({super.key, required this.auth});

  final AuthController auth;

  @override
  State<DogPackApp> createState() => _DogPackAppState();
}

class _DogPackAppState extends State<DogPackApp> {
  late final GoRouter _router = buildRouter(widget.auth);

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AuthController>.value(
      value: widget.auth,
      child: MaterialApp.router(
        title: 'DogPack',
        routerConfig: _router,
        theme: DevDogsTheme.light(app: BrandApps.dogpack, brandFonts: true),
        darkTheme: DevDogsTheme.dark(app: BrandApps.dogpack, brandFonts: true),
      ),
    );
  }
}
