import 'dart:async';

import 'package:flutter/services.dart';

class AndroidNative {
  static const _channel = MethodChannel('com.grey.vless/android');

  static Future<T?> _invoke<T>(
    String method, [
    dynamic args,
    Duration timeout = const Duration(seconds: 12),
  ]) {
    return _channel.invokeMethod<T>(method, args).timeout(
      timeout,
      onTimeout: () => throw TimeoutException('Android $method timeout'),
    );
  }

  static Future<bool> isHevAvailable() async {
    try {
      return await _invoke<bool>('isHevAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Копирует sing-box в codeCacheDir и делает исполняемым (Xiaomi/Samsung).
  static Future<String> prepareSingboxBinary(String sourcePath) async {
    final path = await _invoke<String>('prepareSingboxBinary', {'path': sourcePath});
    if (path == null || path.isEmpty) {
      throw Exception('Не удалось подготовить sing-box');
    }
    return path;
  }

  static Future<String> prepareSingboxConfig(String sourcePath) async {
    final path = await _invoke<String>('prepareSingboxConfig', {'path': sourcePath});
    if (path == null || path.isEmpty) {
      throw Exception('Не удалось подготовить конфиг sing-box');
    }
    return path;
  }

  static Future<String> singboxLastLog() async {
    try {
      return await _invoke<String>('singboxLastLog', null, const Duration(seconds: 3)) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<bool> chmodExecutable(String path) async {
    final ok = await _invoke<bool>('chmodExecutable', {'path': path});
    return ok ?? false;
  }

  static Future<({int exitCode, String output})> singboxCheck({
    required String binaryPath,
    required String configPath,
  }) async {
    final map = await _invoke<Map>(
      'singboxCheck',
      {
        'binaryPath': binaryPath,
        'configPath': configPath,
      },
      const Duration(seconds: 15),
    );
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
    await _invoke<void>('singboxStart', {
      'binaryPath': binaryPath,
      'configPath': configPath,
    });
  }

  static Future<void> singboxStop() async {
    try {
      await _invoke<void>('singboxStop', null, const Duration(seconds: 5));
    } catch (_) {}
  }

  static Future<bool> singboxIsRunning() async {
    try {
      return await _invoke<bool>('singboxIsRunning', null, const Duration(seconds: 2)) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isVpnActive() async {
    try {
      return await _invoke<bool>('isVpnActive', null, const Duration(seconds: 2)) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Чужой VPN активен (WireGuard, OpenVPN и т.д.) — Grey vless не запущен.
  static Future<bool> isOtherVpnActive() async {
    try {
      return await _invoke<bool>('isOtherVpnActive', null, const Duration(seconds: 2)) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Может ждать системный диалог разрешения VPN.
  static Future<bool> prepareVpn() async {
    final ok = await _invoke<bool>('prepareVpn', null, const Duration(seconds: 120));
    return ok ?? false;
  }

  static Future<List<Map<String, dynamic>>> listInstalledApps() async {
    final raw = await _invoke<List>('listInstalledApps', null, const Duration(seconds: 30));
    if (raw == null) return [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      return await _invoke<bool>('isIgnoringBatteryOptimizations') ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<bool> requestIgnoreBatteryOptimizations() async {
    try {
      return await _invoke<bool>(
            'requestIgnoreBatteryOptimizations',
            null,
            const Duration(seconds: 60),
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> startVpn({
    required String configPath,
    required String binaryPath,
    int proxyPort = 7890,
    List<String> allowedApps = const [],
    List<String> disallowedApps = const [],
  }) async {
    try {
      await _invoke<void>('startVpn', {
        'configPath': configPath,
        'binaryPath': binaryPath,
        'proxyPort': proxyPort,
        'allowedApps': allowedApps,
        'disallowedApps': disallowedApps,
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
    try {
      await _invoke<void>('stopVpn', null, const Duration(seconds: 5));
    } catch (_) {}
  }

  static Future<void> installApk(String path) async {
    await _invoke<void>('installApk', {'path': path}, const Duration(seconds: 30));
  }
}
