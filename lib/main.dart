import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/conversation_list_screen.dart';
import 'providers/conversation_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ConversationProvider()..initialize(),
        ),
      ],
      child: MaterialApp(
        title: 'Joey MCP Client',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color.fromARGB(255, 1, 234, 255)),
          useMaterial3: true,
        ),
        home: const ConversationListScreen(),
      ),
    );
  }
}
