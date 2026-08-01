import 'package:flutter/foundation.dart';

import '../models/server.dart';
import '../models/tunnel_mode.dart';
import '../services/auto_connect_service.dart';
import '../services/connection_service.dart';
import '../services/grey_sense_service.dart';
import '../services/settings_repository.dart';

class AppState extends ChangeNotifier {
  AppState(this.connection, this._settings, this.greySense)
      : autoConnectService = AutoConnectService(_settings, connection);

  final ConnectionService connection;
  final SettingsRepository _settings;
  final GreySenseService greySense;
  final AutoConnectService autoConnectService;

  List<VpnServer> servers = [];
  int? selectedIndex;
  TunnelMode tunnelMode = TunnelMode.fullVpn;
  List<String> tunnelAppIds = [];
  bool autoConnect = false;
  bool autoReconnect = true;
  bool greySenseEnabled = true;
  String subscriptionUrl = '';
  String subscriptionName = 'Подписка';
  bool loaded = false;

  bool get tunMode => tunnelMode.usesTun;

  Future<void> load() async {
    subscriptionUrl = _settings.subscriptionUrl;
    subscriptionName = _settings.subscriptionName;
    tunnelMode = _settings.tunnelMode;
    tunnelAppIds = List.of(_settings.tunnelAppIds);
    autoConnect = _settings.autoConnect;
    autoReconnect = _settings.autoReconnect;
    greySenseEnabled = _settings.greySenseEnabled;
    servers = _settings.loadServers();
    selectedIndex = _settings.selectedIndex;
    if (selectedIndex != null && selectedIndex! >= servers.length) {
      selectedIndex = servers.isEmpty ? null : 0;
    }
    _syncConnectionRouting();
    connection.autoReconnect = autoReconnect;
    connection.greySenseEnabled = greySenseEnabled;
    connection.updateServerList(servers);
    loaded = true;
    notifyListeners();
  }

  void _syncConnectionRouting() {
    connection.tunMode = tunnelMode.usesTun;
    connection.tunnelMode = tunnelMode;
    connection.tunnelAppIds = List.of(tunnelAppIds);
  }

  Future<void> setSubscription(String url, {String? name}) async {
    subscriptionUrl = url;
    if (name != null && name.isNotEmpty) subscriptionName = name;
    await _settings.saveSubscription(url: url, name: subscriptionName);
    notifyListeners();
  }

  Future<void> setServers(List<VpnServer> value) async {
    servers = value;
    connection.updateServerList(value);
    await _settings.saveServers(value);
    notifyListeners();
  }

  Future<void> setSelectedIndex(int? index) async {
    selectedIndex = index;
    await _settings.saveSelectedIndex(index);
    notifyListeners();
  }

  Future<void> setTunMode(bool value) async {
    await setTunnelMode(value ? TunnelMode.fullVpn : TunnelMode.systemProxy);
  }

  Future<void> setTunnelMode(TunnelMode value) async {
    tunnelMode = value;
    _syncConnectionRouting();
    await _settings.saveTunnelMode(value);
    notifyListeners();
  }

  Future<void> setTunnelAppIds(List<String> ids) async {
    tunnelAppIds = List.of(ids);
    _syncConnectionRouting();
    await _settings.saveTunnelAppIds(ids);
    notifyListeners();
  }

  Future<void> setAutoReconnect(bool value) async {
    autoReconnect = value;
    connection.autoReconnect = value;
    await _settings.saveAutoReconnect(value);
    notifyListeners();
  }

  Future<void> setGreySenseEnabled(bool value) async {
    greySenseEnabled = value;
    connection.greySenseEnabled = value;
    await _settings.saveGreySenseEnabled(value);
    notifyListeners();
  }

  Future<void> setAutoConnect(bool value) async {
    autoConnect = value;
    await _settings.saveAutoConnect(value);
    if (!value) {
      autoConnectService.resetSession();
    }
    notifyListeners();
  }

  Future<void> setPendingConnectAfterElevate(int? index) =>
      _settings.setPendingConnectAfterElevate(index);

  int? get pendingConnectIndex => _settings.pendingConnectIndex;

  /// Свежее значение из SharedPreferences — не полагаемся на кэш в памяти.
  bool get autoConnectEnabled => _settings.autoConnect;

  Future<void> persistServers() async {
    await _settings.saveServers(servers);
  }

  void refresh() => notifyListeners();
}
