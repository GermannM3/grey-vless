import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'android_native.dart';

class InstalledApp {
  InstalledApp({
    required this.id,
    required this.name,
    this.isSystem = false,
  });

  /// Android: packageName. Desktop: имя процесса (telegram.exe) или путь к exe.
  final String id;
  final String name;
  final bool isSystem;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'isSystem': isSystem};

  factory InstalledApp.fromJson(Map<String, dynamic> j) => InstalledApp(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        isSystem: j['isSystem'] == true,
      );
}

class InstalledApps {
  /// Список приложений из ОС для UI выбора per-app туннеля.
  static Future<List<InstalledApp>> list() async {
    if (Platform.isAndroid) {
      final raw = await AndroidNative.listInstalledApps();
      return raw
          .map(
            (e) => InstalledApp(
              id: e['package']?.toString() ?? '',
              name: e['label']?.toString() ?? '',
              isSystem: e['system'] == true,
            ),
          )
          .where((a) => a.id.isNotEmpty && a.name.isNotEmpty)
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }

    if (Platform.isWindows) {
      return _listWindows();
    }

    if (Platform.isLinux) {
      return _listLinux();
    }

    if (Platform.isMacOS) {
      return _listMac();
    }

    return [];
  }

  /// Нормализация id → process_name / process_path для sing-box.
  static ({List<String> names, List<String> paths}) matchersFromIds(List<String> ids) {
    final names = <String>{};
    final paths = <String>{};
    for (var raw in ids) {
      var s = raw.trim().replaceAll('"', '');
      if (s.isEmpty) continue;
      // DisplayIcon часто: C:\...\app.exe,0
      final m = RegExp(r'^(.*\.exe)\s*,\s*\d+$', caseSensitive: false).firstMatch(s);
      if (m != null) s = m.group(1)!;
      if (s.toLowerCase().endsWith('.exe')) {
        final base = p.basename(s);
        names.add(base);
        if (s.contains(r'\') || s.contains('/')) {
          paths.add(p.normalize(s));
        }
      } else if (Platform.isAndroid || s.contains('.')) {
        // package name — не process
        continue;
      } else {
        names.add(Platform.isWindows && !s.toLowerCase().endsWith('.exe') ? '$s.exe' : s);
      }
    }
    // Свои процессы всегда исключаем из «через прокси» косвенно — caller добавит.
    names.removeWhere((n) {
      final l = n.toLowerCase();
      return l == 'grey_vless.exe' || l == 'sing-box.exe' || l == 'singbox.exe';
    });
    return (names: names.toList()..sort(), paths: paths.toList()..sort());
  }

  static Future<List<InstalledApp>> _listWindows() async {
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      r'''
$ErrorActionPreference = 'SilentlyContinue'
$seen = @{}
$apps = New-Object System.Collections.Generic.List[object]
function Add-App($name, $exePath) {
  if (-not $exePath) { return }
  $exePath = $exePath.Trim().Trim('"')
  if ($exePath -match '^(.*\.exe)\s*,\s*\d+$') { $exePath = $Matches[1] }
  if (-not ($exePath -like '*.exe')) { return }
  if (-not (Test-Path -LiteralPath $exePath)) { return }
  $proc = [IO.Path]::GetFileName($exePath)
  if ($seen.ContainsKey($proc.ToLowerInvariant())) { return }
  $seen[$proc.ToLowerInvariant()] = $true
  if (-not $name) { $name = [IO.Path]::GetFileNameWithoutExtension($proc) }
  $apps.Add([PSCustomObject]@{ id = $proc; name = [string]$name; path = $exePath })
}
$shell = New-Object -ComObject WScript.Shell
$startDirs = @(
  "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
  "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
)
foreach ($dir in $startDirs) {
  if (-not (Test-Path $dir)) { continue }
  Get-ChildItem -LiteralPath $dir -Recurse -Filter *.lnk -ErrorAction SilentlyContinue | ForEach-Object {
    try {
      $sc = $shell.CreateShortcut($_.FullName)
      $label = [IO.Path]::GetFileNameWithoutExtension($_.Name)
      Add-App $label $sc.TargetPath
    } catch {}
  }
}
$keys = @(
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
foreach ($k in $keys) {
  Get-ItemProperty $k -ErrorAction SilentlyContinue | ForEach-Object {
    Add-App $_.DisplayName $_.DisplayIcon
  }
}
# Часто используемые процессы, если ярлыка нет
Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.MainWindowTitle } | ForEach-Object {
  Add-App $_.ProcessName $_.Path
}
$apps | Sort-Object name | ConvertTo-Json -Compress
''',
    ]);
    if (r.exitCode != 0) return [];
    final out = r.stdout.toString().trim();
    if (out.isEmpty || out == 'null') return [];
    try {
      final dynamic decoded = jsonDecode(out);
      final list = decoded is List ? decoded : [decoded];
      return list
          .whereType<Map>()
          .map(
            (e) => InstalledApp(
              id: e['id']?.toString() ?? '',
              name: e['name']?.toString() ?? '',
            ),
          )
          .where((a) => a.id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<InstalledApp>> _listLinux() async {
    final dirs = [
      '/usr/share/applications',
      '${Platform.environment['HOME']}/.local/share/applications',
    ];
    final result = <InstalledApp>[];
    final seen = <String>{};
    for (final dir in dirs) {
      final d = Directory(dir);
      if (!await d.exists()) continue;
      await for (final ent in d.list()) {
        if (ent is! File || !ent.path.endsWith('.desktop')) continue;
        try {
          final lines = await ent.readAsLines();
          var name = '';
          var exec = '';
          var noDisplay = false;
          for (final line in lines) {
            if (line.startsWith('Name=') && name.isEmpty) {
              name = line.substring(5).trim();
            }
            if (line.startsWith('Exec=') && exec.isEmpty) {
              exec = line.substring(5).trim().split(RegExp(r'\s+')).first;
            }
            if (line.startsWith('NoDisplay=true')) noDisplay = true;
          }
          if (noDisplay || name.isEmpty || exec.isEmpty) continue;
          final id = p.basename(exec);
          if (!seen.add(id)) continue;
          result.add(InstalledApp(id: id, name: name));
        } catch (_) {}
      }
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  static Future<List<InstalledApp>> _listMac() async {
    final dir = Directory('/Applications');
    if (!await dir.exists()) return [];
    final result = <InstalledApp>[];
    await for (final ent in dir.list()) {
      if (ent is Directory && ent.path.endsWith('.app')) {
        final name =
            ent.uri.pathSegments.where((s) => s.isNotEmpty).last.replaceAll('.app', '');
        // process_name macOS обычно без .app — имя бинарника в Contents/MacOS
        result.add(InstalledApp(id: name, name: name));
      }
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }
}
