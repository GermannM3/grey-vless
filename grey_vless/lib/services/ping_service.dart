import 'dart:async';
import 'dart:io';

import '../models/server.dart';

class PingService {
  static const _attempts = 2;

  /// TCP до порта сервера (не полный путь через VPN).
  static Future<int> tcpPing(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
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

    final samples = <int>[];
    for (var i = 0; i < _attempts; i++) {
      final stopwatch = Stopwatch()..start();
      Socket? socket;
      try {
        socket = await Socket.connect(address, port, timeout: timeout);
        stopwatch.stop();
        if (stopwatch.elapsedMilliseconds > 0) {
          samples.add(stopwatch.elapsedMilliseconds);
        }
      } finally {
        await socket?.close();
      }
      if (i + 1 < _attempts) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }

    if (samples.isEmpty) {
      throw SocketException('нет TCP до $host:$port');
    }
    samples.sort();
    return samples.first;
  }

  static Future<void> pingAll(List<VpnServer> servers, {bool sequential = true}) async {
    Future<void> pingOne(VpnServer server) async {
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
    }

    if (sequential || Platform.isAndroid) {
      for (final server in servers) {
        await pingOne(server);
      }
    } else {
      await Future.wait(servers.map(pingOne));
    }
  }

  static VpnServer? fastest(List<VpnServer> servers) {
    final reachable = servers.where((s) => s.pingMs != null).toList();
    if (reachable.isEmpty) return null;
    reachable.sort((a, b) => (a.pingMs ?? 999999).compareTo(b.pingMs ?? 999999));
    return reachable.first;
  }
}
