// lib/root_gate.dart
// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/auth_service.dart';
import 'widgets/logo_loader.dart';

// ✅ FCM imports
import 'package:firebase_messaging/firebase_messaging.dart';

class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  bool _navigated = false;
  String _status = "Initializing...";

  // ✅ keep a reference so we can cancel if needed (optional)
  static bool _fcmSetupDone = false;

  @override
  void initState() {
    super.initState();
    _setupFcm(); // ✅ start FCM setup early (non-blocking)
    _boot();
  }

  Future<void> _setupFcm() async {
    // Avoid setting up listeners multiple times if RootGate rebuilds
    if (_fcmSetupDone) return;
    _fcmSetupDone = true;

    try {
      // Android 13+ permission prompt is handled by OS; this call is safe.
      await FirebaseMessaging.instance.requestPermission();

      final token = await FirebaseMessaging.instance.getToken();
      if (kDebugMode) debugPrint("✅ FCM TOKEN: $token");

      // Foreground messages (app open)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final title = message.notification?.title ?? "(no title)";
        final body = message.notification?.body ?? "(no body)";
        if (kDebugMode) debugPrint("📩 FCM onMessage: $title | $body");
      });

      // When user taps a notification to open the app
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        final title = message.notification?.title ?? "(no title)";
        if (kDebugMode) debugPrint("👉 FCM onMessageOpenedApp: $title");
        // You can navigate somewhere specific here later if you want.
      });
    } catch (e) {
      if (kDebugMode) debugPrint("⚠️ FCM setup error: $e");
    }
  }

  Future<void> _boot() async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    try {
      setState(() => _status = "Checking onboarding...");

      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final seenOnboarding = prefs.getBool('seenOnboarding') ?? false;
      if (!seenOnboarding) {
        _go('/onboarding');
        return;
      }

      setState(() => _status = "Checking authentication...");

      await AuthService.syncTokenToApiService();

      bool signedIn = false;
      for (int i = 0; i < 3; i++) {
        await prefs.reload();
        signedIn = await AuthService.isSignedIn();
        if (signedIn) break;
        await Future.delayed(const Duration(milliseconds: 150));
      }

      if (!signedIn) {
        _go('/signin');
        return;
      }

      setState(() => _status = "Loading dashboard...");

      String role = 'client';
      for (int i = 0; i < 3; i++) {
        await prefs.reload();
        final r = await AuthService.getRole();
        if (r != null && r.trim().isNotEmpty) {
          role = r.trim();
          break;
        }
        await Future.delayed(const Duration(milliseconds: 120));
      }

      final route = _routeForRole(role);

      if (kDebugMode) {
        debugPrint("[RootGate] signedIn=$signedIn role=$role -> $route");
        await AuthService.debugAuthState();
      }

      _go(route);
    } catch (e) {
      if (kDebugMode) debugPrint("[RootGate] boot error: $e");
      await AuthService.signOut();
      _go('/signin');
    }
  }

  void _go(String route) {
    if (_navigated || !mounted) return;
    _navigated = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(route);
    });
  }

  String _routeForRole(String role) {
    final r = role.toLowerCase().trim();

    if (r == 'ovadmin' ||
        r == 'overall_admin' ||
        r.contains('overall') ||
        r.contains('ovadmin')) {
      return '/overall_admin';
    }
    if (r == 'branch_admin' || r.contains('branch')) {
      return '/admin_home';
    }
    return '/client_home';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: LogoLoader(message: _status),
      ),
    );
  }
}
