import 'package:flutter/material.dart';

import 'screener_page.dart';
import 'theme.dart';

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

  void _toggleTheme(Brightness current) {
    setState(() => _themeMode = current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StockLens',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: _themeMode,
      home: ScreenerPage(onToggleTheme: _toggleTheme),
    );
  }
}
