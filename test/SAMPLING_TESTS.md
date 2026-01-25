# Sampling Request Unit Test

This test suite validates the MCP sampling request flow in Joey MCP Client Flutter, including support for multi-turn tool use loops as specified in the MCP protocol.

## Test Coverage

The test suite (`test/sampling_request_test.dart`) comprehensively tests the sampling request functionality with mocked OpenRouter endpoints.

### Tests Included

1. **Event Emission Test** - Verifies that `SamplingRequestReceived` events are emitted correctly when an MCP server sends a sampling request.

2. **Request Processing Test** - Tests that approved sampling requests are processed correctly and OpenRouter is called with the right parameters.

3. **Model Selection Test** - Validates that model hints from MCP server preferences are respected.

4. **Content Format Handling** - Tests conversion of complex multi-turn conversations from MCP format to OpenRouter format.

5. **Non-Text Content Filtering** - Ensures that non-text content types (images, audio) are properly filtered out.

6. **Finish Reason Conversion** - Verifies correct mapping between OpenRouter finish reasons and MCP stop reasons:
   - `stop` → `endTurn`
   - `length` → `maxTokens`
   - `tool_calls` → `toolUse`
   - Unknown/null → `endTurn`

7. **Request Rejection** - Tests that rejected sampling requests throw appropriate exceptions.

8. **String Content Format** - Handles both object-based and plain string content formats.

9. **Max Tokens Parameter** - Verifies that `maxTokens` is correctly passed when specified.

10. **Optional Max Tokens** - Ensures `maxTokens` is omitted when not specified.

11. **Tool Use - Initial Request** - Tests that sampling requests with tools return tool_use responses from the LLM with proper MCP formatting.

12. **Tool Use - Follow-up with Results** - Tests that follow-up requests with tool results are processed correctly and return final text responses.

## Running the Tests

```bash
flutter test test/sampling_request_test.dart
```

All 12 tests should pass, validating the complete sampling request flow including multi-turn tool loops.

## Dependencies

The tests use:
- `mockito` for mocking OpenRouter service
- `build_runner` for generating mock classes

## What's Mocked

- **OpenRouterService**: All OpenRouter API calls are mocked to avoid network requests during testing
- Responses are controlled to test different scenarios (success, different finish reasons, etc.)

## What's Real

- **ChatService**: The actual implementation is tested
- **McpClientService**: Real instance used (though network calls aren't made)
- **Message format conversion**: Real conversion logic is tested

## Key Test Patterns

### Event-Based Testing
```dart
final eventCompleter = Completer<void>();
chatService.events.listen((event) {
  if (event is SamplingRequestReceived) {
    // Test event properties
    event.onApprove(request, response);
    eventCompleter.complete();
  }
});

await eventCompleter.future;
```

### Mock Verification
```dart
verify(mockOpenRouterService.chatCompletion(
  model: 'anthropic/claude-3-5-sonnet',
  messages: argThat(containsAll([...])),
  maxTokens: 100,
)).called(1);
```

### Message Format Assertions
```dart
final captured = verify(
  mockOpenRouterService.chatCompletion(
    model: anyNamed('model'),
    messages: captureAnyNamed('messages'),
  ),
).captured.single as List<Map<String, dynamic>>;

expect(captured[0]['role'], equals('system'));
expect(captured[1]['content'], equals('Expected text'));
```

## Future Enhancements

Potential additions to the test suite:
- Streaming response tests
- Image/audio content support tests (when implemented)
- Rate limiting tests
- Concurrent sampling request handling
- Error recovery scenarios
