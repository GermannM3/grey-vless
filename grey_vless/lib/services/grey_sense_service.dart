import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import 'ping_service.dart';

/// Grey Sense — локальный «AI»: скоринг серверов, история стабильности,
/// опциональные подсказки через Hugging Face Inference API.
class GreySenseService {
  static const _kStats = 'grey_sense_server_stats';
  static const _kHfToken = 'grey_sense_hf_token';

  Map<String, _ServerStats> _stats = {};

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kStats);
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _stats = map.map((k, v) => MapEntry(k, _ServerStats.fromJson(v as Map<String, dynamic>)));
    } catch (_) {
      _stats = {};
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_stats.map((k, v) => MapEntry(k, v.toJson())));
    await prefs.setString(_kStats, encoded);
  }

  String _key(VpnServer s) => '${s.protocol}|${s.host}|${s.port}';

  Future<void> recordSuccess(VpnServer server) async {
    final st = _stats[_key(server)] ?? _ServerStats();
    st.successes++;
    st.lastOk = DateTime.now().millisecondsSinceEpoch;
    _stats[_key(server)] = st;
    await _save();
  }

  Future<void> recordFailure(VpnServer server) async {
    final st = _stats[_key(server)] ?? _ServerStats();
    st.failures++;
    _stats[_key(server)] = st;
    await _save();
  }

  double score(VpnServer server) {
    final st = _stats[_key(server)];
    final ping = server.pingMs ?? 800;
    final pingScore = (600 - ping.clamp(0, 600)) / 600;
    final success = st?.successes ?? 0;
    final fail = st?.failures ?? 0;
    final reliability = success + fail == 0 ? 0.5 : success / (success + fail);
    return pingScore * 0.55 + reliability * 0.45;
  }

  VpnServer? recommend(List<VpnServer> servers) {
    if (servers.isEmpty) return null;
    VpnServer? best;
    var bestScore = -1.0;
    for (final s in servers) {
      final sc = score(s);
      if (sc > bestScore) {
        bestScore = sc;
        best = s;
      }
    }
    return best;
  }

  Future<VpnServer?> pickForAutoReconnect(List<VpnServer> servers, VpnServer current) async {
    if (servers.isEmpty) return null;
    await PingService.pingAll(servers, sequential: true);
    final rec = recommend(servers);
    if (rec != null && score(rec) > score(current) + 0.15) return rec;
    return current;
  }

  String explainLocally(String error) {
    final e = error.toLowerCase();
    if (e.contains('permission denied')) {
      return 'Android заблокировал sing-box. Переустановите последний APK из релиза.';
    }
    if (e.contains('dns')) {
      return 'Не резолвится DNS. Отключите Private DNS в настройках Android или смените сервер.';
    }
    if (e.contains('timeout') || e.contains('нет связи')) {
      return 'Сервер не отвечает. Grey Sense попробует другой узел при авто-переподключении.';
    }
    if (e.contains('конфиг') || e.contains('invalid')) {
      return 'Конфиг сервера битый или устарел. Обновите подписку (кнопка ↻).';
    }
    if (e.contains('vpn') || e.contains('tun')) {
      return 'Проблема с TUN. Выключите TUN в настройках или подтвердите разрешение VPN.';
    }
    return 'Сеть нестабильна — включите авто-переподключение в Grey Sense.';
  }

  Future<String?> hfHint({
    required String prompt,
    required String? token,
  }) async {
    if (token == null || token.trim().isEmpty) return null;
    try {
      final response = await http
          .post(
            Uri.parse('https://router.huggingface.co/hf-inference/models/google/flan-t5-base'),
            headers: {
              'Authorization': 'Bearer ${token.trim()}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'inputs': 'VPN совет на русском, коротко: $prompt',
              'parameters': {'max_new_tokens': 100},
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      if (data is List && data.isNotEmpty) {
        return data.first['generated_text']?.toString().trim();
      }
      if (data is Map) {
        return data['generated_text']?.toString().trim() ?? data[0]?.toString();
      }
    } catch (_) {}
    return null;
  }

  Future<String?> getHfToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kHfToken);
  }

  Future<void> setHfToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.trim().isEmpty) {
      await prefs.remove(_kHfToken);
    } else {
      await prefs.setString(_kHfToken, token.trim());
    }
  }
}

class _ServerStats {
  int successes = 0;
  int failures = 0;
  int lastOk = 0;

  Map<String, dynamic> toJson() => {
        'successes': successes,
        'failures': failures,
        'lastOk': lastOk,
      };

  factory _ServerStats.fromJson(Map<String, dynamic> j) => _ServerStats()
    ..successes = (j['successes'] as num?)?.toInt() ?? 0
    ..failures = (j['failures'] as num?)?.toInt() ?? 0
    ..lastOk = (j['lastOk'] as num?)?.toInt() ?? 0;
}
