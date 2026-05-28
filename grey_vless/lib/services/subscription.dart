import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/server.dart';
import 'parser.dart';

class SubscriptionService {
  static Future<List<VpnServer>> parseSource(String source) async {
    final text = await _loadText(source.trim());
    final servers = <VpnServer>[];
    final seen = <String>{};

    for (final line in text.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      try {
        final server = LinkParser.parse(trimmed);
        final key = '${server.protocol}|${server.host}|${server.port}|${server.rawLink}';
        if (seen.add(key)) servers.add(server);
      } catch (_) {
        continue;
      }
    }

    if (servers.isEmpty) {
      throw Exception('Серверы не найдены. Проверьте ссылку или формат.');
    }
    return servers;
  }

  static Future<String> _loadText(String source) async {
    if (source.isEmpty) throw Exception('Пустая ссылка или текст');
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(source)) {
      try {
        final response = await http.get(
          Uri.parse(source),
          headers: {'User-Agent': 'GreyVless/1.0'},
        ).timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) {
          throw Exception('Не удалось загрузить подписку: HTTP ${response.statusCode}');
        }
        return _decodeMaybeBase64(response.body);
      } on SocketException catch (e) {
        throw Exception(
          'Нет доступа к серверу подписки (${e.message}). '
          'Проверьте интернет, отключите Private DNS или вставьте ссылки vless:// вручную.',
        );
      }
    }
    return _decodeMaybeBase64(source);
  }

  static String _decodeMaybeBase64(String text) {
    final trimmed = text.trim();
    if (trimmed.contains('://')) return trimmed;
    try {
      final padded = trimmed + '=' * ((4 - trimmed.length % 4) % 4);
      final decoded = utf8.decode(base64.decode(padded));
      if (decoded.contains('://')) return decoded;
    } catch (_) {}
    return trimmed;
  }
}
