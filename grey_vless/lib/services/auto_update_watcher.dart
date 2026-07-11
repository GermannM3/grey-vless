import 'dart:async';

import 'package:flutter/material.dart';

import '../services/update_preferences.dart';
import '../services/update_service.dart';
import '../ui/update_dialog.dart';

/// Авто-проверка обновлений с GitHub Releases: старт, resume, каждые 4 часа.
class AutoUpdateWatcher extends StatefulWidget {
  const AutoUpdateWatcher({super.key, required this.child});

  final Widget child;

  @override
  State<AutoUpdateWatcher> createState() => _AutoUpdateWatcherState();
}

class _AutoUpdateWatcherState extends State<AutoUpdateWatcher> with WidgetsBindingObserver {
  final _prefs = UpdatePreferences();
  Timer? _periodic;
  bool _checking = false;
  String? _dismissedTag;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check(silent: true));
    _periodic = Timer.periodic(const Duration(hours: 4), (_) => _check(silent: true));
  }

  @override
  void dispose() {
    _periodic?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _check(silent: true);
    }
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking || !mounted) return;
    if (silent && !await _prefs.autoUpdateEnabled()) return;
    _checking = true;
    try {
      final info = await UpdateService.checkForUpdate();
      if (info == null || !mounted) return;
      if (_dismissedTag == info.tagName && silent) return;
      await showUpdateDialog(context, info);
      _dismissedTag = info.tagName;
    } catch (_) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось проверить обновления')),
        );
      }
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
