# Integration Tests

This directory contains integration tests for the Joey MCP Client Flutter app.

## Running Integration Tests

All tests run in the Flutter test environment.

### Quick Start - Run All Tests
```bash
# Run all tests together using main.dart (recommended)
flutter test integration_test/main.dart -d macos

# Or run each test file separately
flutter test integration_test/chat_integration_test.dart -d macos
flutter test integration_test/mcp_integration_test.dart -d macos
```

**Note:** The `main.dart` file runs all test suites in sequence. When prompted to select a device, choose option **[1]: macOS** or **[2]: Chrome**. The tests run without showing a visible window.

### Run with Specific Platform
```bash
# Run on macOS (headless)
flutter test integration_test/main.dart -d macos

# Run on Chrome (headless)
flutter test integration_test/main.dart -d chrome
```

### Run with Options
```bash
# Verbose output
flutter test integration_test/main.dart --verbose

# With coverage
flutter test integration_test/main.dart --coverage

# Specific test name pattern
flutter test integration_test/main.dart --plain-name "Should use MCP"
```

## Test Structure

### chat_integration_test.dart
Tests the chat interface functionality with a mocked OpenRouter service:
- Creating conversations and sending messages
- Message ordering and display
- Empty message handling
- Loading states
- Text field clearing after sending
- Auto-scrolling to new messages

**Note:** These tests do not include MCP server integration. They focus on the core chat UI and OpenRouter interaction.

### mcp_integration_test.dart
Tests MCP server integration functionality:
- Using MCP server tools in chat
- Aggregating tools from multiple MCP servers
- Routing tool calls to the correct server
- Handling sampling requests from MCP servers
- Error handling for tool execution
- Managing servers with overlapping tool names

**Features tested:**
- Mock MCP clients with configurable tools
- Multi-server orchestration
- Sampling request flow
- Tool call history tracking

## Mocking

### MockOpenRouterService (chat_integration_test.dart)
Extends the real `OpenRouterService` and provides:
- Configurable mock responses
- Response delay simulation
- Error simulation
- Call history tracking

### MockMcpClientService (mcp_integration_test.dart)
Extends the real `McpClientService` and provides:
- Configurable tool definitions
- Tool response mocking
- Sampling request simulation
- Tool call history tracking
- Error injection for testing

### MockOpenRouterServiceForMcp (mcp_integration_test.dart)
A specialized mock that:
- Simulates tool calling behavior
- Controls when to stop calling tools
- Tracks call counts to prevent infinite loops

This allows testing the chat interface without requiring actual API calls, network connectivity, or running MCP servers.

## Writing New Tests

When adding new integration tests:

1. Create a new test file in `integration_test/`
2. Use `IntegrationTestWidgetsFlutterBinding.ensureInitialized()` at the start
3. Mock external dependencies (like OpenRouterService, McpClientService)
4. Clean up test data in `setUp()` and `tearDown()`
5. Use descriptive test names
6. Test both happy paths and error cases

Example:
```dart
testWidgets('Should handle network errors gracefully', (WidgetTester tester) async {
  mockOpenRouterService.shouldThrowError = true;
  mockOpenRouterService.errorMessage = 'Network error';

  // ... test code
});
```

## Test Results

### chat_integration_test.dart
✅ 6/6 tests passing
- Should create a conversation and send a message
- Should persist user messages in chat
- Should handle empty messages gracefully
- Should display loading indicator during response
- Should clear text field after sending message
- Should auto-scroll when messages are added

### mcp_integration_test.dart
✅ 6/6 tests passing
- Should use MCP server tool in chat
- Should aggregate tools from multiple MCP servers
- Should route tool calls to correct MCP server
- Should handle sampling requests from MCP server
- Should handle tool execution errors gracefully
- Should handle multiple servers with overlapping tool names

**Total: 12/12 tests passing (100%)**

