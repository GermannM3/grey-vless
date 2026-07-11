import 'dart:io';

import 'package:path/path.dart' as p;

/// Проверка и запрос прав администратора на Windows (нужны для TUN/WinTun).
class WindowsElevation {
  WindowsElevation._();

  static Future<bool> isElevated() async {
    if (!Platform.isWindows) return true;
    try {
      final r = await Process.run(
        'net',
        ['session'],
        runInShell: true,
      );
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Перезапускает текущий exe через UAC. При отмене UAC бросает исключение.
  static Future<void> relaunchElevated() async {
    if (!Platform.isWindows) return;
    final exe = Platform.resolvedExecutable.replaceAll("'", "''");
    final dir = p.dirname(Platform.resolvedExecutable).replaceAll("'", "''");
    final r = await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        'Start-Process -FilePath \'$exe\' -WorkingDirectory \'$dir\' -Verb RunAs',
      ],
    );
    if (r.exitCode != 0) {
      throw Exception(
        'Нужны права администратора для TUN. Подтвердите запрос UAC.',
      );
    }
    exit(0);
  }
}
