import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/server.dart';
import '../services/ping_service.dart';
import '../services/subscription.dart';
import '../state/app_state.dart';

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
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade800),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final conn = state.connection;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1D24),
      appBar: AppBar(
        backgroundColor: const Color(0xFF252A33),
        title: const Text('Grey vless', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'https://... или vless://...',
                hintStyle: TextStyle(color: Colors.grey.shade500),
                filled: true,
                fillColor: const Color(0xFF2E3440),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 10),
            Row(
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
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            final servers = await SubscriptionService.parseSource(_controller.text);
                            state.setServers(servers);
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
              spacing: 12,
              children: [
                FilterChip(
                  label: const Text('TUN (полный VPN)'),
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
            const SizedBox(height: 8),
            Text(
              conn.isConnected
                  ? 'Подключено: ${conn.connectedServer?.name ?? ""}'
                  : 'Не подключено',
              style: TextStyle(color: conn.isConnected ? Colors.greenAccent : Colors.grey.shade400),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton(
                  onPressed: _busy || state.servers.isEmpty
                      ? null
                      : () => _run(() async {
                            await PingService.pingAll(state.servers);
                            state.refresh();
                          }),
                  child: const Text('Пинг'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _busy || state.servers.isEmpty
                      ? null
                      : () => _run(() async {
                            await conn.connectFastest(state.servers);
                            state.refresh();
                          }),
                  child: const Text('Самый быстрый'),
                ),
                const Spacer(),
                if (conn.isConnected)
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red.shade800),
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              await conn.disconnect();
                              state.refresh();
                            }),
                    child: const Text('Отключить'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: state.servers.isEmpty
                  ? Center(child: Text('Загрузите подписку', style: TextStyle(color: Colors.grey.shade500)))
                  : ListView.builder(
                      itemCount: state.servers.length,
                      itemBuilder: (context, index) {
                        final server = state.servers[index];
                        final selected = conn.connectedServer == server;
                        return _ServerTile(
                          server: server,
                          selected: selected,
                          onConnect: _busy
                              ? null
                              : () => _run(() async {
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
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({required this.server, required this.selected, this.onConnect});

  final VpnServer server;
  final bool selected;
  final VoidCallback? onConnect;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: selected ? const Color(0xFF3A4A5C) : const Color(0xFF2A303A),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(server.name, style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          '${server.address} · ${server.protocol.toUpperCase()} · ${server.pingMs != null ? "${server.pingMs} ms" : "—"}',
          style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
        ),
        trailing: onConnect == null
            ? null
            : IconButton(
                icon: Icon(selected ? Icons.link : Icons.link_off, color: Colors.blueAccent),
                onPressed: onConnect,
              ),
      ),
    );
  }
}
