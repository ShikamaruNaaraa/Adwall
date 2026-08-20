import 'package:flutter/material.dart';

/// Shows a floating, pill-shaped message bar at the bottom of the screen,
/// styled like a rounded "toast" rather than the default rectangular
/// [SnackBar]. Use this everywhere a SnackBar would previously have been
/// shown.
void showPillMessage(
  BuildContext context,
  String message, {
  bool isError = false,
  Duration duration = const Duration(seconds: 3),
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        textAlign: TextAlign.center,
      ),
      backgroundColor: isError ? Colors.red.shade600 : Colors.grey.shade900,
      behavior: SnackBarBehavior.floating,
      duration: duration,
      shape: const StadiumBorder(),
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    ),
  );
}
