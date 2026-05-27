import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'services/connection_service.dart';
import 'state/app_state.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(size: Size(820, 620), center: true, title: 'Grey vless');
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    await trayManager.setIcon('assets/icons/grey-vless.png');
    await trayManager.setToolTip('Grey vless');
  }

  final connection = ConnectionService();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(connection),
      child: const GreyVlessApp(),
    ),
  );
}

class GreyVlessApp extends StatelessWidget {
  const GreyVlessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Grey vless',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6B7280), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
