import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'grey_sense_service.dart';

enum AiBackend { local, ollama, huggingFace }

/// Единая точка AI: локальные правила, Ollama (ПК), Hugging Face (облако).
class AiAdvisor {
  static const _kBackend = 'ai_backend';
  static const _kOllamaUrl = 'ollama_url';
  static const _kOllamaModel = 'ollama_model';
  static const _kHfToken = 'grey_sense_hf_token';
  static const _kHfModel = 'grey_sense_hf_model';

  static const defaultOllamaUrl = 'http://127.0.0.1:11434';
  static const defaultOllamaModel = 'llama3.2';

  Future<AiBackend> getBackend() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kBackend) ?? 'local';
    return AiBackend.values.firstWhere(
      (b) => b.name == raw,
      orElse: () => AiBackend.local,
    );
  }

  Future<void> setBackend(AiBackend backend) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBackend, backend.name);
  }

  Future<String> getOllamaUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kOllamaUrl) ?? defaultOllamaUrl;
  }

  Future<String> getOllamaModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kOllamaModel) ?? defaultOllamaModel;
  }

  Future<void> setOllamaConfig({String? url, String? model}) async {
    final prefs = await SharedPreferences.getInstance();
    if (url != null) await prefs.setString(_kOllamaUrl, url.trim());
    if (model != null) await prefs.setString(_kOllamaModel, model.trim());
  }

  Future<String?> getHfToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kHfToken);
  }

  Future<String> getHfModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kHfModel) ?? GreySenseService.defaultHfModel;
  }

  Future<void> setHfToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.trim().isEmpty) {
      await prefs.remove(_kHfToken);
    } else {
      await prefs.setString(_kHfToken, token.trim());
    }
  }

  Future<void> setHfModel(String? model) async {
    final prefs = await SharedPreferences.getInstance();
    final value = model?.trim() ?? '';
    if (value.isEmpty) {
      await prefs.remove(_kHfModel);
    } else {
      await prefs.setString(_kHfModel, value);
    }
  }

  Future<bool> ollamaAvailable() async {
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) return false;
    try {
      final url = await getOllamaUrl();
      final r = await http.get(Uri.parse('$url/api/tags')).timeout(const Duration(seconds: 2));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<String?> advise(String prompt) async {
    final backend = await getBackend();
    switch (backend) {
      case AiBackend.local:
        return null;
      case AiBackend.ollama:
        return _ollama(prompt);
      case AiBackend.huggingFace:
        return _hf(prompt);
    }
  }

  Future<String?> _ollama(String prompt) async {
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) return null;
    try {
      final base = await getOllamaUrl();
      final model = await getOllamaModel();
      final response = await http
          .post(
            Uri.parse('$base/api/generate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'model': model,
              'prompt': 'Ответь кратко по-русски (1-2 предложения): $prompt',
              'stream': false,
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['response']?.toString().trim();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _hf(String prompt) async {
    final token = await getHfToken();
    if (token == null || token.trim().isEmpty) return null;
    final model = await getHfModel();
    try {
      final response = await http
          .post(
            Uri.parse('https://router.huggingface.co/hf-inference/models/$model'),
            headers: {
              'Authorization': 'Bearer ${token.trim()}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'inputs': 'VPN совет на русском, коротко: $prompt',
              'parameters': {'max_new_tokens': 120},
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      if (data is List && data.isNotEmpty) {
        return data.first['generated_text']?.toString().trim();
      }
      if (data is Map) {
        return data['generated_text']?.toString().trim();
      }
    } catch (_) {}
    return null;
  }

  /// Извлекает vless/vmess/trojan/ss ссылки из «грязного» текста.
  Future<List<String>> extractVpnLinks(String raw) async {
    final found = <String>{};
    final pattern = RegExp(
      r'(vless|vmess|trojan|ss)://[^\s"<>]+(?:#[^\s"<>]*)?',
      caseSensitive: false,
    );
    for (final m in pattern.allMatches(raw)) {
      found.add(m.group(0)!);
    }

    if (found.isNotEmpty) return found.toList();

    final backend = await getBackend();
    if (backend == AiBackend.local) return [];

    final ai = await advise(
      'Из текста выпиши только VPN-ссылки vless:// vmess:// trojan:// ss:// через пробел, без пояснений:\n${raw.substring(0, raw.length.clamp(0, 2000))}',
    );
    if (ai == null || ai.isEmpty) return [];

    for (final m in pattern.allMatches(ai)) {
      found.add(m.group(0)!);
    }
    return found.toList();
  }
}
