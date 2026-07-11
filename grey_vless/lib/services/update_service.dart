import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../platform/android_native.dart';

const _repo = 'GermannM3/grey-vless';
const _apiLatest = 'https://api.github.com/repos/$_repo/releases/latest';

class GreyVersion implements Comparable<GreyVersion> {
  GreyVersion(this.semver, this.build);

  final String semver;
  final int build;

  static GreyVersion? parseCurrent(String version, String buildNumber) {
    final build = int.tryParse(buildNumber) ?? 0;
    if (!_semverOk(version)) return null;
    return GreyVersion(version, build);
  }

  static GreyVersion? parseTag(String tag) {
    final m = RegExp(r'^v?(\d+\.\d+\.\d+)-build\.(\d+)$').firstMatch(tag.trim());
    if (m == null) return null;
    return GreyVersion(m.group(1)!, int.parse(m.group(2)!));
  }

  static bool _semverOk(String v) => RegExp(r'^\d+\.\d+\.\d+$').hasMatch(v);

  @override
  int compareTo(GreyVersion other) {
    final a = semver.split('.').map(int.parse).toList();
    final b = other.semver.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      final d = a[i].compareTo(b[i]);
      if (d != 0) return d;
    }
    return build.compareTo(other.build);
  }

  bool isOlderThan(GreyVersion other) => compareTo(other) < 0;

  @override
  String toString() => '$semver (build $build)';
}

class UpdateInfo {
  UpdateInfo({
    required this.latest,
    required this.tagName,
    required this.downloadUrl,
    required this.assetName,
    required this.releasePage,
  });

  final GreyVersion latest;
  final String tagName;
  final String downloadUrl;
  final String assetName;
  final String releasePage;
}

class UpdateService {
  static Future<GreyVersion> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return GreyVersion.parseCurrent(info.version, info.buildNumber) ??
        GreyVersion(info.version, 0);
  }

  static Future<UpdateInfo?> checkForUpdate() async {
    final current = await currentVersion();
    final response = await http.get(
      Uri.parse(_apiLatest),
      headers: const {'Accept': 'application/vnd.github+json', 'User-Agent': 'Grey-vless-updater'},
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final tag = data['tag_name']?.toString() ?? '';
    final latest = GreyVersion.parseTag(tag);
    if (latest == null || !current.isOlderThan(latest)) return null;

    final assetName = await _assetForPlatform();
    if (assetName == null) return null;

    final assets = data['assets'] as List<dynamic>? ?? [];
    for (final raw in assets) {
      final asset = raw as Map<String, dynamic>;
      if (asset['name']?.toString() == assetName) {
        final url = asset['browser_download_url']?.toString();
        if (url == null || url.isEmpty) return null;
        return UpdateInfo(
          latest: latest,
          tagName: tag,
          downloadUrl: url,
          assetName: assetName,
          releasePage: 'https://github.com/$_repo/releases/latest',
        );
      }
    }
    return null;
  }

  static Future<String?> _assetForPlatform() async {
    if (Platform.isAndroid) return 'Grey-vless-android.apk';
    if (Platform.isWindows) return 'Grey-vless-windows-x64.zip';
    if (Platform.isMacOS) {
      final r = await Process.run('uname', ['-m']);
      final arch = r.stdout.toString().trim();
      return arch == 'arm64' ? 'Grey-vless-macos-arm64.dmg' : 'Grey-vless-macos-x86_64.dmg';
    }
    if (Platform.isLinux) {
      if (_runningAsAppImage()) {
        return 'Grey-vless-flutter-x86_64.AppImage';
      }
      return 'Grey-vless-linux-x64.zip';
    }
    return null;
  }

  static bool _runningAsAppImage() {
    if (Platform.environment.containsKey('APPIMAGE')) return true;
    return Platform.resolvedExecutable.contains('AppImage');
  }

  static Future<String> _downloadFile(String url, String fileName, void Function(double)? onProgress) async {
    final dir = await getTemporaryDirectory();
    final dest = File(p.join(dir.path, fileName));
    if (await dest.exists()) await dest.delete();

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request).timeout(const Duration(minutes: 10));
      if (response.statusCode != 200) {
        throw Exception('Скачивание не удалось: HTTP ${response.statusCode}');
      }
      final total = response.contentLength ?? 0;
      var received = 0;
      final sink = dest.openWrite();
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      }
      await sink.close();
      return dest.path;
    } finally {
      client.close();
    }
  }

  static Future<void> downloadAndApply(UpdateInfo info, {void Function(double)? onProgress}) async {
    if (Platform.isAndroid) {
      final path = await _downloadFile(info.downloadUrl, info.assetName, onProgress);
      await AndroidNative.installApk(path);
      return;
    }

    if (Platform.isMacOS && info.assetName.endsWith('.dmg')) {
      final path = await _downloadFile(info.downloadUrl, info.assetName, onProgress);
      await Process.run('open', [path]);
      return;
    }

    if (Platform.isLinux && info.assetName.endsWith('.AppImage')) {
      final path = await _downloadFile(info.downloadUrl, info.assetName, onProgress);
      await _applyAppImageUpdate(path, info.assetName);
      return;
    }

    if ((Platform.isWindows || Platform.isLinux) && info.assetName.endsWith('.zip')) {
      final zipPath = await _downloadFile(info.downloadUrl, info.assetName, onProgress);
      await _applyZipUpdate(zipPath);
      return;
    }

    await Process.run(
      Platform.isWindows ? 'cmd' : 'xdg-open',
      Platform.isWindows ? ['/c', 'start', '', info.releasePage] : [info.releasePage],
    );
  }

  static Future<void> _applyAppImageUpdate(String downloadedPath, String assetName) async {
    final appImage = Platform.environment['APPIMAGE'];
    final targetDir = appImage != null ? p.dirname(appImage) : p.dirname(Platform.resolvedExecutable);
    final target = p.join(targetDir, assetName);
    await File(downloadedPath).copy(target);
    await Process.run('chmod', ['+x', target]);
    await Process.start(target, [], mode: ProcessStartMode.detached);
    exit(0);
  }

  static Future<void> _applyZipUpdate(String zipPath) async {
    final exe = Platform.resolvedExecutable;
    final installDir = p.dirname(exe);
    final staging = Directory(p.join((await getTemporaryDirectory()).path, 'grey-vless-update'));
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);

    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive) {
      if (file.isFile) {
        final out = File(p.join(staging.path, file.name));
        await out.parent.create(recursive: true);
        await out.writeAsBytes(file.content as List<int>);
        if (Platform.isLinux && (file.name == 'grey_vless' || file.name.endsWith('/grey_vless'))) {
          await Process.run('chmod', ['+x', out.path]);
        }
      }
    }

    if (Platform.isWindows) {
      final script = File(p.join(staging.path, '_update.bat'));
      await script.writeAsString('''
@echo off
chcp 65001 >nul
timeout /t 2 /nobreak >nul
xcopy /E /Y /I "${staging.path}\\*" "$installDir\\" >nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '$installDir' -Recurse -File | Unblock-File -ErrorAction SilentlyContinue"
start "" "$exe"
del "%~f0"
''');
      await Process.start('cmd', ['/c', script.path], mode: ProcessStartMode.detached);
    } else {
      final script = File(p.join(staging.path, '_update.sh'));
      await script.writeAsString('''
#!/bin/sh
sleep 2
cp -a "$staging.path"/. "$installDir"/
exec "$exe"
''');
      await Process.run('chmod', ['+x', script.path]);
      await Process.start('/bin/sh', [script.path], mode: ProcessStartMode.detached);
    }
    exit(0);
  }
}
