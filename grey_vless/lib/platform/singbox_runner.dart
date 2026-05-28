import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'android_native.dart';

class SingboxRunner {
  Process? _process;
  String? _configPath;
  bool _androidVpn = false;

  bool get isRunning => _process != null || _androidVpn;

  Future<void> _makeExecutable(String path) async {
    if (Platform.isAndroid) {
      final ok = await AndroidNative.chmodExecutable(path);
      if (!ok) {
        throw Exception(
          'Не удалось выдать права на запуск sing-box. Переустановите приложение.',
        );
      }
      return;
    }
    if (!Platform.isWindows) {
      final result = await Process.run('chmod', ['+x', path]);
      if (result.exitCode != 0) {
        throw Exception('chmod не сработал для sing-box');
      }
    }
  }

  Future<String> _resolveBinary() async {
    final dir = await getApplicationSupportDirectory();
    final out = File(p.join(dir.path, Platform.isWindows ? 'sing-box.exe' : 'sing-box'));

    if (await out.exists()) {
      await _makeExecutable(out.path);
      return out.path;
    }

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
    await _makeExecutable(out.path);
    return out.path;
  }

  Future<void> start(Map<String, dynamic> config, {bool tunMode = false}) async {
    await stop();

    if (Platform.isAndroid && tunMode) {
      final vpnReady = await AndroidNative.prepareVpn();
      if (!vpnReady) {
        throw Exception('Нужно разрешение VPN. Подтвердите запрос системы и нажмите «Подключить» снова.');
      }
    }

    final binary = await _resolveBinary();
    final tempDir = await getTemporaryDirectory();
    _configPath = p.join(tempDir.path, 'grey-vless-${DateTime.now().millisecondsSinceEpoch}.json');
    await File(_configPath!).writeAsString(const JsonEncoder.withIndent('  ').convert(config));

    if (Platform.isAndroid && tunMode) {
      await AndroidNative.startVpn(configPath: _configPath!, binaryPath: binary);
      _androidVpn = true;
      await Future.delayed(const Duration(milliseconds: 1200));
      return;
    }

    try {
      _process = await Process.start(
        binary,
        ['run', '-c', _configPath!],
        mode: ProcessStartMode.normal,
        runInShell: false,
      );
    } on ProcessException catch (e) {
      throw Exception(
        'Не удалось запустить sing-box (${e.message}). '
        'На Android включите TUN (VPN) и подтвердите разрешение.',
      );
    }

    await Future.delayed(const Duration(milliseconds: 900));
    try {
      final code = await _process!.exitCode.timeout(const Duration(milliseconds: 50));
      final err = await _process!.stderr.transform(utf8.decoder).join();
      _process = null;
      throw Exception('sing-box завершился (код $code): ${err.trim().isEmpty ? "проверьте конфиг" : err}');
    } catch (_) {
      // still running
    }
  }

  Future<void> stop() async {
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
  }
}
