import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/server.dart';
import '../services/connection_service.dart';
import '../services/ping_service.dart';
import '../services/subscription.dart';
import '../services/update_service.dart';
import '../state/app_state.dart';
import 'app_theme.dart';
import 'country_flag.dart';
import 'update_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _busy = false;
  bool _checkingUpdate = false;
  bool _pinging = false;
  bool _serversHidden = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates(silent: true));
  }

  Future<void> _checkForUpdates({bool silent = false}) async {
    if (_checkingUpdate) return;
    _checkingUpdate = true;
    try {
      final info = await UpdateService.checkForUpdate();
      if (info != null && mounted) {
        await showUpdateDialog(context, info);
      } else if (!silent && mounted) {
        _snack('Установлена последняя версия');
      }
    } catch (_) {
      if (!silent && mounted) _snack('Не удалось проверить обновления');
    } finally {
      _checkingUpdate = false;
    }
  }

  void _snack(String text, {Color? bg}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: bg),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) _snack(_shortError(e), bg: Colors.red.shade800);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _shortError(Object e) {
    final s = e.toString();
    if (s.startsWith('Exception: ')) return s.substring(11);
    return s;
  }

  VpnServer? _selectedServer(AppState state) {
    if (state.selectedIndex != null && state.selectedIndex! < state.servers.length) {
      return state.servers[state.selectedIndex!];
    }
    if (state.servers.isNotEmpty) return state.servers.first;
    return null;
  }

  Future<void> _loadSubscription(AppState state, String source) async {
    final servers = await SubscriptionService.parseSource(source);
    await state.setSubscription(source.trim());
    await state.setServers(servers);
    if (servers.isNotEmpty) {
      await state.setSelectedIndex(0);
    }
    if (state.autoConnect && servers.isNotEmpty) {
      await state.connection.connectFastest(servers);
      await state.persistServers();
    }
  }

  Future<void> _refreshSubscription(AppState state) async {
    if (state.subscriptionUrl.trim().isEmpty) {
      throw Exception('Нет сохранённой подписки');
    }
    await _loadSubscription(state, state.subscriptionUrl);
  }

  void _showAddSheet(AppState state) {
    final controller = TextEditingController(text: state.subscriptionUrl);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Добавить подписку', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'https://... или vless://...',
                  filled: true,
                  fillColor: AppTheme.cardLight,
                  border: OutlineInputBorder(borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text?.trim().isNotEmpty == true) {
                        controller.text = data!.text!.trim();
                      }
                    },
                    child: const Text('Вставить'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            Navigator.pop(ctx);
                            await _run(() => _loadSubscription(state, controller.text));
                          },
                    child: const Text('Загрузить'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSettings(AppState state) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Настройки', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            SwitchListTile(
              title: Text(Platform.isAndroid ? 'TUN — полный VPN' : 'TUN (полный VPN)'),
              subtitle: Text(
                Platform.isAndroid
                    ? 'Весь трафик через VPN. Без TUN — только проверка серверов.'
                    : 'Весь трафик через VPN',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              value: state.tunMode,
              onChanged: _busy ? null : (v) => state.setTunMode(v),
            ),
            SwitchListTile(
              title: const Text('Автоподключение к самому быстрому'),
              value: state.autoConnect,
              onChanged: _busy ? null : (v) => state.setAutoConnect(v),
            ),
            ListTile(
              leading: const Icon(Icons.system_update),
              title: const Text('Проверить обновления'),
              onTap: () {
                Navigator.pop(ctx);
                _checkForUpdates();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pingAll(AppState state) async {
    if (state.servers.isEmpty) return;
    setState(() => _pinging = true);
    try {
      await PingService.pingAll(state.servers);
      await state.persistServers();
      state.refresh();
    } finally {
      if (mounted) setState(() => _pinging = false);
    }
  }

  Future<void> _connectServer(AppState state, int index) async {
    await state.setSelectedIndex(index);
    await state.connection.connect(state.servers[index]);
    state.refresh();
  }

  Future<void> _toggleConnection(AppState state) async {
    final conn = state.connection;
    if (conn.isConnected) {
      await conn.disconnect();
      state.refresh();
      return;
    }
    final server = _selectedServer(state);
    if (server == null) throw Exception('Выберите сервер');
    await state.connection.connect(server);
    state.refresh();
  }

  String _statusText(ConnectionService conn) {
    if (!conn.isConnected) return 'Не подключено';
    final name = conn.connectedServer?.name ?? '';
    if (conn.isProxyOnly) return 'Прокси: $name';
    if (conn.isFullVpn) return 'VPN: $name';
    return 'Подключено: $name';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final conn = state.connection;
    final connected = conn.isConnected;

    if (!state.loaded) {
      return DecoratedBox(
        decoration: AppTheme.screenGradient,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(child: CircularProgressIndicator(color: AppTheme.accent)),
        ),
      );
    }

    return DecoratedBox(
      decoration: AppTheme.screenGradient,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Настройки',
                      onPressed: () => _showSettings(state),
                      icon: const Icon(Icons.settings_outlined),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Добавить подписку',
                      onPressed: () => _showAddSheet(state),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _ConnectOrb(
                busy: _busy,
                pinging: _pinging,
                connected: connected,
                statusText: _statusText(conn),
                onTap: () => _run(() => _toggleConnection(state)),
                onLongPress: state.servers.isEmpty ? null : () => _pingAll(state),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      _pinging ? 'Проверка пинга…' : 'Проверка пинга',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                    ),
                    const Spacer(),
                    if (state.servers.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() => _serversHidden = !_serversHidden),
                        child: Text(_serversHidden ? 'Показать все' : 'Скрыть все'),
                      ),
                  ],
                ),
              ),
              if (state.subscriptionUrl.isNotEmpty || state.servers.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: _SubscriptionCard(
                    name: state.subscriptionName,
                    serverCount: state.servers.length,
                    busy: _busy,
                    onRefresh: () => _run(() => _refreshSubscription(state)),
                  ),
                ),
              Expanded(
                child: state.servers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cloud_off_outlined, size: 48, color: AppTheme.textMuted.withValues(alpha: 0.5)),
                            const SizedBox(height: 12),
                            const Text('Добавьте подписку', style: TextStyle(color: AppTheme.textMuted)),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: () => _showAddSheet(state),
                              icon: const Icon(Icons.add),
                              label: const Text('Добавить'),
                            ),
                          ],
                        ),
                      )
                    : _serversHidden
                        ? const SizedBox.shrink()
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: state.servers.length,
                            itemBuilder: (context, index) {
                              final server = state.servers[index];
                              final selected = state.selectedIndex == index;
                              final isConnected = conn.connectedServer == server;
                              return _ServerRow(
                                server: server,
                                selected: selected,
                                connected: isConnected,
                                busy: _busy,
                                onTap: () => state.setSelectedIndex(index),
                                onConnect: () => _run(() => _connectServer(state, index)),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectOrb extends StatelessWidget {
  const _ConnectOrb({
    required this.busy,
    required this.pinging,
    required this.connected,
    required this.statusText,
    required this.onTap,
    this.onLongPress,
  });

  final bool busy;
  final bool pinging;
  final bool connected;
  final String statusText;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final label = pinging
        ? 'ПРОВЕРКА\nПИНГА'
        : connected
            ? 'ОТКЛЮЧИТЬ'
            : 'ПОДКЛЮЧИТЬ';

    return GestureDetector(
      onTap: busy ? null : onTap,
      onLongPress: busy ? null : onLongPress,
      child: Column(
        children: [
          SizedBox(
            width: 180,
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (connected ? AppTheme.statusOk : AppTheme.accent).withValues(alpha: 0.35),
                        blurRadius: 40,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: connected
                          ? [const Color(0xFF34D399), const Color(0xFF059669)]
                          : [AppTheme.accentGlow, AppTheme.accent, const Color(0xFF1D4ED8)],
                    ),
                  ),
                  child: busy || pinging
                      ? const Center(child: CircularProgressIndicator(color: Colors.white))
                      : Center(
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              height: 1.2,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(statusText, style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
        ],
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({
    required this.name,
    required this.serverCount,
    required this.busy,
    required this.onRefresh,
  });

  final String name;
  final int serverCount;
  final bool busy;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  '$serverCount серверов · сохранено локально',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Обновить подписку',
            onPressed: busy ? null : onRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({
    required this.server,
    required this.selected,
    required this.connected,
    required this.busy,
    required this.onTap,
    required this.onConnect,
  });

  final VpnServer server;
  final bool selected;
  final bool connected;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onConnect;

  String _pingText() {
    if (server.pingError != null) return server.pingError!;
    if (server.pingMs != null) return '${server.pingMs}мс';
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final flag = countryFlagFor(server.name);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: connected
            ? AppTheme.cardLight.withValues(alpha: 0.95)
            : selected
                ? AppTheme.cardLight
                : AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: busy ? null : onTap,
          onDoubleTap: busy ? null : onConnect,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Text(flag, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        server.name,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        server.transportLabel,
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Text(_pingText(), style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                const SizedBox(width: 6),
                Icon(
                  connected ? Icons.check_circle : Icons.chevron_right,
                  color: connected ? AppTheme.statusOk : AppTheme.textMuted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
