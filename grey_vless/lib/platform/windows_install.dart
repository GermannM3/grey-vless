import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Единственный «правильный» путь Windows-клиента: LocalAppData.
///
/// Конфликты при обновлении обычно из‑за:
/// - копии в Downloads + копии в Programs;
/// - xcopy поверх запущенного grey_vless.exe / dll.
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

  /// Убивает экземпляры только из installDir (не трогает текущий процесс из Downloads).
  static Future<void> killInstallDirInstances() async {
    if (!Platform.isWindows) return;
    final target = installDir.replaceAll("'", "''");
    await Process.run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      '''
\$target = '$target'
Get-CimInstance Win32_Process -Filter "Name='grey_vless.exe' OR Name='sing-box.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
  \$path = \$_.ExecutablePath
  if (\$path -and \$path.StartsWith(\$target, [StringComparison]::OrdinalIgnoreCase)) {
    Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue
  }
}
''',
    ]);
    await Future.delayed(const Duration(milliseconds: 400));
  }

  /// Убивает все экземпляры клиента и ядра (только из внешнего updater-скрипта).
  static Future<void> killRunningInstances() async {
    if (!Platform.isWindows) return;
    for (final name in ['grey_vless.exe', 'sing-box.exe']) {
      try {
        await Process.run('taskkill', ['/F', '/IM', name, '/T'], runInShell: true);
      } catch (_) {}
    }
    await Future.delayed(const Duration(milliseconds: 600));
  }

  /// Если запуск не из installDir — ставит/обновляет туда и перезапускает.
  /// Возвращает true, если текущий процесс должен завершиться.
  static Future<bool> ensureInstalledAndRelaunch() async {
    if (!Platform.isWindows) return false;
    if (isInstalledPath) {
      // Не блокируем старт полным Unblock — только быстро и в фоне.
      unawaited(unblockTree(installDir));
      return false;
    }

    final sourceDir = p.dirname(Platform.resolvedExecutable);
    await killInstallDirInstances();
    await _copyTree(sourceDir, installDir);
    await unblockTree(installDir);
    await _writeLauncherCmd();
    await _createStartMenuShortcut();
    await _removeStaleDownloadsPins();

    await Process.start(
      installExe,
      const [],
      workingDirectory: installDir,
      mode: ProcessStartMode.detached,
    );
    return true;
  }

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
    // Robocopy: /E все подпапки, /IS /IT перезапись, /R:2 повторы при lock.
    final r = await Process.run('robocopy', [
      escapedFrom,
      escapedTo,
      '/E',
      '/IS',
      '/IT',
      '/R:3',
      '/W:1',
      '/NFL',
      '/NDL',
      '/NJH',
      '/NJS',
      '/NP',
      '/XF',
      '_update.bat',
      '_update.ps1',
      '_update.sh',
    ]);
    // Robocopy: 0–7 = успех, >=8 ошибка.
    if (r.exitCode >= 8) {
      // Fallback Copy-Item
      final c = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        "Copy-Item -LiteralPath '$escapedFrom\\*' -Destination '$escapedTo' -Recurse -Force",
      ]);
      if (c.exitCode != 0) {
        throw Exception('Не удалось обновить файлы в $to: ${c.stderr}');
      }
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
    final aumid = appUserModelId;
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
# AppUserModelID через PropertyStore — один ярлык = одна иконка на панели
try {
  \$code = @'
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
public class LnkAumid {
  [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IPropertyStore {
    void GetCount(out uint cProps);
    void GetAt(uint iProp, out PROPERTYKEY pkey);
    void GetValue(ref PROPERTYKEY key, out PROPVARIANT pv);
    void SetValue(ref PROPERTYKEY key, ref PROPVARIANT pv);
    void Commit();
  }
  [StructLayout(LayoutKind.Sequential, Pack = 4)]
  struct PROPERTYKEY { public Guid fmtid; public uint pid; }
  [StructLayout(LayoutKind.Sequential)]
  struct PROPVARIANT {
    public ushort vt; public ushort w1, w2, w3;
    public IntPtr p;
  }
  [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
  static extern void SHGetPropertyStoreFromParsingName(string pszPath, IntPtr pbc, uint flags, ref Guid riid, out IPropertyStore ppv);
  public static void Set(string lnk, string aumid) {
    var iid = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
    IPropertyStore store;
    SHGetPropertyStoreFromParsingName(lnk, IntPtr.Zero, 2 /*GPS_READWRITE*/, ref iid, out store);
    var key = new PROPERTYKEY { fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), pid = 5 };
    var pv = new PROPVARIANT();
    pv.vt = 31; // VT_LPWSTR
    pv.p = Marshal.StringToCoTaskMemUni(aumid);
    store.SetValue(ref key, ref pv);
    store.Commit();
    Marshal.FreeCoTaskMem(pv.p);
  }
}
'@
  Add-Type -TypeDefinition \$code -ErrorAction SilentlyContinue
  [LnkAumid]::Set('$lnkEsc', '$aumid')
} catch {}
''',
    ]);
  }

  /// Убирает старые ярлыки на Downloads из закрепов/рабочего стола по возможности.
  static Future<void> _removeStaleDownloadsPins() async {
    final desktop = p.join(Platform.environment['USERPROFILE'] ?? '', 'Desktop');
    for (final name in ['Grey vless.lnk', 'grey_vless.lnk', 'Grey-vless.lnk']) {
      for (final dir in [
        desktop,
        p.join(Platform.environment['APPDATA'] ?? '', 'Microsoft', 'Internet Explorer', 'Quick Launch', 'User Pinned', 'TaskBar'),
      ]) {
        final f = File(p.join(dir, name));
        if (await f.exists()) {
          try {
            // Не удаляем taskbar pin слепо — только если target в Downloads.
            final r = await Process.run('powershell', [
              '-NoProfile',
              '-Command',
              '''
\$s = (New-Object -ComObject WScript.Shell).CreateShortcut('${f.path.replaceAll("'", "''")}')
\$t = [string]\$s.TargetPath
if (\$t -match 'Downloads|\\\\Temp\\\\') { Remove-Item -LiteralPath '${f.path.replaceAll("'", "''")}' -Force }
''',
            ]);
            // ignore result
            // ignore: unnecessary_statements
            r;
          } catch (_) {}
        }
      }
    }
  }
}
