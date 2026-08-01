import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/tunnel_mode.dart';
import '../services/singbox_config.dart';
import 'android_native.dart';
import 'windows_elevation.dart';

class SingboxRunner {
  Process? _process;
  String? _configPath;
  String? _logPath;
  bool _androidVpn = false;
  bool _androidProxy = false;
  bool _alive = false;
  int _startGen = 0;
  final List<StreamSubscription> _logSubs = [];

  bool get isRunning => _androidVpn || _androidProxy || (_process != null && _alive);

  Future<bool> _portOpen() async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        '127.0.0.1',
        SingboxConfigBuilder.localPort,
        timeout: const Duration(milliseconds: 400),
      ).timeout(const Duration(milliseconds: 600));
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  Future<void> _ensureWintun(String singboxPath) async {
    if (!Platform.isWindows) return;
    final dir = p.dirname(singboxPath);
    final dest = File(p.join(dir, 'wintun.dll'));
    if (await dest.exists()) return;
    try {
      final data = await rootBundle.load('assets/bin/wintun.dll');
      await dest.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    } catch (e) {
      throw Exception(
        'Не удалось извлечь wintun.dll (нужен для TUN на Windows): $e',
      );
    }
  }

  Future<String> _resolveBinary() async {
    if (Platform.isAndroid) {
      return AndroidNative.prepareSingboxBinary('');
    }

    final dir = await getApplicationSupportDirectory();
    final out = File(p.join(dir.path, Platform.isWindows ? 'sing-box.exe' : 'sing-box'));
    final marker = File(p.join(dir.path, 'sing-box.version'));
    final info = await PackageInfo.fromPlatform();
    final want = '${info.version}+${info.buildNumber}';
    final have = await marker.exists() ? (await marker.readAsString()).trim() : '';
    final needExtract = !await out.exists() || have != want;

    if (needExtract) {
      final String asset;
      if (Platform.isWindows) {
        asset = 'assets/bin/sing-box-windows-amd64.exe';
      } else if (Platform.isMacOS) {
        final uname = await Process.run('uname', ['-m']);
        final arch = (uname.stdout as String).trim();
        asset = arch == 'arm64' ? 'assets/bin/sing-box-darwin-arm64' : 'assets/bin/sing-box-darwin-amd64';
      } else {
        asset = 'assets/bin/sing-box-linux-amd64';
      }

      final data = await rootBundle.load(asset);
      await out.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      await marker.writeAsString(want, flush: true);
    }

    if (Platform.isWindows) {
      await _ensureWintun(out.path);
    } else {
      final result = await Process.run('chmod', ['+x', out.path]);
      if (result.exitCode != 0) {
        throw Exception('chmod не сработал для sing-box');
      }
    }
    return out.path;
  }

  /// Если порт 7890 уже слушает — убиваем зомби sing-box.
  Future<void> _freeLocalPort() async {
    if (!await _portOpen()) return;
    await _killOrphanSingbox();
    await Future.delayed(const Duration(milliseconds: 400));
    if (await _portOpen()) {
      await Future.delayed(const Duration(milliseconds: 800));
    }
  }

  Future<void> _killOrphanSingbox() async {
    try {
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/F', '/IM', 'sing-box.exe'], runInShell: true)
            .timeout(const Duration(seconds: 3));
      } else if (Platform.isLinux || Platform.isMacOS) {
        await Process.run('pkill', ['-f', 'sing-box']).timeout(const Duration(seconds: 3));
      }
    } catch (_) {}
  }

  Future<String> _readLogTail() async {
    if (_logPath == null) return '';
    final file = File(_logPath!);
    if (!await file.exists()) return '';
    final content = await file.readAsString();
    if (content.length <= 900) return content;
    return content.substring(content.length - 900);
  }

  String _tunFailureHint(String log, {required bool tunMode}) {
    if (!tunMode) return '';
    final lower = log.toLowerCase();
    if (Platform.isWindows &&
        (lower.contains('access is denied') ||
            lower.contains('wintun') ||
            lower.contains('error creating interface') ||
            lower.contains('configure tun'))) {
      return '. TUN на Windows нужен запуск от имени администратора (UAC) и wintun.dll рядом с sing-box.';
    }
    if (lower.contains('operation not permitted')) {
      return '. TUN нужны права: sudo setcap cap_net_admin+ep на sing-box';
    }
    return '';
  }

  Future<void> start(
    Map<String, dynamic> config, {
    bool tunMode = false,
    TunnelMode tunnelMode = TunnelMode.fullVpn,
    List<String> tunnelAppIds = const [],
  }) async {
    // Elevation: не блокируем UI на UAC — бросаем NeedsElevationException для диалога.
    if (Platform.isWindows && tunMode) {
      if (!await WindowsElevation.isElevated()) {
        throw NeedsElevationException();
      }
    }

    await stop();
    await _freeLocalPort();

    if (tunnelMode.needsAppList && tunnelAppIds.isEmpty) {
      throw Exception(
        tunnelMode == TunnelMode.selectedApps
            ? 'Выберите хотя бы одно приложение для прохождения через VLESS.'
            : 'Выберите приложения, которые должны идти мимо VPN.',
      );
    }

    if (Platform.isAndroid && tunMode) {
      if (!await AndroidNative.isHevAvailable()) {
        throw Exception(
          'TUN недоступен на этом телефоне. Выберите «Системный прокси» в настройках туннеля.',
        );
      }
      final vpnReady = await AndroidNative.prepareVpn();
      if (!vpnReady) {
        throw Exception('Нужно разрешение VPN. Подтвердите запрос системы и нажмите «Подключить» снова.');
      }
      // Battery-исключение НЕ запрашиваем здесь — системный диалог рвёт connect и выглядит как зависание.
    }

    final binary = await _resolveBinary();
    final tempDir = await getTemporaryDirectory();
    _configPath = p.join(tempDir.path, 'grey-vless-${DateTime.now().millisecondsSinceEpoch}.json');
    _logPath = p.join(tempDir.path, 'grey-vless-${DateTime.now().millisecondsSinceEpoch}.log');
    await File(_configPath!).writeAsString(const JsonEncoder.withIndent('  ').convert(config));

    var binaryPath = binary;
    var configPath = _configPath!;

    if (Platform.isAndroid) {
      configPath = await AndroidNative.prepareSingboxConfig(_configPath!);
      _configPath = configPath;
      final check = await AndroidNative.singboxCheck(binaryPath: binaryPath, configPath: configPath);
      if (check.exitCode != 0) {
        throw Exception(
          'Конфиг sing-box невалиден: ${check.output.isEmpty ? "проверьте сервер" : check.output}',
        );
      }
    } else {
      final check = await Process.run(binary, ['check', '-c', configPath])
          .timeout(const Duration(seconds: 8));
      if (check.exitCode != 0) {
        final err = '${check.stderr}${check.stdout}'.trim();
        throw Exception('Конфиг sing-box невалиден: ${err.isEmpty ? "проверьте сервер" : err}');
      }
    }

    if (Platform.isAndroid && tunMode) {
      final allowed = tunnelMode == TunnelMode.selectedApps ? tunnelAppIds : <String>[];
      final disallowed = tunnelMode == TunnelMode.bypassApps ? tunnelAppIds : <String>[];
      await AndroidNative.startVpn(
        configPath: configPath,
        binaryPath: binaryPath,
        proxyPort: SingboxConfigBuilder.localPort,
        allowedApps: allowed,
        disallowedApps: disallowed,
      );
      // Сервис стартует асинхронно — ждём порт до ~15 с (не socket.close — зависает на OEM).
      var sawVpn = false;
      for (var i = 0; i < 60; i++) {
        await Future.delayed(const Duration(milliseconds: 250));
        if (await _portOpen()) {
          _androidVpn = true;
          return;
        }
        if (await AndroidNative.isVpnActive()) sawVpn = true;
        // VPN так и не поднялся за ~5с.
        if (i >= 20 && !sawVpn) break;
      }
      if (!await _portOpen()) {
        await stop();
        throw Exception(
          sawVpn
              ? 'VPN-интерфейс есть, но прокси 127.0.0.1:${SingboxConfigBuilder.localPort} молчит. Переустановите APK из последнего релиза.'
              : 'VPN не поднялся. Разрешите VPN в системе и убедитесь, что другой VPN выключен.',
        );
      }
      _androidVpn = true;
      return;
    }

    if (Platform.isAndroid) {
      await AndroidNative.singboxStart(binaryPath: binaryPath, configPath: configPath);
      _androidProxy = true;
      for (var i = 0; i < 40; i++) {
        await Future.delayed(const Duration(milliseconds: 150));
        if (!await AndroidNative.singboxIsRunning()) {
          final log = await AndroidNative.singboxLastLog();
          throw Exception(
            log.isEmpty ? 'sing-box завершился на Android' : log,
          );
        }
        if (await _portOpen()) {
          _alive = true;
          return;
        }
      }
      final log = await AndroidNative.singboxLastLog();
      await stop();
      throw Exception(
        log.isEmpty
            ? 'Порт 127.0.0.1:${SingboxConfigBuilder.localPort} не открылся. sing-box не слушает прокси.'
            : log,
      );
    }

    try {
      _process = await Process.start(
        binary,
        ['run', '-c', configPath],
        mode: ProcessStartMode.normal,
        runInShell: false,
        workingDirectory: p.dirname(binary),
      );
    } on ProcessException catch (e) {
      throw Exception('Не удалось запустить sing-box (${e.message})');
    }

    final gen = ++_startGen;
    final logFile = File(_logPath!);
    final proc = _process!;
    _logSubs.add(proc.stderr.listen((data) {
      try {
        logFile.writeAsBytesSync(data, mode: FileMode.append, flush: true);
      } catch (_) {}
    }));
    _logSubs.add(proc.stdout.listen((data) {
      try {
        logFile.writeAsBytesSync(data, mode: FileMode.append, flush: true);
      } catch (_) {}
    }));
    proc.exitCode.then((_) {
      if (_startGen == gen) _alive = false;
    });

    for (var i = 0; i < 40; i++) {
      await Future.delayed(const Duration(milliseconds: 150));
      try {
        await proc.exitCode.timeout(const Duration(milliseconds: 1));
        final log = await _readLogTail();
        if (_startGen == gen) {
          _process = null;
          _alive = false;
        }
        var msg = 'sing-box завершился';
        msg += _tunFailureHint(log, tunMode: tunMode);
        if (log.isNotEmpty) msg += ': $log';
        throw Exception(msg);
      } on TimeoutException {
        // still running
      }
      if (await _portOpen()) {
        _alive = true;
        return;
      }
    }

    final log = await _readLogTail();
    await stop();
    throw Exception(
      'Порт 127.0.0.1:${SingboxConfigBuilder.localPort} не открылся. '
      '${log.isEmpty ? "sing-box не слушает прокси." : log}'
      '${_tunFailureHint(log, tunMode: tunMode)}',
    );
  }

  Future<void> stop() async {
    _alive = false;
    _startGen++;
    for (final s in _logSubs) {
      await s.cancel();
    }
    _logSubs.clear();

    if (_androidProxy) {
      await AndroidNative.singboxStop();
      _androidProxy = false;
    }
    if (_androidVpn) {
      await AndroidNative.stopVpn();
      _androidVpn = false;
    }

    final proc = _process;
    _process = null;
    if (proc != null) {
      try {
        proc.kill(ProcessSignal.sigterm);
      } catch (_) {}
      try {
        await proc.exitCode.timeout(const Duration(seconds: 3));
      } catch (_) {
        try {
          proc.kill(ProcessSignal.sigkill);
        } catch (_) {}
      }
    }
    if (_configPath != null) {
      try {
        final file = File(_configPath!);
        if (await file.exists()) await file.delete();
      } catch (_) {}
      _configPath = null;
    }
    if (_logPath != null) {
      try {
        final file = File(_logPath!);
        if (await file.exists()) await file.delete();
      } catch (_) {}
      _logPath = null;
    }
  }
}
