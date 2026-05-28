import 'dart:io';

import '../models/server.dart';

class SingboxConfigBuilder {
  static const localPort = 7890;

  static Map<String, dynamic> _tunInbound() {
    if (Platform.isAndroid) {
      return {
        'type': 'tun',
        'tag': 'tun-in',
        'inet4_address': ['172.19.0.1/30'],
        'mtu': 9000,
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
      'inet4_address': ['172.19.0.1/30'],
      'auto_route': true,
      'strict_route': true,
      'stack': 'system',
      'sniff': true,
    };
  }

  static Map<String, dynamic> build(VpnServer server, {bool tunMode = false}) {
    final inbounds = tunMode
        ? [_tunInbound()]
        : [
            {
              'type': 'mixed',
              'tag': 'mixed-in',
              'listen': '127.0.0.1',
              'listen_port': localPort,
            }
          ];

    return {
      'log': {'level': 'warn'},
      'dns': {
        'servers': [
          {'tag': 'google', 'address': '8.8.8.8'},
          {'tag': 'local', 'address': '223.5.5.5', 'detour': 'direct'},
        ],
        'strategy': 'prefer_ipv4',
      },
      'inbounds': inbounds,
      'outbounds': [
        _outbound(server),
        {'type': 'direct', 'tag': 'direct'},
        {'type': 'block', 'tag': 'block'},
      ],
      'route': {
        'auto_detect_interface': true,
        'final': 'proxy',
      },
    };
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
