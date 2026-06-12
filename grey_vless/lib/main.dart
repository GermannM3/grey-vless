import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'services/connection_service.dart';
import 'services/settings_repository.dart';
import 'state/app_state.dart';
import 'ui/app_theme.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(size: Size(420, 780), center: true, title: 'Grey vless');
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    await trayManager.setIcon('assets/icons/grey-vless.png');
    await trayManager.setToolTip('Grey vless');
  }

  final settings = SettingsRepository();
  await settings.init();
  final connection = ConnectionService();
  final state = AppState(connection, settings);
  await state.load();

  runApp(
    ChangeNotifierProvider.value(
      value: state,
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
      theme: AppTheme.dark(),
      home: const HomeScreen(),
    );
  }
}
