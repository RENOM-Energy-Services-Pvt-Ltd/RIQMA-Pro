import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'dashboard_screen.dart';
import 'firebase_options.dart';
import 'providers/theme_provider.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'services/activity_log_service.dart';
import 'services/notification_service.dart';

/// Top-level background message handler (must be outside of any class)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase if not already done
  await Firebase.initializeApp();
  debugPrint('Background message received: ${message.messageId}');
}

Future<void> main() async {
  // 1. This MUST be the first line
  WidgetsFlutterBinding.ensureInitialized();
  
  // Note: AuditManager is initialized when starting an audit with a specific draftId
  // Do NOT initialize it here without a draftId

  // 2. Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 3. Register background message handler (must be before runApp)
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 4. Enable Offline Persistence with high cache capacity
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: 100 * 1024 * 1024, // 100 MB for deep offline storage
  );

  // 5. Initialize services (Moved to Splash Screen to avoid blocking UI)
  
  // 6. Run App
  runApp(
    ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  MyApp({super.key});

  // Global Navigator Key for context-free navigation if needed
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  Future<void> _initAppServices() async {
    // Parallelize initialization where possible
    await Future.wait([
      ActivityLogService.instance.init(),
      NotificationService.instance.init(),
    ]);
  }

  @override
  Widget build(BuildContext context) {

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'RiQMA Pro',
      themeMode: ThemeMode.light, // Force Light Mode
      theme: ThemeData.light(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00897B)),
      ),
      // Show Splash Screen first, then transition to AuthWrapper
      home: WindFarmSplash(
        initializationFuture: _initAppServices(),
        onComplete: () {
          // Navigate to Auth Wrapper using replacement to remove Splash from stack
          Navigator.of(navigatorKey.currentContext!).pushReplacement(
            MaterialPageRoute<void>(builder: (_) => const AuthWrapper()),
          );
        },
      ),
    );
  }
}

/// Authentication Wrapper
/// Decides whether to show Dashboard or Login based on Auth State
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // While checking auth, we could show a simple loader or continue splash visual
          // Since we already waited 4s, likely this is instant.
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return const DashboardScreen();
        }
        return const LoginScreen();
      },
    );
  }
}
