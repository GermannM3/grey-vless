import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/server.dart';
import 'parser.dart';

class SubscriptionService {
  static final _linkPattern = RegExp(
    r'(vless|vmess|trojan|ss)://[^\s"<>]+(?:#[^\s"<>]*)?',
    caseSensitive: false,
  );

  static Future<List<VpnServer>> parseSource(String source) async {
    final text = await _loadText(source.trim());
    final servers = <VpnServer>[];
    final seen = <String>{};

    for (final link in _extractLinks(text)) {
      try {
        final server = LinkParser.parse(link);
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

  static Iterable<String> _extractLinks(String text) {
    final fromRegex = _linkPattern.allMatches(text).map((m) => m.group(0)!);
    if (fromRegex.isNotEmpty) return fromRegex;

    final lines = <String>[];
    for (final line in text.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      lines.add(trimmed);
    }
    return lines;
  }

  static Future<String> _loadText(String source) async {
    if (source.isEmpty) throw Exception('Пустая ссылка или текст');
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(source)) {
      try {
        final response = await http.get(
          Uri.parse(source),
          headers: {'User-Agent': 'GreyVless/1.0'},
        ).timeout(const Duration(seconds: 25));
        if (response.statusCode != 200) {
          throw Exception('Не удалось загрузить подписку: HTTP ${response.statusCode}');
        }
        final body = response.bodyBytes;
        final asText = utf8.decode(body, allowMalformed: true);
        return _decodeMaybeBase64(asText.trim());
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

    final compact = trimmed.replaceAll(RegExp(r'\s+'), '');
    for (final candidate in [trimmed, compact]) {
      if (candidate.isEmpty) continue;
      try {
        final padded = candidate + '=' * ((4 - candidate.length % 4) % 4);
        final decoded = utf8.decode(base64.decode(padded), allowMalformed: true);
        if (decoded.contains('://')) return decoded;
      } catch (_) {}
    }
    return trimmed;
  }
}
