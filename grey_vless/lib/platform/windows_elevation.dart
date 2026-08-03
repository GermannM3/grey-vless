import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/app_log.dart';
import 'windows_install.dart';

/// Нужны права администратора для TUN — UI должен показать диалог и перезапустить.
class NeedsElevationException implements Exception {
  NeedsElevationException([this.message = 'Для TUN нужны права администратора (UAC).']);
  final String message;
  @override
  String toString() => message;
}

class UacCancelledException implements Exception {
  UacCancelledException([
    this.message =
        'UAC отменён или окно не появилось. Запусти «Grey vless (Админ)» из меню Пуск '
        'или в настройках нажми «Перезапустить от администратора». '
        'Либо оставь «Системный прокси» — он без UAC.',
  ]);
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

  /// Путь к постоянному лаунчеру с UAC (ставится установщиком / при первом elevate).
  static String get adminLauncherCmd {
    final dir = Directory(WindowsInstall.installDir).existsSync()
        ? WindowsInstall.installDir
        : p.dirname(Platform.resolvedExecutable);
    return p.join(dir, 'Запуск_админ.cmd');
  }

  /// Пишет Запуск_админ.cmd рядом с exe.
  static Future<void> ensureAdminLauncher() async {
    if (!Platform.isWindows) return;
    var dir = WindowsInstall.installDir;
    if (!await Directory(dir).exists()) {
      dir = p.dirname(Platform.resolvedExecutable);
    }
    await Directory(dir).create(recursive: true);
    final exeName = WindowsInstall.exeName;
    final cmd = File(p.join(dir, 'Запуск_админ.cmd'));
    await cmd.writeAsString(
      '@echo off\r\n'
      'chcp 65001 >nul\r\n'
      'cd /d "%~dp0"\r\n'
      'echo Запрос UAC для TUN...\r\n'
      'powershell -NoProfile -ExecutionPolicy Bypass -Command '
      '"Start-Process -FilePath \'%~dp0$exeName\' -WorkingDirectory \'%~dp0\' -Verb RunAs"\r\n'
      'if errorlevel 1 pause\r\n',
    );
  }

  /// Запрос UAC через видимый cmd (не Hidden powershell — иначе UAC часто «не видно»).
  static Future<void> relaunchElevated() async {
    if (!Platform.isWindows) return;

    await ensureAdminLauncher();

    var exePath = Platform.resolvedExecutable;
    final install = WindowsInstall.installExe;
    if (await File(install).exists()) {
      exePath = install;
    }
    if (!await File(exePath).exists()) {
      AppLog.instance.error('uac', 'exe не найден: $exePath');
      throw UacCancelledException('Не найден grey_vless.exe для запуска от админа.');
    }

    final dir = p.dirname(exePath);
    final temp = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final marker = File(p.join(temp.path, 'grey-uac-$stamp.txt'));
    final bat = File(p.join(temp.path, 'grey-uac-$stamp.bat'));
    if (await marker.exists()) await marker.delete();

    // Экранирование для bat: пути в кавычках.
    await bat.writeAsString(
      '@echo off\r\n'
      'chcp 65001 >nul\r\n'
      'echo Grey vless — запрос прав администратора (UAC)\r\n'
      'echo Если окно UAC не видно — посмотри на панели задач (щит).\r\n'
      'powershell -NoProfile -ExecutionPolicy Bypass -Command ^\r\n'
      '  "try { Start-Process -FilePath \'${exePath.replaceAll("'", "''")}\' '
      '-WorkingDirectory \'${dir.replaceAll("'", "''")}\' -Verb RunAs -ErrorAction Stop; '
      'Set-Content -LiteralPath \'${marker.path.replaceAll("'", "''")}\' -Value ok -Encoding ASCII } '
      'catch { Set-Content -LiteralPath \'${marker.path.replaceAll("'", "''")}\' -Value cancel -Encoding ASCII }"\r\n',
    );

    AppLog.instance.info('uac', 'запуск UAC для $exePath');

    // start "" = пустой TITLE. Без этого Windows ищет exe с именем заголовка.
    await Process.start(
      'cmd.exe',
      ['/c', 'start', '""', '/wait', bat.path],
      mode: ProcessStartMode.detached,
      workingDirectory: dir,
    );

    // Ждём marker (UAC + start). /wait на bat держит, пока powershell не закончит.
    for (var i = 0; i < 180; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!await marker.exists()) continue;
      final status = (await marker.readAsString()).trim().toLowerCase();
      try {
        await marker.delete();
      } catch (_) {}
      try {
        await bat.delete();
      } catch (_) {}

      if (status == 'ok') {
        AppLog.instance.info('uac', 'UAC OK — закрываем обычное окно');
        // Дать elevated процессу отрисоваться.
        await Future<void>.delayed(const Duration(milliseconds: 800));
        exit(0);
      }
      AppLog.instance.warn('uac', 'UAC cancel/fail');
      throw UacCancelledException();
    }
    AppLog.instance.warn('uac', 'timeout waiting for UAC');
    throw UacCancelledException();
  }
}
