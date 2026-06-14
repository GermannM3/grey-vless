import 'dart:async';
import 'dart:io';

import '../models/server.dart';
import '../platform/android_native.dart';
import '../platform/singbox_runner.dart';
import 'singbox_config.dart';

typedef ReconnectCallback = Future<void> Function(VpnServer server);

/// Следит за живостью туннеля и переподключается при обрыве.
class ConnectionWatchdog {
  ConnectionWatchdog(this._runner, this._reconnect);

  final SingboxRunner _runner;
  final ReconnectCallback _reconnect;

  Timer? _timer;
  VpnServer? _server;
  bool _reconnecting = false;
  int _failStreak = 0;

  bool get isActive => _timer != null;
  bool get isReconnecting => _reconnecting;
  int get failStreak => _failStreak;

  void start(VpnServer server) {
    _server = server;
    _failStreak = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _server = null;
    _failStreak = 0;
    _reconnecting = false;
  }

  Future<void> _tick() async {
    if (_reconnecting || _server == null) return;
    final ok = await _healthOk();
    if (ok) {
      _failStreak = 0;
      return;
    }
    _failStreak++;
    if (_failStreak < 3) return;

    _reconnecting = true;
    try {
      final server = _server!;
      await _reconnect(server);
      _failStreak = 0;
    } catch (_) {
      // следующий цикл попробует снова
    } finally {
      _reconnecting = false;
    }
  }

  Future<bool> _healthOk() async {
    if (!_runner.isRunning) return false;

    if (!await _localPortOpen()) return false;

    if (Platform.isAndroid) {
      final proxyAlive = await AndroidNative.singboxIsRunning();
      final vpnAlive = await AndroidNative.isVpnActive();
      if (!proxyAlive && !vpnAlive) return false;
    }

    return _internetProbe();
  }

  Future<bool> _localPortOpen() async {
    try {
      final socket = await Socket.connect(
        '127.0.0.1',
        SingboxConfigBuilder.localPort,
        timeout: const Duration(seconds: 3),
      );
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _internetProbe() async {
    const urls = [
      'https://connectivitycheck.gstatic.com/generate_204',
      'https://www.cloudflare.com/cdn-cgi/trace',
    ];
    for (final url in urls) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 6);
        final req = await client.getUrl(Uri.parse(url));
        final resp = await req.close();
        final code = resp.statusCode;
        await resp.drain();
        client.close();
        if (code >= 200 && code < 400) return true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }
}
