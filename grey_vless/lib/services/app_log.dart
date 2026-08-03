import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum AppLogLevel { debug, info, warn, error }

class AppLogLine {
  AppLogLine({
    required this.time,
    required this.level,
    required this.tag,
    required this.message,
  });

  final DateTime time;
  final AppLogLevel level;
  final String tag;
  final String message;

  String get timeStr {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    final ms = time.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  String get levelStr => switch (level) {
        AppLogLevel.debug => 'DBG',
        AppLogLevel.info => 'INF',
        AppLogLevel.warn => 'WRN',
        AppLogLevel.error => 'ERR',
      };

  @override
  String toString() => '[$timeStr] [$levelStr] [$tag] $message';
}

/// Кольцевой буфер логов приложения + sing-box для вкладки «Терминал».
class AppLog {
  AppLog._();
  static final AppLog instance = AppLog._();

  static const _maxLines = 800;
  final Queue<AppLogLine> _lines = Queue<AppLogLine>();
  final _controller = StreamController<AppLogLine>.broadcast();

  Stream<AppLogLine> get stream => _controller.stream;
  List<AppLogLine> get lines => List.unmodifiable(_lines);

  void clear() {
    _lines.clear();
    info('log', '— буфер очищен —');
  }

  String dump() => _lines.map((e) => e.toString()).join('\n');

  void debug(String tag, String message) => _add(AppLogLevel.debug, tag, message);
  void info(String tag, String message) => _add(AppLogLevel.info, tag, message);
  void warn(String tag, String message) => _add(AppLogLevel.warn, tag, message);
  void error(String tag, String message) => _add(AppLogLevel.error, tag, message);

  void _add(AppLogLevel level, String tag, String message) {
    final cleaned = message.replaceAll('\r', '').trimRight();
    if (cleaned.isEmpty) return;
    // Разбиваем многострочный вывод sing-box на отдельные строки.
    for (final part in cleaned.split('\n')) {
      final msg = part.trimRight();
      if (msg.isEmpty) continue;
      final line = AppLogLine(
        time: DateTime.now(),
        level: level,
        tag: tag,
        message: msg,
      );
      _lines.addLast(line);
      while (_lines.length > _maxLines) {
        _lines.removeFirst();
      }
      if (!_controller.isClosed) {
        _controller.add(line);
      }
      if (kDebugMode) {
        debugPrint(line.toString());
      }
    }
  }

  /// Сырой stdout/stderr ядра.
  void fromBytes(String tag, List<int> data) {
    try {
      final text = String.fromCharCodes(data);
      info(tag, text);
    } catch (_) {}
  }

  void exception(String tag, Object e, [StackTrace? st]) {
    error(tag, e.toString());
    if (st != null && kDebugMode) {
      debug(tag, st.toString().split('\n').take(6).join(' | '));
    }
  }

  Future<void> writeSnapshotHeader({
    required String version,
    required String tunnelMode,
    required bool connected,
    required bool elevated,
  }) async {
    info('sys', 'Grey vless $version');
    info('sys', 'OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    info('sys', 'tunnel=$tunnelMode connected=$connected elevated=$elevated');
  }
}
