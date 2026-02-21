// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:joey_mcp_client_flutter/main.dart';

void main() {
  testWidgets('App launches and shows auth screen when not authenticated', (WidgetTester tester) async {
    // Set up SharedPreferences with no API key for test environment.
    SharedPreferences.setMockInitialValues({});

    // Save the original ErrorWidget.builder so we can restore it after the
    // test (MyApp's MaterialApp builder overrides it, which the test
    // framework treats as a violation if left changed).
    final originalErrorWidgetBuilder = ErrorWidget.builder;

    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());
    // Pump frames to let the FutureBuilder resolve (pumpAndSettle can't be
    // used here because the loading state shows a CircularProgressIndicator
    // whose infinite animation prevents settling).
    await tester.pump(const Duration(seconds: 1));

    // In a test environment SharedPreferences has no stored API key,
    // so the app should show the authentication screen.
    expect(find.text('Welcome to Joey'), findsOneWidget);

    // Restore ErrorWidget.builder to avoid test framework assertion.
    ErrorWidget.builder = originalErrorWidgetBuilder;
  });
}
