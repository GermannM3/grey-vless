from gi.repository import GLib, Gtk, GdkPixbuf

from .branding import APP_NAME
from .connection import ConnectionManager
from .paths import icon_path


class TrayIcon:
    def __init__(
        self,
        window: Gtk.Window,
        connection: ConnectionManager,
        on_quit,
    ):
        self.window = window
        self.connection = connection
        self.on_quit = on_quit
        self.icon = Gtk.StatusIcon()
        self._load_icon()
        self.icon.set_tooltip_text(APP_NAME)
        self.icon.connect("activate", self._on_activate)
        self.icon.connect("popup-menu", self._on_popup)
        self.update()

    def _load_icon(self) -> None:
        path = icon_path()
        if path.exists():
            pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_size(str(path), 22, 22)
            self.icon.set_from_pixbuf(pixbuf)
        else:
            self.icon.set_from_icon_name("network-vpn")

    def update(self) -> None:
        if self.connection.is_connected:
            name = self.connection.connected_server.name if self.connection.connected_server else "VPN"
            self.icon.set_tooltip_text(f"Подключено: {name}")
        else:
            self.icon.set_tooltip_text(f"{APP_NAME} — не подключено")

    def _on_activate(self, _icon) -> None:
        self.window.present()
        self.window.deiconify()

    def _on_popup(self, icon, button, time_) -> None:
        menu = Gtk.Menu()

        show_item = Gtk.MenuItem(label="Открыть")
        show_item.connect("activate", lambda *_: self._on_activate(icon))
        menu.append(show_item)

        if self.connection.is_connected:
            disconnect_item = Gtk.MenuItem(label="Отключить")
            disconnect_item.connect("activate", self._on_disconnect)
            menu.append(disconnect_item)

        quit_item = Gtk.MenuItem(label="Выход")
        quit_item.connect("activate", lambda *_: self.on_quit())
        menu.append(quit_item)

        menu.show_all()
        menu.popup(None, None, Gtk.StatusIcon.position_menu, icon, button, time_)

    def _on_disconnect(self, _item) -> None:
        self.connection.disconnect()
        self.update()
        if hasattr(self.window, "on_disconnected"):
            self.window.on_disconnected()
