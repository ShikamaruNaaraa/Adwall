import 'package:flutter/material.dart';
import 'flavors.dart';
import 'screens/admin_home_screen.dart';
import 'screens/tv_home_screen.dart';

class AdWallApp extends StatelessWidget {
  const AdWallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: F.title,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: F.appFlavor == Flavor.admin
          ? const AdminHomeScreen()
          : const TvHomeScreen(),
    );
  }
}
