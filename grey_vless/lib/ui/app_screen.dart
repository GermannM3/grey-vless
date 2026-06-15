import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Обёртка экрана: на Linux прозрачный Scaffold даёт чёрный прямоугольник.
class AppScreen extends StatelessWidget {
  const AppScreen({super.key, required this.body, this.safeArea = true});

  final Widget body;
  final bool safeArea;

  @override
  Widget build(BuildContext context) {
    final content = safeArea ? SafeArea(child: body) : body;
    return Scaffold(
      backgroundColor: AppTheme.bgBottom,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: AppTheme.screenGradient,
        foregroundDecoration: null,
        child: content,
      ),
    );
  }
}
