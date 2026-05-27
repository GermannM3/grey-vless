import 'dart:async';
import 'dart:io';

import '../models/server.dart';

class PingService {
  static Future<int> tcpPing(String host, int port, {Duration timeout = const Duration(seconds: 3)}) async {
    final stopwatch = Stopwatch()..start();
    final socket = await Socket.connect(host, port, timeout: timeout);
    await socket.close();
    stopwatch.stop();
    return stopwatch.elapsedMilliseconds;
  }

  static Future<void> pingAll(List<VpnServer> servers) async {
    await Future.wait(servers.map((server) async {
      try {
        server.pingMs = await tcpPing(server.host, server.port);
        server.pingError = null;
      } catch (_) {
        server.pingMs = null;
        server.pingError = 'нет связи';
      }
    }));
  }

  static VpnServer? fastest(List<VpnServer> servers) {
    final reachable = servers.where((s) => s.pingMs != null).toList();
    if (reachable.isEmpty) return null;
    reachable.sort((a, b) => (a.pingMs ?? 999999).compareTo(b.pingMs ?? 999999));
    return reachable.first;
  }
}
