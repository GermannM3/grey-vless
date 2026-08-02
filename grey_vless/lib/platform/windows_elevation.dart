import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'windows_install.dart';

/// Нужны права администратора для TUN — UI должен показать диалог и перезапустить.
class NeedsElevationException implements Exception {
  NeedsElevationException([this.message = 'Для TUN нужны права администратора (UAC).']);
  final String message;
  @override
  String toString() => message;
}

class UacCancelledException implements Exception {
  UacCancelledException([this.message = 'UAC отменён — приложение остаётся открытым. Выберите «Системный прокси» или подтвердите UAC.']);
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

  /// Запрос UAC. Не закрывает текущее окно, пока пользователь не подтвердит.
  /// При отмене — [UacCancelledException], приложение остаётся.
  static Future<void> relaunchElevated() async {
    if (!Platform.isWindows) return;
    var exePath = Platform.resolvedExecutable;
    final install = WindowsInstall.installExe;
    if (await File(install).exists()) {
      exePath = install;
    }
    final exe = exePath.replaceAll("'", "''");
    final dir = p.dirname(exePath).replaceAll("'", "''");

    final temp = await getTemporaryDirectory();
    final marker = File(p.join(temp.path, 'grey-vless-uac-${DateTime.now().millisecondsSinceEpoch}.txt'));
    if (await marker.exists()) await marker.delete();
    final markerPath = marker.path.replaceAll("'", "''");

    // PowerShell пишет ok/cancel в marker — Flutter ждёт, UI не exit'ится сразу.
    await Process.start(
      'powershell',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-Command',
        '''
try {
  Start-Process -FilePath '$exe' -WorkingDirectory '$dir' -Verb RunAs -ErrorAction Stop
  Set-Content -LiteralPath '$markerPath' -Value 'ok' -Encoding ASCII
} catch {
  Set-Content -LiteralPath '$markerPath' -Value 'cancel' -Encoding ASCII
}
''',
      ],
      mode: ProcessStartMode.detached,
      runInShell: false,
    );

    // Ждём ответ UAC до 2 минут — окно остаётся открытым.
    for (var i = 0; i < 120; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!await marker.exists()) continue;
      final status = (await marker.readAsString()).trim();
      try {
        await marker.delete();
      } catch (_) {}
      if (status == 'ok') {
        exit(0);
      }
      throw UacCancelledException();
    }
    throw UacCancelledException('UAC не ответил — попробуйте ещё раз или включите системный прокси.');
  }
}
