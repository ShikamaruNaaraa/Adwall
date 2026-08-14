// Basic smoke test for the Admin flavor's home screen.
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adwall/screens/admin_home_screen.dart';

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8000');
  });

  testWidgets('Admin home screen shows the Add TV button', (tester) async {

    await tester.pumpWidget(
      const MaterialApp(home: AdminHomeScreen()),
    );

    expect(find.text('Add TV'), findsOneWidget);
    expect(find.text('TV nickname'), findsOneWidget);
  });
}
