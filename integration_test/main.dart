import 'package:integration_test/integration_test.dart';
import 'chat_integration_test.dart' as chat;
import 'mcp_integration_test.dart' as mcp;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Run chat integration tests
  chat.main();

  // Run MCP integration tests
  mcp.main();
}
