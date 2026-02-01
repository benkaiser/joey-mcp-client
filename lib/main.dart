import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/conversation_list_screen.dart';
import 'screens/auth_screen.dart';
import 'providers/conversation_provider.dart';
import 'services/openrouter_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch all Flutter framework errors
  FlutterError.onError = (FlutterErrorDetails details) {
    print('=== FLUTTER ERROR ===');
    print('Error: ${details.exception}');
    print('Stack trace:');
    print(details.stack);
    print('Context: ${details.context}');
    print('===================');
  };

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
        Provider(create: (_) => OpenRouterService()),
      ],
      child: MaterialApp(
        title: 'Joey MCP Client',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color.fromARGB(255, 1, 234, 255),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF0D1117),
          cardTheme: CardThemeData(
            color: const Color(0xFF161B22),
            elevation: 0,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF161B22),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: const Color(0xFF1C2128),
          ),
          snackBarTheme: const SnackBarThemeData(
            backgroundColor: Color(0xFF1C2128),
            contentTextStyle: TextStyle(color: Colors.white),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF1C2128),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF30363D)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF30363D)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF01EAFF), width: 2),
            ),
          ),
          dividerColor: const Color(0xFF30363D),
          listTileTheme: const ListTileThemeData(iconColor: Colors.white70),
        ),
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color.fromARGB(255, 1, 234, 255),
          ),
          useMaterial3: true,
        ),
        builder: (context, widget) {
          ErrorWidget.builder = (FlutterErrorDetails errorDetails) {
            print('=== ERROR WIDGET BUILDER ===');
            print('Error: ${errorDetails.exception}');
            print('Stack: ${errorDetails.stack}');
            print('==========================');
            return Scaffold(
              body: Center(child: Text('Error: ${errorDetails.exception}')),
            );
          };
          return widget!;
        },
        home: const AuthCheckScreen(),
        routes: {
          '/conversations': (context) => const ConversationListScreen(),
          '/auth': (context) => const AuthScreen(),
        },
      ),
    );
  }
}

class AuthCheckScreen extends StatelessWidget {
  const AuthCheckScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final openRouterService = Provider.of<OpenRouterService>(
      context,
      listen: false,
    );

    return FutureBuilder<bool>(
      future: openRouterService.isAuthenticated(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData && snapshot.data == true) {
          return const ConversationListScreen();
        }

        return const AuthScreen();
      },
    );
  }
}
