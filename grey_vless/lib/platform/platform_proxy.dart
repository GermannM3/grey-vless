import 'dart:io';

import 'package:flutter/services.dart';

class PlatformProxy {
  static const _channel = MethodChannel('com.grey.vless/proxy');

  String? _previousMode;
  String? _previousWinEnable;
  String? _previousWinServer;
  bool _macProxyTouched = false;

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
      _macProxyTouched = true;
    }
  }

  Future<void> _macDisable() async {
    if (!_macProxyTouched) return;
    for (final service in await _macNetworkServices()) {
      await Process.run('networksetup', ['-setwebproxystate', service, 'off']);
      await Process.run('networksetup', ['-setsecurewebproxystate', service, 'off']);
      await Process.run('networksetup', ['-setsocksfirewallproxystate', service, 'off']);
    }
    _macProxyTouched = false;
  }

  Future<List<String>> _macNetworkServices() async {
    final result = await Process.run('networksetup', ['-listallnetworkservices']);
    final lines = (result.stdout as String).split('\n');
    return lines.where((l) => l.isNotEmpty && !l.startsWith('*') && !l.contains('asterisk')).toList();
  }

  Future<String?> _regQuery(String valueName) async {
    final result = await Process.run('reg', [
      'query',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v',
      valueName,
    ]);
    if (result.exitCode != 0) return null;
    final text = (result.stdout as String).replaceAll('\r', '');
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('$valueName ')) {
        final parts = trimmed.split(RegExp(r'\s{2,}'));
        if (parts.length >= 3) return parts.last.trim();
      }
    }
    return null;
  }

  Future<void> _windowsEnable(String host, int port) async {
    _previousWinEnable ??= await _regQuery('ProxyEnable');
    _previousWinServer ??= await _regQuery('ProxyServer');

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
    if (_previousWinEnable != null) {
      final raw = _previousWinEnable!.toLowerCase();
      final enable = raw.contains('0x1') || raw == '1' ? '1' : '0';
      await Process.run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyEnable',
        '/t',
        'REG_DWORD',
        '/d',
        enable,
        '/f',
      ]);
    } else {
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
    if (_previousWinServer != null) {
      await Process.run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyServer',
        '/t',
        'REG_SZ',
        '/d',
        _previousWinServer!,
        '/f',
      ]);
    }
    _previousWinEnable = null;
    _previousWinServer = null;
  }
}
