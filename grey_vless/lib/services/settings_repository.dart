import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/server.dart';
import '../models/tunnel_mode.dart';

class SettingsRepository {
  static const _kSubscriptionUrl = 'subscription_url';
  static const _kSubscriptionName = 'subscription_name';
  static const _kServers = 'servers_json';
  static const _kSelectedIndex = 'selected_index';
  static const _kTunMode = 'tun_mode';
  static const _kTunnelMode = 'tunnel_mode';
  static const _kTunnelApps = 'tunnel_apps';
  static const _kAutoConnect = 'auto_connect';
  static const _kAutoReconnect = 'auto_reconnect';
  static const _kGreySense = 'grey_sense_enabled';
  static const _kPendingConnectIndex = 'pending_connect_index';
  static const _kPendingConnectAfterElevate = 'pending_connect_elevate';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  SharedPreferences get prefs {
    final p = _prefs;
    if (p == null) throw StateError('SettingsRepository not initialized');
    return p;
  }

  String get subscriptionUrl => prefs.getString(_kSubscriptionUrl) ?? '';
  String get subscriptionName => prefs.getString(_kSubscriptionName) ?? 'Подписка';

  Future<void> saveSubscription({required String url, String? name}) async {
    await prefs.setString(_kSubscriptionUrl, url);
    if (name != null && name.isNotEmpty) {
      await prefs.setString(_kSubscriptionName, name);
    }
  }

  /// Совместимость со старым boolean tun_mode.
  bool get tunMode => tunnelMode.usesTun;

  TunnelMode get tunnelMode {
    final id = prefs.getString(_kTunnelMode);
    if (id != null && id.isNotEmpty) {
      return TunnelModeX.fromId(id);
    }
    // Миграция со старого переключателя.
    final legacy = prefs.getBool(_kTunMode);
    if (legacy == false) return TunnelMode.systemProxy;
    if (legacy == true) return TunnelMode.fullVpn;
    return Platform.isAndroid ? TunnelMode.fullVpn : TunnelMode.systemProxy;
  }

  List<String> get tunnelAppIds => prefs.getStringList(_kTunnelApps) ?? const [];

  bool get autoConnect => prefs.getBool(_kAutoConnect) ?? false;
  bool get autoReconnect => prefs.getBool(_kAutoReconnect) ?? true;
  bool get greySenseEnabled => prefs.getBool(_kGreySense) ?? true;

  Future<void> saveTunMode(bool value) async {
    await saveTunnelMode(value ? TunnelMode.fullVpn : TunnelMode.systemProxy);
  }

  Future<void> saveTunnelMode(TunnelMode mode) async {
    await prefs.setString(_kTunnelMode, mode.id);
    await prefs.setBool(_kTunMode, mode.usesTun);
  }

  Future<void> saveTunnelAppIds(List<String> ids) async {
    await prefs.setStringList(_kTunnelApps, ids);
  }

  Future<void> saveAutoConnect(bool value) async => prefs.setBool(_kAutoConnect, value);
  Future<void> saveAutoReconnect(bool value) async => prefs.setBool(_kAutoReconnect, value);
  Future<void> saveGreySenseEnabled(bool value) async => prefs.setBool(_kGreySense, value);

  /// После UAC-перезапуска — продолжить подключение к этому индексу сервера.
  int? get pendingConnectIndex {
    if (prefs.getBool(_kPendingConnectAfterElevate) != true) return null;
    if (!prefs.containsKey(_kPendingConnectIndex)) return null;
    return prefs.getInt(_kPendingConnectIndex);
  }

  Future<void> setPendingConnectAfterElevate(int? serverIndex) async {
    if (serverIndex == null) {
      await prefs.setBool(_kPendingConnectAfterElevate, false);
      await prefs.remove(_kPendingConnectIndex);
    } else {
      await prefs.setBool(_kPendingConnectAfterElevate, true);
      await prefs.setInt(_kPendingConnectIndex, serverIndex);
    }
  }

  int? get selectedIndex {
    if (!prefs.containsKey(_kSelectedIndex)) return null;
    return prefs.getInt(_kSelectedIndex);
  }

  Future<void> saveSelectedIndex(int? value) async {
    if (value == null) {
      await prefs.remove(_kSelectedIndex);
    } else {
      await prefs.setInt(_kSelectedIndex, value);
    }
  }

  List<VpnServer> loadServers() {
    final raw = prefs.getString(_kServers);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => VpnServer.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveServers(List<VpnServer> servers) async {
    final encoded = jsonEncode(servers.map((s) => s.toJson()).toList());
    await prefs.setString(_kServers, encoded);
  }
}
