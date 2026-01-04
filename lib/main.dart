// lib/main.dart
import 'package:flutter/material.dart';

void main() {
  runApp(const TempoApp());
}

class TempoApp extends StatelessWidget {
  const TempoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1A1A1A), // Your Charcoal
      ),
      home: const Scaffold(
        body: Center(child: Text("Tempo Ready.")),
      ),
    );
  }
}