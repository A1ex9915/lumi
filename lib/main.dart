import 'package:flutter/material.dart';

import 'api_service.dart';
import 'screens/chat_screen.dart';
import 'screens/login_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.instance.init();
  runApp(const ChatbotApp());
}

class ChatbotApp extends StatelessWidget {
  const ChatbotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumi',
      debugShowCheckedModeBanner: false,
      theme: lumiTheme(Brightness.light),
      darkTheme: lumiTheme(Brightness.dark),
      // Cambia de pantalla automáticamente al iniciar o cerrar sesión
      home: ListenableBuilder(
        listenable: ApiService.instance,
        builder: (context, _) => ApiService.instance.isLoggedIn ? const ChatScreen() : const LoginScreen(),
      ),
    );
  }
}
