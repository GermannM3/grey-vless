import 'dart:async';
import 'dart:io';

import '../models/server.dart';
import '../platform/platform_proxy.dart';
import '../platform/singbox_runner.dart';
import 'connection_watchdog.dart';
import 'grey_sense_service.dart';
import 'ping_service.dart';
import 'singbox_config.dart';

class ConnectionService {
  ConnectionService(this.greySense) {
    _watchdog = ConnectionWatchdog(_runner, _autoReconnect);
  }

  final GreySenseService greySense;
  final SingboxRunner _runner = SingboxRunner();
  final PlatformProxy _proxy = PlatformProxy();
  late final ConnectionWatchdog _watchdog;

  VpnServer? connectedServer;
  bool tunMode = false;
  bool autoReconnect = true;

  final _events = StreamController<ConnectionEvent>.broadcast();
  Stream<ConnectionEvent> get events => _events.stream;

  bool get isConnected => _runner.isRunning;
  bool get isReconnecting => _watchdog.isReconnecting;

  bool get isProxyOnly => Platform.isAndroid && isConnected && !tunMode;
  bool get isFullVpn => isConnected && tunMode;

  Future<void> connect(VpnServer server, {bool fromWatchdog = false}) async {
    await disconnect(stopWatchdog: false);
    try {
      final config = SingboxConfigBuilder.build(server, tunMode: tunMode);
      await _runner.start(config, tunMode: tunMode);
      if (!tunMode && !Platform.isAndroid && !Platform.isIOS) {
        try {
          await _proxy.enable(host: '127.0.0.1', port: SingboxConfigBuilder.localPort);
        } catch (_) {}
      }
      connectedServer = server;
      await greySense.recordSuccess(server);
      _watchdog.start(server);
      if (fromWatchdog) {
        _events.add(ConnectionEvent.reconnected(server));
      } else {
        _events.add(ConnectionEvent.connected(server));
      }
    } catch (e) {
      await greySense.recordFailure(server);
      rethrow;
    }
  }

  Future<void> switchServer(VpnServer server) async {
    if (connectedServer == server && isConnected) return;
    await connect(server);
  }

  Future<void> disconnect({bool stopWatchdog = true}) async {
    if (stopWatchdog) _watchdog.stop();
    await _runner.stop();
    if (!tunMode && !Platform.isAndroid && !Platform.isIOS) {
      await _proxy.disable();
    }
    connectedServer = null;
    if (stopWatchdog) {
      _events.add(ConnectionEvent.disconnected());
    }
  }

  Future<VpnServer> connectFastest(List<VpnServer> servers) async {
    await PingService.pingAll(servers);
    final best = greySense.recommend(servers) ?? PingService.fastest(servers);
    if (best == null) {
      throw Exception('Нет доступных серверов');
    }
    await connect(best);
    return best;
  }

  Future<void> _autoReconnect(VpnServer server) async {
    if (!autoReconnect) return;
    _events.add(ConnectionEvent.reconnecting());
    var target = server;
    if (greySenseEnabled) {
      target = await greySense.pickForAutoReconnect(
            _lastKnownServers,
            server,
          ) ??
          server;
    }
    await connect(target, fromWatchdog: true);
  }

  bool greySenseEnabled = true;
  List<VpnServer> _lastKnownServers = [];

  void updateServerList(List<VpnServer> servers) => _lastKnownServers = servers;
}

sealed class ConnectionEvent {
  const ConnectionEvent();
  factory ConnectionEvent.connected(VpnServer s) = ConnectedEvent;
  factory ConnectionEvent.disconnected() = DisconnectedEvent;
  factory ConnectionEvent.reconnecting() = ReconnectingEvent;
  factory ConnectionEvent.reconnected(VpnServer s) = ReconnectedEvent;
}

class ConnectedEvent extends ConnectionEvent {
  ConnectedEvent(this.server);
  final VpnServer server;
}

class DisconnectedEvent extends ConnectionEvent {}

class ReconnectingEvent extends ConnectionEvent {}

class ReconnectedEvent extends ConnectionEvent {
  ReconnectedEvent(this.server);
  final VpnServer server;
}
