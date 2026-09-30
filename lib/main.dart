import 'package:flutter/material.dart';

import 'screens/home_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FamilyHomeManagerApp());
}

class FamilyHomeManagerApp extends StatelessWidget {
  const FamilyHomeManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '家庭管理',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
      ),
      home: const HomeShell(),
    );
  }
}
