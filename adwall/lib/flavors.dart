enum Flavor { admin, tv }

/// Holds the flavor the app was launched with. Set once in main_admin.dart
/// or main_tv.dart before runApp() is called.
class F {
  static Flavor appFlavor = Flavor.admin;

  static String get title {
    switch (appFlavor) {
      case Flavor.admin:
        return 'AdWall Admin';
      case Flavor.tv:
        return 'AdWall TV';
    }
  }

  static String get name => appFlavor.name;
}
