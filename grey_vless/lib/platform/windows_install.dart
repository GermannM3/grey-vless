import 'dart:io';

import 'package:path/path.dart' as p;

/// Жёсткая установка Windows-клиента в LocalAppData + снятие MotW.
///
/// Без этого после reboot SmartScreen/App Control часто не даёт стартовать
/// exe прямо из Downloads.
class WindowsInstall {
  WindowsInstall._();

  static const appUserModelId = 'GermannM3.GreyVless';
  static const folderName = 'Grey-vless';
  static const exeName = 'grey_vless.exe';

  static String get installDir =>
      p.join(Platform.environment['LOCALAPPDATA'] ?? '', 'Programs', folderName);

  static String get installExe => p.join(installDir, exeName);

  static bool get isInstalledPath {
    if (!Platform.isWindows) return true;
    final exe = Platform.resolvedExecutable;
    final normExe = p.normalize(exe).toLowerCase();
    final normInstall = p.normalize(installExe).toLowerCase();
    return normExe == normInstall;
  }

  static bool get looksLikeDownloads {
    final exe = Platform.resolvedExecutable.toLowerCase();
    return exe.contains('\\downloads\\') || exe.contains('\\temp\\');
  }

  /// Если запуск не из installDir — копирует туда, Unblock, ярлык, relaunch.
  /// Возвращает true, если текущий процесс должен завершиться.
  static Future<bool> ensureInstalledAndRelaunch() async {
    if (!Platform.isWindows) return false;
    if (isInstalledPath) {
      await unblockTree(installDir);
      return false;
    }

    final sourceDir = p.dirname(Platform.resolvedExecutable);
    await _copyTree(sourceDir, installDir);
    await unblockTree(installDir);
    await _writeLauncherCmd();
    await _createStartMenuShortcut();
    await Process.start(
      installExe,
      const [],
      workingDirectory: installDir,
      mode: ProcessStartMode.detached,
    );
    return true;
  }

  /// Стартовый safety-net: снять MotW даже если уже установлены.
  static Future<void> unblockTree(String dir) async {
    if (!Platform.isWindows || dir.isEmpty) return;
    final escaped = dir.replaceAll("'", "''");
    await Process.run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      '''
\$ErrorActionPreference = 'SilentlyContinue'
Get-ChildItem -LiteralPath '$escaped' -Recurse -File | ForEach-Object {
  Unblock-File -LiteralPath \$_.FullName
  \$z = \$_.FullName + ':Zone.Identifier'
  if (Test-Path -LiteralPath \$z) { Remove-Item -LiteralPath \$z -Force }
}
''',
    ]);
  }

  static Future<void> _copyTree(String from, String to) async {
    await Directory(to).create(recursive: true);
    final escapedFrom = from.replaceAll("'", "''");
    final escapedTo = to.replaceAll("'", "''");
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      "Copy-Item -LiteralPath '$escapedFrom\\*' -Destination '$escapedTo' -Recurse -Force",
    ]);
    if (r.exitCode != 0) {
      throw Exception('Не удалось установить в $to: ${r.stderr}');
    }
  }

  static Future<void> _writeLauncherCmd() async {
    final cmd = File(p.join(installDir, 'Запуск.cmd'));
    await cmd.writeAsString('''
@echo off
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0' -Recurse -File | Unblock-File -ErrorAction SilentlyContinue"
start "" "%~dp0$exeName"
''');
  }

  static Future<void> _createStartMenuShortcut() async {
    final startMenu = p.join(
      Platform.environment['APPDATA'] ?? '',
      'Microsoft',
      'Windows',
      'Start Menu',
      'Programs',
    );
    final lnk = p.join(startMenu, 'Grey vless.lnk');
    final target = installExe.replaceAll("'", "''");
    final workDir = installDir.replaceAll("'", "''");
    final lnkEsc = lnk.replaceAll("'", "''");
    final launcher = p.join(installDir, 'Запуск.cmd').replaceAll("'", "''");
    await Process.run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      '''
\$ErrorActionPreference = 'Stop'
\$Wsh = New-Object -ComObject WScript.Shell
\$Sc = \$Wsh.CreateShortcut('$lnkEsc')
\$Sc.TargetPath = '$launcher'
\$Sc.WorkingDirectory = '$workDir'
\$Sc.Description = 'Grey vless'
\$Sc.IconLocation = '$target'
\$Sc.Save()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject(\$Wsh) | Out-Null
Unblock-File -LiteralPath '$lnkEsc' -ErrorAction SilentlyContinue
\$z = '$lnkEsc' + ':Zone.Identifier'
if (Test-Path -LiteralPath \$z) { Remove-Item -LiteralPath \$z -Force }
try {
  \$shell = New-Object -ComObject Shell.Application
  \$folder = \$shell.NameSpace((Split-Path -Parent '$lnkEsc'))
  \$item = \$folder.ParseName((Split-Path -Leaf '$lnkEsc'))
  if (\$item -ne \$null) {
    \$item.ExtendedProperty('System.AppUserModel.ID') | Out-Null
  }
} catch {}
''',
    ]);
  }
}
