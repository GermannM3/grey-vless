import 'dart:io';

import '../models/server.dart';
import '../models/tunnel_mode.dart';
import '../platform/installed_apps.dart';

class SingboxConfigBuilder {
  static const localPort = 7890;

  static Map<String, dynamic> _mixedInbound() => {
        'type': 'mixed',
        'tag': 'mixed-in',
        'listen': '127.0.0.1',
        'listen_port': localPort,
        'sniff': true,
        'sniff_override_destination': true,
        'set_system_proxy': false,
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
    // Windows: WinTun; имя tun0 часто конфликтует — используем grey-tun.
    final iface = Platform.isWindows ? 'grey-tun' : 'tun0';
    return {
      'type': 'tun',
      'tag': 'tun-in',
      'interface_name': iface,
      'address': ['172.19.0.1/30'],
      'auto_route': true,
      'strict_route': true,
      'stack': 'system',
      'sniff': true,
      'sniff_override_destination': true,
    };
  }

  static Map<String, dynamic> build(
    VpnServer server, {
    bool tunMode = false,
    TunnelMode tunnelMode = TunnelMode.fullVpn,
    List<String> tunnelAppIds = const [],
  }) {
    final inbounds = <Map<String, dynamic>>[];
    // Per-app на desktop требует TUN, чтобы видеть процесс источника.
    final useTun = (tunMode || tunnelMode.needsAppList) && !Platform.isAndroid;
    if (useTun) {
      inbounds.add(_tunInbound());
    }
    inbounds.add(_mixedInbound());

    return {
      'log': {'level': Platform.isAndroid ? 'info' : 'warn'},
      'dns': _dnsBlock(),
      'inbounds': inbounds,
      'outbounds': [
        _outbound(server),
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': _routeBlock(tunnelMode: tunnelMode, tunnelAppIds: tunnelAppIds),
    };
  }

  static Map<String, dynamic> _routeBlock({
    required TunnelMode tunnelMode,
    required List<String> tunnelAppIds,
  }) {
    final rules = <Map<String, dynamic>>[
      {'protocol': 'dns', 'action': 'hijack-dns'},
    ];

    // Свой клиент и ядро — всегда direct (анти-петля).
    if (!Platform.isAndroid) {
      rules.add({
        'process_name': ['grey_vless.exe', 'grey_vless', 'sing-box.exe', 'sing-box'],
        'outbound': 'direct',
      });
    }

    if (Platform.isAndroid) {
      rules.add({
        'domain_suffix': [
          'telegram.org',
          't.me',
          'telegra.ph',
          'telegram.me',
          'tdesktop.com',
          'telesco.pe',
        ],
        'outbound': 'proxy',
      });
      // Per-app на Android делает VpnService; в конфиге final=proxy.
      return {
        'rules': rules,
        'final': 'proxy',
      };
    }

    // Desktop per-app через process_name / process_path (нужен find_process).
    if (tunnelMode.needsAppList && tunnelAppIds.isNotEmpty) {
      final matchers = InstalledApps.matchersFromIds(tunnelAppIds);
      final processRule = <String, dynamic>{};
      if (matchers.names.isNotEmpty) {
        processRule['process_name'] = matchers.names;
      }
      if (matchers.paths.isNotEmpty) {
        processRule['process_path'] = matchers.paths;
      }
      if (processRule.isNotEmpty) {
        if (tunnelMode == TunnelMode.selectedApps) {
          // Только выбранные → proxy, остальное напрямую.
          processRule['outbound'] = 'proxy';
          rules.add(processRule);
          return {
            'auto_detect_interface': true,
            'find_process': true,
            'rules': rules,
            'final': 'direct',
          };
        }
        if (tunnelMode == TunnelMode.bypassApps) {
          // Выбранные → direct, остальное → proxy.
          processRule['outbound'] = 'direct';
          rules.add(processRule);
          return {
            'auto_detect_interface': true,
            'find_process': true,
            'rules': rules,
            'final': 'proxy',
          };
        }
      }
    }

    return {
      'auto_detect_interface': true,
      'find_process': tunnelMode.needsAppList,
      'rules': rules,
      'final': 'proxy',
    };
  }

  static Map<String, dynamic> _dnsBlock() {
    // DNS через direct — иначе sing-box не может резолвить адрес прокси до поднятия туннеля.
    return {
      'servers': [
        {'tag': 'google', 'address': '8.8.8.8', 'detour': 'direct'},
        {'tag': 'cloudflare', 'address': '1.1.1.1', 'detour': 'direct'},
      ],
      'final': 'google',
      'strategy': 'prefer_ipv4',
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
