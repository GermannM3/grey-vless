import 'dart:convert';
import 'dart:io';

import 'android_native.dart';

class InstalledApp {
  InstalledApp({
    required this.id,
    required this.name,
    this.isSystem = false,
  });

  /// packageName (Android) или путь/ключ (desktop).
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

  static Future<List<InstalledApp>> _listWindows() async {
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      r'''
$ErrorActionPreference = 'SilentlyContinue'
$apps = @()
$keys = @(
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
foreach ($k in $keys) {
  Get-ItemProperty $k | ForEach-Object {
    $n = $_.DisplayName
    $id = $_.DisplayIcon
    if (-not $id) { $id = $_.InstallLocation }
    if (-not $id) { $id = $_.PSChildName }
    if ($n -and $id) {
      $apps += [PSCustomObject]@{ id = [string]$id; name = [string]$n }
    }
  }
}
$apps | Sort-Object name -Unique | ConvertTo-Json -Compress
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
    for (final dir in dirs) {
      final d = Directory(dir);
      if (!await d.exists()) continue;
      await for (final ent in d.list()) {
        if (ent is! File || !ent.path.endsWith('.desktop')) continue;
        try {
          final lines = await ent.readAsLines();
          var name = '';
          var noDisplay = false;
          for (final line in lines) {
            if (line.startsWith('Name=') && name.isEmpty) {
              name = line.substring(5).trim();
            }
            if (line.startsWith('NoDisplay=true')) noDisplay = true;
          }
          if (!noDisplay && name.isNotEmpty) {
            result.add(InstalledApp(id: ent.path, name: name));
          }
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
        result.add(InstalledApp(id: ent.path, name: name));
      }
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }
}
