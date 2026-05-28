import 'dart:io';

import '../models/server.dart';
import '../platform/platform_proxy.dart';
import '../platform/singbox_runner.dart';
import 'ping_service.dart';
import 'singbox_config.dart';

class ConnectionService {
  ConnectionService();

  final SingboxRunner _runner = SingboxRunner();
  final PlatformProxy _proxy = PlatformProxy();

  VpnServer? connectedServer;
  bool tunMode = false;

  bool get isConnected => _runner.isRunning;

  /// На Android без TUN sing-box слушает только локальный прокси — это не VPN.
  bool get isProxyOnly => Platform.isAndroid && isConnected && !tunMode;

  bool get isFullVpn => isConnected && tunMode;

  Future<void> connect(VpnServer server) async {
    await disconnect();
    final config = SingboxConfigBuilder.build(server, tunMode: tunMode);
    await _runner.start(config, tunMode: tunMode);
    if (!tunMode && !Platform.isAndroid && !Platform.isIOS) {
      await _proxy.enable(host: '127.0.0.1', port: SingboxConfigBuilder.localPort);
    }
    connectedServer = server;
  }

  Future<void> disconnect() async {
    await _runner.stop();
    if (!tunMode && !Platform.isAndroid && !Platform.isIOS) {
      await _proxy.disable();
    }
    connectedServer = null;
  }

  Future<VpnServer> connectFastest(List<VpnServer> servers) async {
    await PingService.pingAll(servers);
    final best = PingService.fastest(servers);
    if (best == null) {
      throw Exception('Нет доступных серверов');
    }
    await connect(best);
    return best;
  }
}
