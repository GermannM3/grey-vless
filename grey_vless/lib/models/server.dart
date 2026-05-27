class VpnServer {
  VpnServer({
    required this.name,
    required this.protocol,
    required this.host,
    required this.port,
    required this.rawLink,
    this.params = const {},
    this.pingMs,
    this.pingError,
  });

  final String name;
  final String protocol;
  final String host;
  final int port;
  final String rawLink;
  final Map<String, String> params;
  int? pingMs;
  String? pingError;

  String get address => '$host:$port';
}
