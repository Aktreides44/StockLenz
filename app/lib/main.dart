import 'package:flutter/material.dart';

import 'screener_page.dart';

void main() {
  runApp(const StockLensApp());
}

class StockLensApp extends StatefulWidget {
  const StockLensApp({super.key});

  @override
  State<StockLensApp> createState() => _StockLensAppState();
}

class _StockLensAppState extends State<StockLensApp> {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeData _theme(Brightness brightness) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF26A69A), brightness: brightness),
      visualDensity: VisualDensity.compact,
    );
  }

  void _toggleTheme(Brightness current) {
    setState(() => _themeMode = current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StockLens',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: _themeMode,
      home: ScreenerPage(onToggleTheme: _toggleTheme),
    );
  }
}
