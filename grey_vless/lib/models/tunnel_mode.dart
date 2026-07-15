/// Режим маршрутизации трафика.
enum TunnelMode {
  /// Весь трафик через VPN (TUN).
  fullVpn,

  /// Только выбранные приложения через VPN (Android VpnService allowed apps).
  selectedApps,

  /// Все, кроме выбранных (Android VpnService disallowed apps).
  bypassApps,

  /// Без TUN: системный прокси (desktop) / локальный mixed (Android).
  systemProxy,
}

extension TunnelModeX on TunnelMode {
  String get id => name;

  String get title {
    switch (this) {
      case TunnelMode.fullVpn:
        return 'Полный VPN (весь трафик)';
      case TunnelMode.selectedApps:
        return 'Только выбранные приложения';
      case TunnelMode.bypassApps:
        return 'Все, кроме выбранных';
      case TunnelMode.systemProxy:
        return 'Системный прокси (без TUN)';
    }
  }

  String get subtitle {
    switch (this) {
      case TunnelMode.fullVpn:
        return 'Весь трафик устройства через VLESS';
      case TunnelMode.selectedApps:
        return 'VPN «включён», но в него попадают только отмеченные приложения';
      case TunnelMode.bypassApps:
        return 'Полный VPN, выбранные приложения идут мимо туннеля';
      case TunnelMode.systemProxy:
        return 'Браузеры и proxy-aware приложения; без виртуального адаптера';
    }
  }

  bool get usesTun => this != TunnelMode.systemProxy;

  bool get needsAppList =>
      this == TunnelMode.selectedApps || this == TunnelMode.bypassApps;

  static TunnelMode fromId(String? id) {
    return TunnelMode.values.firstWhere(
      (e) => e.id == id,
      orElse: () => TunnelMode.fullVpn,
    );
  }
}
