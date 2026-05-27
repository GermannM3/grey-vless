import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SingboxRunner {
  Process? _process;
  String? _configPath;

  bool get isRunning => _process != null;

  Future<String> _resolveBinary() async {
    if (Platform.isAndroid) {
      final dir = await getApplicationSupportDirectory();
      final out = File(p.join(dir.path, 'sing-box'));
      if (!await out.exists()) {
        final data = await rootBundle.load('assets/bin/sing-box-android-arm64');
        await out.writeAsBytes(data.buffer.asUint8List(), flush: true);
        await Process.run('chmod', ['+x', out.path]);
      }
      return out.path;
    }

    final dir = await getApplicationSupportDirectory();
    String asset;
    String name;
    if (Platform.isWindows) {
      asset = 'assets/bin/sing-box-windows-amd64.exe';
      name = 'sing-box.exe';
    } else if (Platform.isMacOS) {
      final uname = await Process.run('uname', ['-m']);
      final arch = (uname.stdout as String).trim();
      final isArm = arch == 'arm64';
      asset = isArm ? 'assets/bin/sing-box-darwin-arm64' : 'assets/bin/sing-box-darwin-amd64';
      name = 'sing-box';
    } else {
      asset = 'assets/bin/sing-box-linux-amd64';
      name = 'sing-box';
    }
    final out = File(p.join(dir.path, name));
    if (!await out.exists()) {
      final data = await rootBundle.load(asset);
      await out.writeAsBytes(data.buffer.asUint8List(), flush: true);
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', out.path]);
      }
    }
    return out.path;
  }

  Future<void> start(Map<String, dynamic> config) async {
    await stop();
    final binary = await _resolveBinary();
    final tempDir = await getTemporaryDirectory();
    _configPath = p.join(tempDir.path, 'grey-vless-${DateTime.now().millisecondsSinceEpoch}.json');
    await File(_configPath!).writeAsString(const JsonEncoder.withIndent('  ').convert(config));

    _process = await Process.start(binary, ['run', '-c', _configPath!]);
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
