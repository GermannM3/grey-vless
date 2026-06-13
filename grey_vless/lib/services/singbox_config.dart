import 'dart:io';

import '../models/server.dart';

class SingboxConfigBuilder {
  static const localPort = 7890;

  static Map<String, dynamic> _mixedInbound() => {
        'type': 'mixed',
        'tag': 'mixed-in',
        'listen': '127.0.0.1',
        'listen_port': localPort,
      };

  static Map<String, dynamic> _tunInbound() {
    if (Platform.isAndroid) {
      return {
        'type': 'tun',
        'tag': 'tun-in',
        'address': ['172.19.0.1/30'],
        'auto_route': true,
        'strict_route': true,
        'stack': 'gvisor',
        'sniff': true,
        'sniff_override_destination': true,
      };
    }
    return {
      'type': 'tun',
      'tag': 'tun-in',
      'interface_name': 'tun0',
      'address': ['172.19.0.1/30'],
      'auto_route': true,
      'strict_route': true,
      'stack': 'system',
      'sniff': true,
      'sniff_override_destination': true,
    };
  }

  static Map<String, dynamic> build(VpnServer server, {bool tunMode = false}) {
    final inbounds = <Map<String, dynamic>>[];
    final useTun = tunMode && !Platform.isAndroid;
    if (useTun) {
      inbounds.add(_tunInbound());
    }
    // Локальный HTTP/SOCKS — всегда
    inbounds.add(_mixedInbound());

    return {
      'log': {'level': Platform.isAndroid ? 'info' : 'warn'},
      'dns': _dnsBlock(),
      'inbounds': inbounds,
      'outbounds': [
        _withDialer(_outbound(server)),
        {'type': 'direct', 'tag': 'direct'},
        {'type': 'block', 'tag': 'block'},
      ],
      'route': _routeBlock(),
    };
  }

  static Map<String, dynamic> _routeBlock() {
    if (Platform.isAndroid) {
      return {
        'rules': [
          {'protocol': 'dns', 'action': 'hijack-dns'},
        ],
        'final': 'proxy',
      };
    }
    return {
      'auto_detect_interface': true,
      'rules': [
        {'protocol': 'dns', 'action': 'hijack-dns'},
      ],
      'final': 'proxy',
    };
  }

  static Map<String, dynamic> _dnsBlock() {
    if (Platform.isAndroid) {
      return {
        'servers': [
          {'tag': 'local', 'address': '223.5.5.5', 'detour': 'direct'},
          {'tag': 'remote', 'address': '8.8.8.8', 'detour': 'proxy'},
        ],
        'final': 'remote',
        'strategy': 'prefer_ipv4',
      };
    }
    return {
      'servers': [
        {'tag': 'remote', 'address': 'tls://8.8.8.8', 'detour': 'proxy'},
        {'tag': 'local', 'address': '223.5.5.5', 'detour': 'direct'},
      ],
      'rules': [
        {'outbound': 'any', 'server': 'remote'},
      ],
      'final': 'remote',
      'strategy': 'prefer_ipv4',
    };
  }

  static Map<String, dynamic> _withDialer(Map<String, dynamic> outbound) {
    outbound['dialer_options'] = {
      'tcp_keep_alive': '30s',
      'tcp_keep_alive_interval': '15s',
      'connect_timeout': '20s',
    };
    return outbound;
  }

  static Map<String, dynamic> _outbound(VpnServer server) {
    switch (server.protocol) {
      case 'vless':
        return _vless(server);
      case 'vmess':
        return _vmess(server);
      case 'trojan':
        return _trojan(server);
      case 'shadowsocks':
        return _shadowsocks(server);
      default:
        throw UnsupportedError('Протокол ${server.protocol} не поддерживается');
    }
  }

  static Map<String, dynamic>? _transport(VpnServer server) {
    final network = server.params['network'] ?? 'tcp';
    if (network == 'tcp' || network == 'none' || network.isEmpty) return null;
    final transport = <String, dynamic>{'type': network};
    if (network == 'ws') {
      transport['path'] = server.params['path']?.isNotEmpty == true ? server.params['path'] : '/';
      final host = server.params['host'] ?? server.params['host_header'];
      if (host != null && host.isNotEmpty) {
        transport['headers'] = {'Host': host};
      }
    } else if (network == 'grpc') {
      transport['service_name'] = server.params['serviceName'] ?? '';
    }
    return transport;
  }

  static Map<String, dynamic>? _tls(VpnServer server) {
    final security = (server.params['security'] ?? server.params['tls'] ?? '').toLowerCase();
    if (!['tls', 'reality', 'xtls'].contains(security)) return null;
    final tls = <String, dynamic>{
      'enabled': true,
      'server_name': (server.params['sni']?.isNotEmpty == true) ? server.params['sni'] : server.host,
    };
    final fp = server.params['fp'];
    if (fp != null && fp.isNotEmpty) {
      tls['utls'] = {'enabled': true, 'fingerprint': fp};
    }
    if (security == 'reality') {
      tls['reality'] = {
        'enabled': true,
        'public_key': server.params['pbk'] ?? '',
        'short_id': server.params['sid'] ?? '',
      };
    }
    return tls;
  }

  static Map<String, dynamic> _vless(VpnServer server) {
    final outbound = <String, dynamic>{
      'type': 'vless',
      'tag': 'proxy',
      'server': server.host,
      'server_port': server.port,
      'uuid': server.params['uuid'] ?? '',
    };
    final flow = server.params['flow'];
    if (flow != null && flow.isNotEmpty) outbound['flow'] = flow;
    final transport = _transport(server);
    if (transport != null) outbound['transport'] = transport;
    final tls = _tls(server);
    if (tls != null) outbound['tls'] = tls;
    return outbound;
  }

  static Map<String, dynamic> _vmess(VpnServer server) {
    final outbound = <String, dynamic>{
      'type': 'vmess',
      'tag': 'proxy',
      'server': server.host,
      'server_port': server.port,
      'uuid': server.params['uuid'] ?? '',
      'security': server.params['security'] ?? 'auto',
      'alter_id': int.tryParse(server.params['alter_id'] ?? '0') ?? 0,
    };
    final transport = _transport(server);
    if (transport != null) outbound['transport'] = transport;
    final tls = _tls(server);
    if (tls != null) outbound['tls'] = tls;
    return outbound;
  }

  static Map<String, dynamic> _trojan(VpnServer server) {
    final outbound = <String, dynamic>{
      'type': 'trojan',
      'tag': 'proxy',
      'server': server.host,
      'server_port': server.port,
      'password': server.params['password'] ?? '',
    };
    final transport = _transport(server);
    if (transport != null) outbound['transport'] = transport;
    outbound['tls'] = _tls(server) ??
        {
          'enabled': true,
          'server_name': (server.params['sni']?.isNotEmpty == true) ? server.params['sni'] : server.host,
        };
    return outbound;
  }

  static Map<String, dynamic> _shadowsocks(VpnServer server) {
    return {
      'type': 'shadowsocks',
      'tag': 'proxy',
      'server': server.host,
      'server_port': server.port,
      'method': server.params['method'] ?? 'aes-256-gcm',
      'password': server.params['password'] ?? '',
    };
  }
}
