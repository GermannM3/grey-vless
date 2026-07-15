import 'package:flutter/material.dart';

import '../platform/installed_apps.dart';
import 'app_theme.dart';

/// Выбор приложений из системного списка для per-app туннеля.
class AppPickerScreen extends StatefulWidget {
  const AppPickerScreen({
    super.key,
    required this.initialSelected,
    required this.title,
  });

  final List<String> initialSelected;
  final String title;

  @override
  State<AppPickerScreen> createState() => _AppPickerScreenState();
}

class _AppPickerScreenState extends State<AppPickerScreen> {
  final _selected = <String>{};
  final _query = TextEditingController();
  List<InstalledApp>? _apps;
  String? _error;
  bool _hideSystem = true;

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.initialSelected);
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _apps = null;
    });
    try {
      final list = await InstalledApps.list();
      if (!mounted) return;
      setState(() => _apps = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  List<InstalledApp> get _filtered {
    final apps = _apps ?? const <InstalledApp>[];
    final q = _query.text.trim().toLowerCase();
    return apps.where((a) {
      if (_hideSystem && a.isSystem) return false;
      if (q.isEmpty) return true;
      return a.name.toLowerCase().contains(q) || a.id.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: AppTheme.bgTop,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _selected.toList()),
            child: Text('Готово (${_selected.length})'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _query,
              decoration: const InputDecoration(
                hintText: 'Поиск…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SwitchListTile(
            title: const Text('Скрыть системные'),
            value: _hideSystem,
            onChanged: (v) => setState(() => _hideSystem = v),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            )
          else if (_apps == null)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (filtered.isEmpty)
            const Expanded(child: Center(child: Text('Ничего не найдено')))
          else
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final app = filtered[i];
                  final checked = _selected.contains(app.id);
                  return CheckboxListTile(
                    value: checked,
                    title: Text(app.name),
                    subtitle: Text(app.id, style: const TextStyle(fontSize: 11)),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected.add(app.id);
                        } else {
                          _selected.remove(app.id);
                        }
                      });
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
