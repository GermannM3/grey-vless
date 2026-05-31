import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/server.dart';
import '../services/connection_service.dart';
import '../services/ping_service.dart';
import '../services/subscription.dart';
import '../state/app_state.dart';
import 'app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_shortError(e)),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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

  Future<void> _connectSelected(AppState state) async {
    final server = _selectedServer(state);
    if (server == null) {
      throw Exception('Выберите сервер в списке');
    }
    await state.connection.connect(server);
    state.refresh();
    if (!mounted) return;
    final conn = state.connection;
    if (conn.isFullVpn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('VPN включён — в статус-баре должен быть значок VPN.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (conn.isProxyOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Запущен только локальный прокси. Для интернета на телефоне включите TUN.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _statusLine(ConnectionService conn) {
    if (!conn.isConnected) return 'Не подключено';
    final name = conn.connectedServer?.name ?? '';
    if (conn.isProxyOnly) {
      return 'Прокси (не VPN): $name';
    }
    if (conn.isFullVpn) {
      return 'VPN: $name';
    }
    return 'Подключено: $name';
  }

  Color _statusColor(ConnectionService conn) {
    if (!conn.isConnected) return AppTheme.statusOff;
    if (conn.isProxyOnly) return const Color(0xFFB45309);
    return AppTheme.statusOk;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final conn = state.connection;
    final theme = Theme.of(context);
    final canConnect = !_busy && state.servers.isNotEmpty && !conn.isConnected;
    final canDisconnect = !_busy && conn.isConnected;

    return Scaffold(
      appBar: AppBar(title: const Text('Grey vless')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ссылка на подписку или список серверов (vless://, vmess://, trojan://, ss://)',
                style: theme.textTheme.bodySmall?.copyWith(color: AppTheme.hint),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  hintText: 'https://... или vless://...',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            final data = await Clipboard.getData('text/plain');
                            if (data?.text?.trim().isNotEmpty == true) {
                              _controller.text = data!.text!.trim();
                            }
                          },
                    child: const Text('Вставить'),
                  ),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              final servers = await SubscriptionService.parseSource(_controller.text);
                              state.setServers(servers);
                              if (state.servers.isNotEmpty) {
                                state.selectedIndex = 0;
                              }
                              if (state.autoConnect) {
                                await conn.connectFastest(servers);
                                state.refresh();
                              }
                            }),
                    child: const Text('Загрузить'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  FilterChip(
                    label: Text(Platform.isAndroid ? 'TUN — полный VPN' : 'TUN (полный VPN)'),
                    selected: state.tunMode,
                    onSelected: (v) {
                      state.tunMode = v;
                      conn.tunMode = v;
                      state.refresh();
                    },
                  ),
                  FilterChip(
                    label: const Text('Автоподключение'),
                    selected: state.autoConnect,
                    onSelected: (v) {
                      state.autoConnect = v;
                      state.refresh();
                    },
                  ),
                ],
              ),
              if (Platform.isAndroid)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    state.tunMode
                        ? 'TUN: весь трафик через VPN (подтвердите разрешение при подключении).'
                        : 'Без TUN: только проверка серверов — интернет телефона через VPN не идёт.',
                    style: theme.textTheme.bodySmall?.copyWith(color: AppTheme.hint, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                _statusLine(conn),
                style: TextStyle(
                  color: _statusColor(conn),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy || state.servers.isEmpty
                        ? null
                        : () => _run(() async {
                              await PingService.pingAll(state.servers);
                              state.refresh();
                            }),
                    child: const Text('Пинг (TCP)'),
                  ),
                  OutlinedButton(
                    onPressed: _busy || state.servers.isEmpty
                        ? null
                        : () => _run(() async {
                              await conn.connectFastest(state.servers);
                              state.refresh();
                            }),
                    child: const Text('Самый быстрый'),
                  ),
                  FilledButton(
                    onPressed: canConnect ? () => _run(() => _connectSelected(state)) : null,
                    child: const Text('Подключить'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: canDisconnect
                        ? () => _run(() async {
                              await conn.disconnect();
                              state.refresh();
                            })
                        : null,
                    child: const Text('Отключить'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: state.servers.isEmpty
                    ? Center(
                        child: Text(
                          'Загрузите подписку',
                          style: theme.textTheme.bodyLarge?.copyWith(color: AppTheme.hint),
                        ),
                      )
                    : ListView.builder(
                        itemCount: state.servers.length,
                        itemBuilder: (context, index) {
                          final server = state.servers[index];
                          final selected = state.selectedIndex == index;
                          final connected = conn.connectedServer == server;
                          return _ServerTile(
                            server: server,
                            selected: selected,
                            connected: connected,
                            onTap: _busy
                                ? null
                                : () {
                                    state.selectedIndex = index;
                                    state.refresh();
                                  },
                            onConnect: _busy
                                ? null
                                : () => _run(() async {
                                      state.selectedIndex = index;
                                      await conn.connect(server);
                                      state.refresh();
                                    }),
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

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.server,
    required this.selected,
    required this.connected,
    this.onTap,
    this.onConnect,
  });

  final VpnServer server;
  final bool selected;
  final bool connected;
  final VoidCallback? onTap;
  final VoidCallback? onConnect;

  static String _pingText(VpnServer server) {
    if (server.pingError != null) return server.pingError!;
    if (server.pingMs != null) return 'TCP ${server.pingMs} ms';
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: connected
              ? AppTheme.statusOk
              : selected
                  ? theme.colorScheme.primary
                  : Colors.transparent,
          width: connected || selected ? 1.5 : 0,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        title: Text(server.name),
        subtitle: Text(
          '${server.address} · ${server.protocol.toUpperCase()} · ${_pingText(server)}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: connected
            ? Icon(Icons.check_circle, color: AppTheme.statusOk)
            : TextButton(
                onPressed: onConnect,
                child: const Text('Подключить'),
              ),
      ),
    );
  }
}
