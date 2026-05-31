import 'package:flutter/services.dart';

class AndroidNative {
  static const _channel = MethodChannel('com.grey.vless/android');

  static Future<bool> isHevAvailable() async {
    final ok = await _channel.invokeMethod<bool>('isHevAvailable');
    return ok ?? false;
  }

  static Future<bool> chmodExecutable(String path) async {
    final ok = await _channel.invokeMethod<bool>('chmodExecutable', {'path': path});
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
}
