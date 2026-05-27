import 'dart:convert';

import '../models/server.dart';

class LinkParser {
  static VpnServer parse(String link) {
    final trimmed = link.trim();
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('vless://')) return _parseUri(trimmed, 'vless');
    if (lower.startsWith('vmess://')) return _parseVmess(trimmed);
    if (lower.startsWith('trojan://')) return _parseUri(trimmed, 'trojan');
    if (lower.startsWith('ss://')) return _parseShadowsocks(trimmed);
    throw FormatException('Неподдерживаемый формат: ${trimmed.substring(0, trimmed.length.clamp(0, 32))}');
  }

  static VpnServer _parseUri(String link, String protocol) {
    final uri = Uri.parse(link);
    final params = uri.queryParameters;
    final name = Uri.decodeComponent(uri.fragment.isEmpty ? protocol.toUpperCase() : uri.fragment);
    final password = uri.userInfo.split(':').first;
    return VpnServer(
      name: name,
      protocol: protocol,
      host: uri.host,
      port: uri.port == 0 ? 443 : uri.port,
      rawLink: link,
      params: {
        if (protocol == 'vless') 'uuid': password else 'password': password,
        'security': params['security'] ?? '',
        'network': params['type'] ?? 'tcp',
        'flow': params['flow'] ?? '',
        'path': params['path'] ?? '',
        'host': params['host'] ?? '',
        'sni': params['sni'] ?? '',
        'fp': params['fp'] ?? 'chrome',
        'pbk': params['pbk'] ?? '',
        'sid': params['sid'] ?? '',
        'headerType': params['headerType'] ?? '',
        'serviceName': params['serviceName'] ?? '',
        'encryption': params['encryption'] ?? 'none',
      },
    );
  }

  static VpnServer _parseVmess(String link) {
    final payload = link.substring('vmess://'.length);
    final padded = payload + '=' * ((4 - payload.length % 4) % 4);
    final jsonStr = utf8.decode(base64.decode(padded));
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    return VpnServer(
      name: (data['ps'] ?? data['remark'] ?? 'VMess').toString(),
      protocol: 'vmess',
      host: (data['add'] ?? data['host'] ?? '').toString(),
      port: int.tryParse(data['port']?.toString() ?? '') ?? 443,
      rawLink: link,
      params: {
        'uuid': (data['id'] ?? '').toString(),
        'alter_id': (data['aid'] ?? '0').toString(),
        'security': (data['scy'] ?? 'auto').toString(),
        'network': (data['net'] ?? 'tcp').toString(),
        'host_header': (data['host'] ?? '').toString(),
        'path': (data['path'] ?? '').toString(),
        'tls': (data['tls'] ?? '').toString(),
        'sni': (data['sni'] ?? data['host'] ?? '').toString(),
        'fp': (data['fp'] ?? '').toString(),
        'type': (data['type'] ?? 'none').toString(),
        'serviceName': (data['serviceName'] ?? data['servicename'] ?? '').toString(),
      },
    );
  }

  static VpnServer _parseShadowsocks(String link) {
    final uri = Uri.parse(link);
    final name = Uri.decodeComponent(uri.fragment.isEmpty ? 'Shadowsocks' : uri.fragment);
    String method;
    String password;
    String host;
    int port;

    if (uri.userInfo.contains('@') || uri.host.isNotEmpty && uri.port != 0) {
      final userHost = uri.userInfo;
      if (userHost.contains('@')) {
        final parts = userHost.split('@');
        final creds = parts.first.split(':');
        method = creds.first;
        password = creds.sublist(1).join(':');
        final hp = parts.last.split(':');
        host = hp.first;
        port = int.parse(hp.last);
      } else {
        final decoded = utf8.decode(base64.decode(userHost + '=' * ((4 - userHost.length % 4) % 4)));
        final at = decoded.split('@');
        final mp = at.first.split(':');
        method = mp.first;
        password = mp.sublist(1).join(':');
        final hp = at.last.split(':');
        host = hp.first;
        port = int.parse(hp.last);
      }
    } else {
      final payload = uri.path.replaceFirst('/', '');
      final decoded = utf8.decode(base64.decode(payload + '=' * ((4 - payload.length % 4) % 4)));
      final at = decoded.split('@');
      final mp = at.first.split(':');
      method = mp.first;
      password = mp.sublist(1).join(':');
      final hp = at.last.split(':');
      host = hp.first;
      port = int.parse(hp.last);
    }

    return VpnServer(
      name: name,
      protocol: 'shadowsocks',
      host: host,
      port: port,
      rawLink: link,
      params: {'method': method, 'password': password},
    );
  }
}
