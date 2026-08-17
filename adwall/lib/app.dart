import 'package:flutter/material.dart';
import 'flavors.dart';
import 'screens/admin_login_screen.dart';
import 'screens/admin_home_screen.dart';
import 'screens/tv_home_screen.dart';
import 'services/pairing_service.dart';

class AdWallApp extends StatelessWidget {
  const AdWallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: F.title,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: F.appFlavor == Flavor.admin
          ? const _AdminEntryPoint()
          : const TvHomeScreen(),
    );
  }
}

/// Skips the login screen if an admin is already logged in (saved locally
/// after a successful login), so the admin doesn't have to log in every
/// time they open the app.
class _AdminEntryPoint extends StatelessWidget {
  const _AdminEntryPoint();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: PairingService().getLoggedInAdmin(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data != null
            ? const AdminHomeScreen()
            : const AdminLoginScreen();
      },
    );
  }
}
