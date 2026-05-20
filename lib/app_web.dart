import 'package:flutter/material.dart';
import 'pages/web_simulator_page.dart';

Widget buildApp() => const WebApp();

class WebApp extends StatelessWidget {
  const WebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Retinexa',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
      ),
      home: const WebSimulatorPage(),
    );
  }
}
