import 'dart:io';

import '../models/server.dart';
import '../platform/android_native.dart';
import 'connection_service.dart';
import 'settings_repository.dart';

/// Автоподключение при старте и после загрузки подписки.
class AutoConnectService {
  AutoConnectService(this._settings, this._connection);

  final SettingsRepository _settings;
  final ConnectionService _connection;
  bool _ranThisSession = false;

  Future<AutoConnectResult> tryConnect({
    required List<VpnServer> servers,
    int? selectedIndex,
    bool force = false,
  }) async {
    if (!force && _ranThisSession) {
      return AutoConnectResult.skipped('Уже проверяли в этой сессии');
    }
    if (!_settings.autoConnect) {
      return AutoConnectResult.skipped('Автоподключение выключено');
    }
    if (servers.isEmpty) {
      return AutoConnectResult.skipped('Нет серверов');
    }
    if (_connection.isConnected) {
      return AutoConnectResult.skipped('Уже подключено');
    }

    if (Platform.isAndroid) {
      if (await AndroidNative.isOtherVpnActive()) {
        return AutoConnectResult.blocked(
          'Активен другой VPN — отключите его или выключите автоподключение',
        );
      }
    }

    _ranThisSession = true;

    // Без pingAll: иначе кнопка «Подключить» блокируется на минуты.
    final idx = (selectedIndex != null && selectedIndex >= 0 && selectedIndex < servers.length)
        ? selectedIndex
        : 0;
    final target = servers[idx];
    await _connection.connect(target);
    return AutoConnectResult.connected(target);
  }

  void resetSession() => _ranThisSession = false;
}

sealed class AutoConnectResult {
  const AutoConnectResult();

  factory AutoConnectResult.connected(VpnServer server) = AutoConnectConnected;
  factory AutoConnectResult.skipped(String reason) = AutoConnectSkipped;
  factory AutoConnectResult.blocked(String reason) = AutoConnectBlocked;
}

class AutoConnectConnected extends AutoConnectResult {
  AutoConnectConnected(this.server);
  final VpnServer server;
}

class AutoConnectSkipped extends AutoConnectResult {
  AutoConnectSkipped(this.reason);
  final String reason;
}

class AutoConnectBlocked extends AutoConnectResult {
  AutoConnectBlocked(this.reason);
  final String reason;
}
