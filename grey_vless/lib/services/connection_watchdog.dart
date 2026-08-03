import 'dart:async';
import 'dart:io';

import '../models/server.dart';
import '../platform/android_native.dart';
import '../platform/singbox_runner.dart';
import 'app_log.dart';
import 'singbox_config.dart';

typedef ReconnectCallback = Future<void> Function(VpnServer server);

/// Следит за живостью туннеля и переподключается с backoff.
///
/// Важно: клиент часто идёт direct (Android disallowed / Windows process_name),
/// поэтому HTTP-пробы ОБЯЗАНЫ идти через 127.0.0.1:7890 — иначе ложные reconnect
/// убивают живой VPN, когда «голый» интернет мигает или режет generate_204.
class ConnectionWatchdog {
  ConnectionWatchdog(this._runner, this._reconnect);

  final SingboxRunner _runner;
  final ReconnectCallback _reconnect;

  Timer? _timer;
  VpnServer? _server;
  bool _reconnecting = false;
  bool _tickRunning = false;
  int _failStreak = 0;
  int _reconnectAttempts = 0;
  DateTime? _nextAllowedReconnect;

  static const _baseInterval = Duration(seconds: 60);
  static const _maxBackoff = Duration(minutes: 5);
  /// Сколько подряд провалов туннеля нужно, чтобы дернуть reconnect.
  static const _failsBeforeReconnect = 4;

  bool get isActive => _timer != null;
  bool get isReconnecting => _reconnecting;
  int get failStreak => _failStreak;

  void start(VpnServer server) {
    _server = server;
    _failStreak = 0;
    _reconnectAttempts = 0;
    _nextAllowedReconnect = null;
    _timer?.cancel();
    // Первый тик не сразу — дать туннелю прогреться.
    _timer = Timer.periodic(_baseInterval, (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _server = null;
    _failStreak = 0;
    _reconnectAttempts = 0;
    _nextAllowedReconnect = null;
    _reconnecting = false;
    _tickRunning = false;
  }

  Future<void> _tick() async {
    if (_reconnecting || _tickRunning || _server == null) return;
    _tickRunning = true;
    try {
      final ok = await _healthOk();
      if (ok) {
        _failStreak = 0;
        _reconnectAttempts = 0;
        _nextAllowedReconnect = null;
        return;
      }
      _failStreak++;
      if (_failStreak < _failsBeforeReconnect) return;

      final now = DateTime.now();
      if (_nextAllowedReconnect != null && now.isBefore(_nextAllowedReconnect!)) {
        return;
      }

      _reconnecting = true;
      try {
        final server = _server!;
        AppLog.instance.warn('watchdog', 'reconnect → ${server.name} (fails=$_failStreak)');
        await _reconnect(server);
        _failStreak = 0;
        _reconnectAttempts = 0;
        _nextAllowedReconnect = null;
        AppLog.instance.info('watchdog', 'reconnect OK');
      } catch (e) {
        AppLog.instance.exception('watchdog', e);
        _reconnectAttempts++;
        final secs = (45 * (1 << _reconnectAttempts.clamp(0, 4))).clamp(45, _maxBackoff.inSeconds);
        _nextAllowedReconnect = DateTime.now().add(Duration(seconds: secs));
        AppLog.instance.warn('watchdog', 'backoff ${secs}s');
      } finally {
        _reconnecting = false;
      }
    } finally {
      _tickRunning = false;
    }
  }

  Future<bool> _healthOk() async {
    if (!_runner.isRunning) return false;

    // 1) Локальный mixed — ядро живо.
    if (!await _localPortOpen()) return false;

    // 2) Android: раз VpnService/прокси живы — не рвём сессию из‑за «голого» интернета.
    //    (приложение в disallowed → старые probe шли мимо VPN и ложно роняли туннель.)
    if (Platform.isAndroid) {
      final vpnAlive = await AndroidNative.isVpnActive();
      final proxyAlive = await AndroidNative.singboxIsRunning();
      return vpnAlive || proxyAlive;
    }

    // 3) Desktop: выход именно через local proxy (не direct ISP).
    return _tunnelProbe();
  }

  Future<bool> _localPortOpen() async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        '127.0.0.1',
        SingboxConfigBuilder.localPort,
        timeout: const Duration(seconds: 2),
      ).timeout(const Duration(seconds: 3));
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  /// HTTP через 127.0.0.1:7890 — реальный путь трафика VPN/прокси.
  Future<bool> _tunnelProbe() async {
    const urls = [
      'https://www.gstatic.com/generate_204',
      'https://connectivitycheck.gstatic.com/generate_204',
      'http://cp.cloudflare.com/',
    ];
    for (final url in urls) {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);
      client.findProxy = (_) => 'PROXY 127.0.0.1:${SingboxConfigBuilder.localPort}';
      client.badCertificateCallback = (_, __, ___) => true;
      try {
        final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 8));
        req.followRedirects = false;
        final resp = await req.close().timeout(const Duration(seconds: 10));
        final code = resp.statusCode;
        await resp.drain<void>().timeout(const Duration(seconds: 3), onTimeout: () {});
        // 204/200/30x — туннель отвечает.
        if (code >= 200 && code < 500) return true;
      } catch (_) {
        continue;
      } finally {
        client.close(force: true);
      }
    }
    return false;
  }
}
