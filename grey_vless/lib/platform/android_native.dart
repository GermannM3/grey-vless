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
}
