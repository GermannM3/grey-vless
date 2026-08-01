import 'dart:async';
import 'dart:io';

import '../models/server.dart';
import '../models/tunnel_mode.dart';
import '../platform/platform_proxy.dart';
import '../platform/singbox_runner.dart';
import 'connection_watchdog.dart';
import 'grey_sense_service.dart';
import 'parser.dart';
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
  TunnelMode tunnelMode = TunnelMode.fullVpn;
  List<String> tunnelAppIds = [];
  bool autoReconnect = true;

  final _events = StreamController<ConnectionEvent>.broadcast();
  Stream<ConnectionEvent> get events => _events.stream;

  /// Сериализация connect/disconnect — защита от double-start.
  /// Важно: внутри _connectBody/_disconnectBody НЕ вызывать connect()/disconnect() —
  /// иначе deadlock (ждём сами себя).
  Future<void> _chain = Future.value();
  int _opGen = 0;

  bool get isConnected => _runner.isRunning;
  bool get isReconnecting => _watchdog.isReconnecting;

  bool get isProxyOnly => Platform.isAndroid && isConnected && !tunMode;
  bool get isFullVpn => isConnected && tunMode;

  Future<T> _serialized<T>(Future<T> Function() fn) {
    final completer = Completer<T>();
    _chain = _chain.catchError((_) {}).then((_) async {
      try {
        final result = await fn();
        if (!completer.isCompleted) completer.complete(result);
      } catch (e, st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      }
    });
    // Не даём упавшему/зависшему звену убить всю очередь навсегда.
    _chain = _chain.catchError((_) {});
    return completer.future;
  }

  Future<void> connect(VpnServer server, {bool fromWatchdog = false}) {
    return _serialized(() => _connectBody(server, fromWatchdog: fromWatchdog));
  }

  Future<void> _connectBody(VpnServer server, {bool fromWatchdog = false}) async {
    final gen = ++_opGen;
    // Только _disconnectBody — НЕ disconnect() (тот же mutex → вечный hang).
    await _disconnectBody(stopWatchdog: !fromWatchdog);
    if (gen != _opGen) return;

    final resolved = _prepareServer(server);
    try {
      final useTun = tunnelMode.usesTun || (!Platform.isAndroid && tunnelMode.needsAppList);
      tunMode = useTun;
      if (tunnelMode.needsAppList && tunnelAppIds.isEmpty) {
        throw Exception(
          tunnelMode == TunnelMode.selectedApps
              ? 'Выберите хотя бы одно приложение для прохождения через VLESS.'
              : 'Выберите приложения, которые должны идти мимо VPN.',
        );
      }
      final config = SingboxConfigBuilder.build(
        resolved,
        tunMode: useTun,
        tunnelMode: tunnelMode,
        tunnelAppIds: tunnelAppIds,
      );
      await _runner
          .start(
            config,
            tunMode: useTun,
            tunnelMode: tunnelMode,
            tunnelAppIds: tunnelAppIds,
          )
          .timeout(
            const Duration(seconds: 25),
            onTimeout: () => throw TimeoutException(
              'Ядро не ответило за 25с. Попробуйте «Системный прокси» или другой сервер.',
            ),
          );
      if (gen != _opGen) {
        await _runner.stop();
        return;
      }
      if (!useTun && !Platform.isAndroid && !Platform.isIOS) {
        try {
          await _proxy.enable(host: '127.0.0.1', port: SingboxConfigBuilder.localPort);
        } catch (e) {
          await _runner.stop();
          throw Exception('Не удалось включить системный прокси: $e');
        }
      }
      connectedServer = resolved;
      await greySense.recordSuccess(resolved);
      _watchdog.start(resolved);
      if (fromWatchdog) {
        _events.add(ConnectionEvent.reconnected(resolved));
      } else {
        _events.add(ConnectionEvent.connected(resolved));
      }
    } catch (e) {
      await greySense.recordFailure(resolved);
      if (!fromWatchdog) {
        _watchdog.stop();
      }
      rethrow;
    }
  }

  VpnServer _prepareServer(VpnServer server) {
    var resolved = server;
    if (server.rawLink.trim().isNotEmpty) {
      try {
        resolved = LinkParser.parse(server.rawLink.trim());
      } catch (_) {
        resolved = server;
      }
    }
    _validate(resolved);
    return resolved;
  }

  void _validate(VpnServer server) {
    if (server.host.trim().isEmpty) {
      throw Exception('Нет адреса сервера. Обновите подписку (кнопка ↻).');
    }
    switch (server.protocol) {
      case 'vless':
      case 'vmess':
        if ((server.params['uuid'] ?? '').trim().isEmpty) {
          throw Exception('Нет UUID в ссылке сервера. Обновите подписку (кнопка ↻).');
        }
      case 'trojan':
      case 'shadowsocks':
        if ((server.params['password'] ?? '').trim().isEmpty) {
          throw Exception('Нет пароля в ссылке сервера. Обновите подписку (кнопка ↻).');
        }
    }
  }

  Future<void> switchServer(VpnServer server) async {
    if (connectedServer == server && isConnected) return;
    await connect(server);
  }

  Future<void> disconnect({bool stopWatchdog = true}) {
    return _serialized(() => _disconnectBody(stopWatchdog: stopWatchdog));
  }

  Future<void> _disconnectBody({bool stopWatchdog = true}) async {
    _opGen++;
    if (stopWatchdog) _watchdog.stop();
    try {
      await _runner.stop().timeout(const Duration(seconds: 8));
    } catch (_) {
      // Не блокируем connect из‑за тормозного stop.
    }
    if (!tunMode && !Platform.isAndroid && !Platform.isIOS) {
      try {
        await _proxy.disable().timeout(const Duration(seconds: 3));
      } catch (_) {}
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
      // Не пингуем весь список — только быстрый выбор из кэша stats.
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
