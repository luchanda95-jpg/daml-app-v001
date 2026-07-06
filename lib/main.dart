// main.dart
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// ✅ Screens & Services
import 'root_gate.dart';
import 'screens/onboarding_screen.dart';
import 'screens/sign_in_screen.dart';
import 'screens/sign_up_screen.dart';
import 'screens/branch/branch_home_loader.dart';
import 'screens/admin/admin.dart';
import 'package:daml/screens/client/widgets/client_dashboard.dart';
import 'theme/app_theme.dart';
import 'theme/theme_service.dart';
import 'services/supabase_daml_service.dart';
import 'services/local_storage.dart';

// ✅ New Components
import 'widgets/app_skeleton.dart';
import 'widgets/connectivity_banner.dart';
import 'providers/loading_provider.dart';

// ✅ Firebase imports
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Initialize Hive/local cache first so offline reports are always available.
  await LocalStorage.init();

  // ✅ Initialize Supabase (direct backend). If dart-defines are missing, it safely falls back.
  await SupabaseDamlService.initialize();

  // ✅ Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ✅ Register background handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  final themeService = ThemeService();
  await themeService.loadThemePreference();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeService>.value(value: themeService),
        ChangeNotifierProvider(create: (_) => LoadingProvider()),
      ],
      child: const DamlApp(),
    ),
  );
}

class DamlApp extends StatelessWidget {
  const DamlApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeService.themeMode,

      // --- UNIFIED CONNECTIVITY + LOADING LAYER ---
      builder: (context, child) {
        return ConnectivityBanner(
          child: Stack(
            children: [
              if (child != null) child,
              Consumer<LoadingProvider>(
                builder: (context, loading, _) {
                  if (!loading.isLoading) return const SizedBox.shrink();
                  return AppLoadingOverlay(message: loading.message);
                },
              ),
            ],
          ),
        );
      },

      initialRoute: '/',
      routes: {
        '/': (_) => const RootGate(),
        '/onboarding': (_) => const OnboardingScreen(),
        '/signin': (_) => const SignInScreen(),
        '/signup': (_) => const SignUpScreen(),
        '/client_home': (_) => const ClientDashboardScreen(),
        '/admin_home': (_) => const BranchHomeLoader(),
        '/overall_admin': (_) => const OverallAdminDashboard(),
      },

      onUnknownRoute: (settings) {
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text("Route Error")),
            body: Center(child: Text("Unknown route: ${settings.name}")),
          ),
        );
      },
    );
  }
}
