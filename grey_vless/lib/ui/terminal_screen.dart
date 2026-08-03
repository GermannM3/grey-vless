import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../platform/android_native.dart';
import '../platform/windows_elevation.dart';
import '../services/app_log.dart';
import '../services/singbox_config.dart';
import '../state/app_state.dart';
import 'app_theme.dart';

/// Системный терминал: живые логи приложения и ядра.
class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final _scroll = ScrollController();
  final _filter = TextEditingController();
  StreamSubscription<AppLogLine>? _sub;
  bool _autoScroll = true;
  bool _onlyErrors = false;
  int _rev = 0;

  @override
  void initState() {
    super.initState();
    _sub = AppLog.instance.stream.listen((_) {
      if (!mounted) return;
      setState(() => _rev++);
      if (_autoScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scroll.hasClients) return;
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _dumpStatus());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    _filter.dispose();
    super.dispose();
  }

  Future<void> _dumpStatus() async {
    final state = context.read<AppState>();
    final info = await PackageInfo.fromPlatform();
    final elevated = Platform.isWindows ? await WindowsElevation.isElevated() : true;
    await AppLog.instance.writeSnapshotHeader(
      version: '${info.version}+${info.buildNumber}',
      tunnelMode: state.tunnelMode.name,
      connected: state.connection.isConnected,
      elevated: elevated,
    );
    AppLog.instance.info('sys', 'proxy 127.0.0.1:${SingboxConfigBuilder.localPort}');
    if (Platform.isAndroid) {
      try {
        final vpn = await AndroidNative.isVpnActive();
        final proxy = await AndroidNative.singboxIsRunning();
        final other = await AndroidNative.isOtherVpnActive();
        AppLog.instance.info('android', 'vpnActive=$vpn proxyRunning=$proxy otherVpn=$other');
        final last = await AndroidNative.singboxLastLog();
        if (last.isNotEmpty) {
          AppLog.instance.info('sing-box', '--- last native log ---\n$last');
        }
      } catch (e) {
        AppLog.instance.exception('android', e);
      }
    }
    // Порт
    try {
      final s = await Socket.connect(
        '127.0.0.1',
        SingboxConfigBuilder.localPort,
        timeout: const Duration(milliseconds: 400),
      );
      s.destroy();
      AppLog.instance.info('net', 'порт ${SingboxConfigBuilder.localPort}: открыт');
    } catch (_) {
      AppLog.instance.warn('net', 'порт ${SingboxConfigBuilder.localPort}: закрыт');
    }
  }

  List<AppLogLine> get _visible {
    final q = _filter.text.trim().toLowerCase();
    return AppLog.instance.lines.where((l) {
      if (_onlyErrors && l.level != AppLogLevel.error && l.level != AppLogLevel.warn) {
        return false;
      }
      if (q.isEmpty) return true;
      return l.toString().toLowerCase().contains(q);
    }).toList();
  }

  Color _color(AppLogLevel level) => switch (level) {
        AppLogLevel.debug => AppTheme.textMuted,
        AppLogLevel.info => const Color(0xFFA7F3D0),
        AppLogLevel.warn => const Color(0xFFFDE68A),
        AppLogLevel.error => const Color(0xFFFCA5A5),
      };

  Future<void> _copyAll() async {
    final text = _visible.map((e) => e.toString()).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Лог скопирован')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = _visible;
    // ignore: unused_local_variable
    final _ = _rev;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1A),
      appBar: AppBar(
        title: const Text('Терминал'),
        backgroundColor: const Color(0xFF0A0F1A),
        actions: [
          IconButton(
            tooltip: _autoScroll ? 'Автопрокрутка вкл' : 'Автопрокрутка выкл',
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
            icon: Icon(
              _autoScroll ? Icons.vertical_align_bottom : Icons.vertical_align_center,
              color: _autoScroll ? AppTheme.accentGlow : AppTheme.textMuted,
            ),
          ),
          IconButton(
            tooltip: 'Только ошибки',
            onPressed: () => setState(() => _onlyErrors = !_onlyErrors),
            icon: Icon(
              Icons.error_outline,
              color: _onlyErrors ? Colors.orangeAccent : AppTheme.textMuted,
            ),
          ),
          IconButton(
            tooltip: 'Обновить статус',
            onPressed: _dumpStatus,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Копировать',
            onPressed: _copyAll,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: 'Очистить',
            onPressed: () {
              AppLog.instance.clear();
              setState(() {});
            },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _filter,
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 13, color: AppTheme.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Фильтр…',
                hintStyle: const TextStyle(color: AppTheme.textMuted),
                prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.textMuted),
                filled: true,
                fillColor: const Color(0xFF121A2B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: lines.isEmpty
                ? const Center(
                    child: Text(
                      'Пока пусто — подключись или обнови статус',
                      style: TextStyle(color: AppTheme.textMuted),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
                    itemCount: lines.length,
                    itemBuilder: (ctx, i) {
                      final line = lines[i];
                      return SelectableText(
                        line.toString(),
                        style: TextStyle(
                          fontFamily: 'Consolas',
                          fontFamilyFallback: const ['Courier New', 'monospace'],
                          fontSize: 11.5,
                          height: 1.35,
                          color: _color(line.level),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Text(
                '${lines.length} строк · ${_autoScroll ? "follow" : "paused"}',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
