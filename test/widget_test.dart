// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:joey_mcp_client_flutter/main.dart';

void main() {
  testWidgets('App launches and shows conversation list', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the app shows the conversation list screen
    expect(find.text('Joey MCP Client'), findsOneWidget);
    expect(find.text('No conversations yet'), findsOneWidget);
  });
}
