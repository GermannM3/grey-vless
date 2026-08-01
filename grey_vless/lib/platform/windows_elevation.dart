import 'dart:io';

import 'package:path/path.dart' as p;

import 'windows_install.dart';

/// Нужны права администратора для TUN — UI должен показать диалог и перезапустить.
class NeedsElevationException implements Exception {
  NeedsElevationException([this.message = 'Для TUN нужны права администратора (UAC).']);
  final String message;
  @override
  String toString() => message;
}

/// Проверка и запрос прав администратора на Windows (нужны для TUN/WinTun).
class WindowsElevation {
  WindowsElevation._();

  static Future<bool> isElevated() async {
    if (!Platform.isWindows) return true;
    try {
      // Быстрая проверка без зависаний: whoami /groups содержит S-1-16-12288 (High).
      final r = await Process.run(
        'whoami',
        ['/groups'],
        runInShell: true,
      ).timeout(const Duration(seconds: 3));
      final out = '${r.stdout}'.toLowerCase();
      return out.contains('s-1-16-12288') || out.contains('high mandatory');
    } catch (_) {
      try {
        final r = await Process.run('net', ['session'], runInShell: true)
            .timeout(const Duration(seconds: 2));
        return r.exitCode == 0;
      } catch (_) {
        return false;
      }
    }
  }

  /// Запускает UAC **не блокируя** UI: Process.start + сразу выход.
  /// Если пользователь отменит UAC — новое окно не появится (нужно нажать Подключить снова).
  static Future<void> relaunchElevated() async {
    if (!Platform.isWindows) return;
    var exePath = Platform.resolvedExecutable;
    final install = WindowsInstall.installExe;
    if (await File(install).exists()) {
      exePath = install;
    }
    final exe = exePath.replaceAll("'", "''");
    final dir = p.dirname(exePath).replaceAll("'", "''");

    // НЕ Process.run: он ждёт закрытия UAC/процесса → UI «зависает».
    await Process.start(
      'powershell',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-Command',
        'Start-Process -FilePath \'$exe\' -WorkingDirectory \'$dir\' -Verb RunAs',
      ],
      mode: ProcessStartMode.detached,
      runInShell: false,
    );
    // Даём powershell стартовать, затем выходим — UAC покажется поверх.
    await Future.delayed(const Duration(milliseconds: 200));
    exit(0);
  }
}
