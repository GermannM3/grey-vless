import 'package:flutter/foundation.dart';

import '../models/server.dart';
import '../services/connection_service.dart';
import '../services/grey_sense_service.dart';
import '../services/settings_repository.dart';

class AppState extends ChangeNotifier {
  AppState(this.connection, this._settings, this.greySense);

  final ConnectionService connection;
  final SettingsRepository _settings;
  final GreySenseService greySense;

  List<VpnServer> servers = [];
  int? selectedIndex;
  bool tunMode = false;
  bool autoConnect = false;
  bool autoReconnect = true;
  bool greySenseEnabled = true;
  String subscriptionUrl = '';
  String subscriptionName = 'Подписка';
  bool loaded = false;

  Future<void> load() async {
    subscriptionUrl = _settings.subscriptionUrl;
    subscriptionName = _settings.subscriptionName;
    tunMode = _settings.tunMode;
    autoConnect = _settings.autoConnect;
    autoReconnect = _settings.autoReconnect;
    greySenseEnabled = _settings.greySenseEnabled;
    servers = _settings.loadServers();
    selectedIndex = _settings.selectedIndex;
    if (selectedIndex != null && selectedIndex! >= servers.length) {
      selectedIndex = servers.isEmpty ? null : 0;
    }
    connection.tunMode = tunMode;
    connection.autoReconnect = autoReconnect;
    connection.greySenseEnabled = greySenseEnabled;
    connection.updateServerList(servers);
    loaded = true;
    notifyListeners();
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
    tunMode = value;
    connection.tunMode = value;
    await _settings.saveTunMode(value);
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
    notifyListeners();
  }

  Future<void> persistServers() async {
    await _settings.saveServers(servers);
  }

  void refresh() => notifyListeners();
}
