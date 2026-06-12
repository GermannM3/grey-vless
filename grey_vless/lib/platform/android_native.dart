import 'package:flutter/services.dart';

class AndroidNative {
  static const _channel = MethodChannel('com.grey.vless/android');

  static Future<bool> isHevAvailable() async {
    final ok = await _channel.invokeMethod<bool>('isHevAvailable');
    return ok ?? false;
  }

  /// Копирует sing-box в codeCacheDir и делает исполняемым (Xiaomi/Samsung).
  static Future<String> prepareSingboxBinary(String sourcePath) async {
    final path = await _channel.invokeMethod<String>('prepareSingboxBinary', {'path': sourcePath});
    if (path == null || path.isEmpty) {
      throw Exception('Не удалось подготовить sing-box');
    }
    return path;
  }

  static Future<bool> chmodExecutable(String path) async {
    final ok = await _channel.invokeMethod<bool>('chmodExecutable', {'path': path});
    return ok ?? false;
  }

  static Future<({int exitCode, String output})> singboxCheck({
    required String binaryPath,
    required String configPath,
  }) async {
    final map = await _channel.invokeMethod<Map>('singboxCheck', {
      'binaryPath': binaryPath,
      'configPath': configPath,
    });
    if (map == null) {
      throw Exception('singbox check failed');
    }
    return (
      exitCode: (map['exitCode'] as num?)?.toInt() ?? 1,
      output: map['output']?.toString() ?? '',
    );
  }

  static Future<void> singboxStart({
    required String binaryPath,
    required String configPath,
  }) async {
    await _channel.invokeMethod<void>('singboxStart', {
      'binaryPath': binaryPath,
      'configPath': configPath,
    });
  }

  static Future<void> singboxStop() async {
    await _channel.invokeMethod<void>('singboxStop');
  }

  static Future<bool> singboxIsRunning() async {
    final ok = await _channel.invokeMethod<bool>('singboxIsRunning');
    return ok ?? false;
  }

  static Future<bool> prepareVpn() async {
    final ok = await _channel.invokeMethod<bool>('prepareVpn');
    return ok ?? false;
  }

  static Future<void> startVpn({
    required String configPath,
    required String binaryPath,
    int proxyPort = 7890,
  }) async {
    try {
      await _channel.invokeMethod<void>('startVpn', {
        'configPath': configPath,
        'binaryPath': binaryPath,
        'proxyPort': proxyPort,
      });
    } on PlatformException catch (e) {
      if (e.code == 'no_hev') {
        throw Exception(
          'TUN недоступен на этом телефоне. Отключите TUN — прокси на 127.0.0.1:7890 всё равно работает.',
        );
      }
      throw Exception(e.message ?? 'Не удалось запустить VPN');
    }
  }

  static Future<void> stopVpn() async {
    await _channel.invokeMethod<void>('stopVpn');
  }

  static Future<void> installApk(String path) async {
    await _channel.invokeMethod<void>('installApk', {'path': path});
  }
}
