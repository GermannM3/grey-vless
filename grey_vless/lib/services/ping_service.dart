import 'dart:async';
import 'dart:io';

import '../models/server.dart';

class PingService {
  /// Один быстрый TCP-замер — на Windows Socket.connect часто игнорирует свой timeout.
  static Future<int> tcpPing(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    return _tcpPingBody(host, port, timeout).timeout(
      timeout + const Duration(milliseconds: 500),
      onTimeout: () => throw SocketException('timeout: $host:$port'),
    );
  }

  static Future<int> _tcpPingBody(String host, int port, Duration timeout) async {
    InternetAddress address;
    try {
      final resolved = await InternetAddress.lookup(host).timeout(timeout);
      if (resolved.isEmpty) {
        throw SocketException('DNS: $host');
      }
      address = resolved.firstWhere(
        (a) => a.type == InternetAddressType.IPv4,
        orElse: () => resolved.first,
      );
    } on SocketException {
      rethrow;
    } on TimeoutException {
      throw SocketException('DNS timeout: $host');
    }

    Socket? socket;
    final stopwatch = Stopwatch()..start();
    try {
      socket = await Socket.connect(address, port, timeout: timeout).timeout(
        timeout,
        onTimeout: () => throw TimeoutException('connect'),
      );
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds.clamp(1, 99999);
    } on TimeoutException {
      throw SocketException('timeout: $host:$port');
    } finally {
      // close() на Windows может висеть вечно — только destroy.
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  /// Пинг списка с лимитом параллелизма; [onProgress] — после каждого сервера (для UI).
  static Future<void> pingAll(
    List<VpnServer> servers, {
    int concurrency = 6,
    void Function(VpnServer server)? onProgress,
  }) async {
    if (servers.isEmpty) return;

    // На Android слишком много параллельных сокетов ломает OEM — держим низкий лимит.
    final limit = Platform.isAndroid ? 3 : concurrency;
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= servers.length) return;
        final server = servers[i];
        try {
          server.pingMs = await tcpPing(server.host, server.port);
          server.pingError = null;
        } on SocketException catch (e) {
          server.pingMs = null;
          server.pingError = e.message.contains('DNS') ? 'DNS' : 'нет связи';
        } catch (_) {
          server.pingMs = null;
          server.pingError = 'нет связи';
        }
        onProgress?.call(server);
      }
    }

    final n = servers.length < limit ? servers.length : limit;
    await Future.wait(List.generate(n, (_) => worker()));
  }

  static VpnServer? fastest(List<VpnServer> servers) {
    final reachable = servers.where((s) => s.pingMs != null).toList();
    if (reachable.isEmpty) return null;
    reachable.sort((a, b) => (a.pingMs ?? 999999).compareTo(b.pingMs ?? 999999));
    return reachable.first;
  }
}
