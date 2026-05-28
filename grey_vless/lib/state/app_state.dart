import 'package:flutter/foundation.dart';

import '../models/server.dart';
import '../services/connection_service.dart';

class AppState extends ChangeNotifier {
  AppState(this.connection);

  final ConnectionService connection;
  List<VpnServer> servers = [];
  int? selectedIndex;
  bool tunMode = false;
  bool autoConnect = false;

  void setServers(List<VpnServer> value) {
    servers = value;
    notifyListeners();
  }

  void refresh() => notifyListeners();
}
