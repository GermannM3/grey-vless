import 'dart:async';
import 'dart:io';

import '../models/server.dart';
import '../platform/android_native.dart';
import '../platform/singbox_runner.dart';
import 'singbox_config.dart';

typedef ReconnectCallback = Future<void> Function(VpnServer server);

/// Следит за живостью туннеля и переподключается с backoff.
class ConnectionWatchdog {
  ConnectionWatchdog(this._runner, this._reconnect);

  final SingboxRunner _runner;
  final ReconnectCallback _reconnect;

  Timer? _timer;
  VpnServer? _server;
  bool _reconnecting = false;
  bool _tickRunning = false;
  int _failStreak = 0;
  int _internetFailStreak = 0;
  int _reconnectAttempts = 0;
  DateTime? _nextAllowedReconnect;

  static const _baseInterval = Duration(seconds: 45);
  static const _maxBackoff = Duration(minutes: 5);

  bool get isActive => _timer != null;
  bool get isReconnecting => _reconnecting;
  int get failStreak => _failStreak;

  void start(VpnServer server) {
    _server = server;
    _failStreak = 0;
    _internetFailStreak = 0;
    _reconnectAttempts = 0;
    _nextAllowedReconnect = null;
    _timer?.cancel();
    _timer = Timer.periodic(_baseInterval, (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _server = null;
    _failStreak = 0;
    _internetFailStreak = 0;
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
        _internetFailStreak = 0;
        _reconnectAttempts = 0;
        _nextAllowedReconnect = null;
        return;
      }
      _failStreak++;
      if (_failStreak < 3) return;

      final now = DateTime.now();
      if (_nextAllowedReconnect != null && now.isBefore(_nextAllowedReconnect!)) {
        return;
      }

      _reconnecting = true;
      try {
        final server = _server!;
        await _reconnect(server);
        _failStreak = 0;
        _internetFailStreak = 0;
        _reconnectAttempts = 0;
        _nextAllowedReconnect = null;
      } catch (_) {
        _reconnectAttempts++;
        final secs = (30 * (1 << _reconnectAttempts.clamp(0, 4))).clamp(30, _maxBackoff.inSeconds);
        _nextAllowedReconnect = DateTime.now().add(Duration(seconds: secs));
        // не сбрасываем failStreak — следующий tick после backoff
      } finally {
        _reconnecting = false;
      }
    } finally {
      _tickRunning = false;
    }
  }

  Future<bool> _healthOk() async {
    if (!_runner.isRunning) return false;

    if (!await _localPortOpen()) return false;

    if (Platform.isAndroid) {
      final proxyAlive = await AndroidNative.singboxIsRunning();
      final vpnAlive = await AndroidNative.isVpnActive();
      // Нативные флаги авторитетнее Dart-кэша.
      if (!proxyAlive && !vpnAlive) return false;
    }

    final netOk = await _internetProbe();
    if (!netOk) {
      _internetFailStreak++;
      // Мягкий fail: сеть может мигать — не рвём на первом же 204.
      return _internetFailStreak < 2;
    }
    _internetFailStreak = 0;
    return true;
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

  Future<bool> _internetProbe() async {
    const urls = [
      'https://connectivitycheck.gstatic.com/generate_204',
      'https://www.cloudflare.com/cdn-cgi/trace',
    ];
    for (final url in urls) {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 6);
      try {
        final req = await client.getUrl(Uri.parse(url));
        final resp = await req.close().timeout(const Duration(seconds: 8));
        final code = resp.statusCode;
        await resp.drain();
        if (code >= 200 && code < 400) return true;
      } catch (_) {
        continue;
      } finally {
        client.close(force: true);
      }
    }
    return false;
  }
}
