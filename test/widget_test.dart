// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:joey_mcp_client_flutter/main.dart';

void main() {
  testWidgets('App launches and shows auth screen when not authenticated', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());
    // Wait for the auth check FutureBuilder to resolve.
    await tester.pumpAndSettle();

    // In a test environment SharedPreferences has no stored API key,
    // so the app should show the authentication screen.
    expect(find.text('Welcome to Joey'), findsOneWidget);
  });
}
