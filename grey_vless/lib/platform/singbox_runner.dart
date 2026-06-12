import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/singbox_config.dart';
import 'android_native.dart';

class SingboxRunner {
  Process? _process;
  String? _configPath;
  String? _logPath;
  bool _androidVpn = false;
  bool _androidProxy = false;
  bool _alive = false;

  bool get isRunning => _androidVpn || _androidProxy || (_process != null && _alive);

  Future<bool> _portOpen() async {
    try {
      final socket = await Socket.connect('127.0.0.1', SingboxConfigBuilder.localPort,
          timeout: const Duration(milliseconds: 400));
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> _resolveBinary() async {
    final dir = await getApplicationSupportDirectory();
    final out = File(p.join(dir.path, Platform.isWindows ? 'sing-box.exe' : 'sing-box'));

    if (!await out.exists()) {
      final String asset;
      if (Platform.isAndroid) {
        asset = 'assets/bin/sing-box-android-arm64';
      } else if (Platform.isWindows) {
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
    }

    if (Platform.isAndroid) {
      return AndroidNative.prepareSingboxBinary(out.path);
    }

    if (!Platform.isWindows) {
      final result = await Process.run('chmod', ['+x', out.path]);
      if (result.exitCode != 0) {
        throw Exception('chmod не сработал для sing-box');
      }
    }
    return out.path;
  }

  Future<String> _readLogTail() async {
    if (_logPath == null) return '';
    final file = File(_logPath!);
    if (!await file.exists()) return '';
    final content = await file.readAsString();
    if (content.length <= 900) return content;
    return content.substring(content.length - 900);
  }

  Future<void> start(Map<String, dynamic> config, {bool tunMode = false}) async {
    await stop();

    if (Platform.isAndroid && tunMode) {
      if (!await AndroidNative.isHevAvailable()) {
        throw Exception(
          'TUN недоступен на этом телефоне. Отключите переключатель TUN — подключение через прокси всё равно работает.',
        );
      }
      final vpnReady = await AndroidNative.prepareVpn();
      if (!vpnReady) {
        throw Exception('Нужно разрешение VPN. Подтвердите запрос системы и нажмите «Подключить» снова.');
      }
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
      final check = await Process.run(binary, ['check', '-c', configPath]);
      if (check.exitCode != 0) {
        final err = '${check.stderr}${check.stdout}'.trim();
        throw Exception('Конфиг sing-box невалиден: ${err.isEmpty ? "проверьте сервер" : err}');
      }
    }

    if (Platform.isAndroid && tunMode) {
      await AndroidNative.startVpn(
        configPath: configPath,
        binaryPath: binaryPath,
        proxyPort: SingboxConfigBuilder.localPort,
      );
      _androidVpn = true;
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!await _portOpen()) {
        throw Exception('VPN запущен, но прокси 127.0.0.1:${SingboxConfigBuilder.localPort} недоступен');
      }
      return;
    }

    if (Platform.isAndroid) {
      await AndroidNative.singboxStart(binaryPath: binaryPath, configPath: configPath);
      _androidProxy = true;
      for (var i = 0; i < 25; i++) {
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
      );
    } on ProcessException catch (e) {
      throw Exception('Не удалось запустить sing-box (${e.message})');
    }

    final logFile = File(_logPath!);
    final proc = _process!;
    proc.stderr.listen((data) => logFile.writeAsBytesSync(data, mode: FileMode.append, flush: true));
    proc.stdout.listen((data) => logFile.writeAsBytesSync(data, mode: FileMode.append, flush: true));
    proc.exitCode.then((_) => _alive = false);

    for (var i = 0; i < 25; i++) {
      await Future.delayed(const Duration(milliseconds: 150));
      try {
        await proc.exitCode.timeout(const Duration(milliseconds: 1));
        final log = await _readLogTail();
        _process = null;
        _alive = false;
        var msg = 'sing-box завершился';
        if (tunMode && log.toLowerCase().contains('operation not permitted')) {
          msg += '. TUN нужны права: sudo setcap cap_net_admin+ep на sing-box';
        }
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
      '${log.isEmpty ? "sing-box не слушает прокси." : log}',
    );
  }

  Future<void> stop() async {
    _alive = false;
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
      proc.kill(ProcessSignal.sigterm);
      try {
        await proc.exitCode.timeout(const Duration(seconds: 3));
      } catch (_) {
        proc.kill(ProcessSignal.sigkill);
      }
    }
    if (_configPath != null) {
      final file = File(_configPath!);
      if (await file.exists()) await file.delete();
      _configPath = null;
    }
    if (_logPath != null) {
      final file = File(_logPath!);
      if (await file.exists()) await file.delete();
      _logPath = null;
    }
  }
}
