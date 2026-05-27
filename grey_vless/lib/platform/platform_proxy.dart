import 'dart:io';

import 'package:flutter/services.dart';

class PlatformProxy {
  static const _channel = MethodChannel('com.grey.vless/proxy');

  String? _previousMode;

  Future<void> enable({required String host, required int port}) async {
    if (Platform.isLinux) {
      await _linuxEnable(host, port);
    } else if (Platform.isMacOS) {
      await _macEnable(host, port);
    } else if (Platform.isWindows) {
      await _windowsEnable(host, port);
    } else if (Platform.isAndroid) {
      await _channel.invokeMethod('enable', {'host': host, 'port': port});
    }
  }

  Future<void> disable() async {
    if (Platform.isLinux) {
      await _linuxDisable();
    } else if (Platform.isMacOS) {
      await _macDisable();
    } else if (Platform.isWindows) {
      await _windowsDisable();
    } else if (Platform.isAndroid) {
      await _channel.invokeMethod('disable');
    }
  }

  Future<void> _linuxEnable(String host, int port) async {
    final mode = await Process.run('gsettings', ['get', 'org.gnome.system.proxy', 'mode']);
    _previousMode = (mode.stdout as String).trim().replaceAll("'", '');
    await Process.run('gsettings', ['set', 'org.gnome.system.proxy', 'mode', 'manual']);
    for (final key in ['http', 'https', 'ftp', 'socks']) {
      await Process.run('gsettings', ['set', 'org.gnome.system.proxy.$key', 'host', host]);
      await Process.run('gsettings', ['set', 'org.gnome.system.proxy.$key', 'port', '$port']);
    }
    final verify = await Process.run('gsettings', ['get', 'org.gnome.system.proxy', 'mode']);
    final current = (verify.stdout as String).trim().replaceAll("'", '');
    if (current != 'manual') {
      throw Exception(
        'Не удалось включить системный прокси (mode=$current). '
        'Запускайте приложение без sudo.',
      );
    }
  }

  Future<void> _linuxDisable() async {
    final mode = _previousMode ?? 'none';
    await Process.run('gsettings', ['set', 'org.gnome.system.proxy', 'mode', mode]);
  }

  Future<void> _macEnable(String host, int port) async {
    for (final service in await _macNetworkServices()) {
      await Process.run('networksetup', ['-setwebproxy', service, host, '$port']);
      await Process.run('networksetup', ['-setsecurewebproxy', service, host, '$port']);
      await Process.run('networksetup', ['-setsocksfirewallproxy', service, host, '$port']);
    }
  }

  Future<void> _macDisable() async {
    for (final service in await _macNetworkServices()) {
      await Process.run('networksetup', ['-setwebproxystate', service, 'off']);
      await Process.run('networksetup', ['-setsecurewebproxystate', service, 'off']);
      await Process.run('networksetup', ['-setsocksfirewallproxystate', service, 'off']);
    }
  }

  Future<List<String>> _macNetworkServices() async {
    final result = await Process.run('networksetup', ['-listallnetworkservices']);
    final lines = (result.stdout as String).split('\n');
    return lines.where((l) => l.isNotEmpty && !l.startsWith('*') && !l.contains('asterisk')).toList();
  }

  Future<void> _windowsEnable(String host, int port) async {
    await Process.run('reg', [
      'add',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v',
      'ProxyEnable',
      '/t',
      'REG_DWORD',
      '/d',
      '1',
      '/f',
    ]);
    await Process.run('reg', [
      'add',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v',
      'ProxyServer',
      '/t',
      'REG_SZ',
      '/d',
      'http=$host:$port;https=$host:$port;socks=$host:$port',
      '/f',
    ]);
  }

  Future<void> _windowsDisable() async {
    await Process.run('reg', [
      'add',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v',
      'ProxyEnable',
      '/t',
      'REG_DWORD',
      '/d',
      '0',
      '/f',
    ]);
  }
}
