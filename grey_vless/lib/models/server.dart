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

  String get transportLabel {
    final parts = <String>[protocol.toUpperCase()];
    final network = params['network'];
    if (network != null && network.isNotEmpty && network != 'tcp') {
      parts.add(network.toUpperCase());
    }
    final security = params['security'] ?? params['tls'];
    if (security != null && security.isNotEmpty && security != 'none') {
      parts.add(security.toUpperCase());
    }
    parts.add('JSON');
    return parts.join(' / ');
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'protocol': protocol,
        'host': host,
        'port': port,
        'rawLink': rawLink,
        'params': params,
        if (pingMs != null) 'pingMs': pingMs,
        if (pingError != null) 'pingError': pingError,
      };

  factory VpnServer.fromJson(Map<String, dynamic> json) {
    final paramsRaw = json['params'];
    return VpnServer(
      name: json['name'] as String? ?? 'Server',
      protocol: json['protocol'] as String? ?? 'vless',
      host: json['host'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 443,
      rawLink: json['rawLink'] as String? ?? '',
      params: paramsRaw is Map
          ? paramsRaw.map((k, v) => MapEntry(k.toString(), v.toString()))
          : const {},
      pingMs: (json['pingMs'] as num?)?.toInt(),
      pingError: json['pingError'] as String?,
    );
  }
}
