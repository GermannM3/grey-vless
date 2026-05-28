import 'package:flutter/services.dart';

class AndroidNative {
  static const _channel = MethodChannel('com.grey.vless/android');

  static Future<bool> chmodExecutable(String path) async {
    final ok = await _channel.invokeMethod<bool>('chmodExecutable', {'path': path});
    return ok ?? false;
  }

  static Future<bool> prepareVpn() async {
    final ok = await _channel.invokeMethod<bool>('prepareVpn');
    return ok ?? false;
  }

  static Future<void> startVpn({required String configPath, required String binaryPath}) async {
    await _channel.invokeMethod<void>('startVpn', {
      'configPath': configPath,
      'binaryPath': binaryPath,
    });
  }

  static Future<void> stopVpn() async {
    await _channel.invokeMethod<void>('stopVpn');
  }
}
