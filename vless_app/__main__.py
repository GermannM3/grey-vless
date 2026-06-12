#!/usr/bin/env python3

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk, Gdk  # noqa: E402

import sys
import threading

from vless_app.branding import APP_ID, APP_NAME
from vless_app.connection import ConnectionManager
from vless_app.models import Server
from vless_app.paths import singbox_binary
from vless_app.settings import AppSettings
from vless_app.subscription import parse_subscription
from vless_app.tray import TrayIcon
from vless_app.update import check_for_update, prompt_update


class MainWindow(Gtk.ApplicationWindow):
    def __init__(self, app: Gtk.Application, connection: ConnectionManager, settings: AppSettings):
        super().__init__(application=app, title=APP_NAME, default_width=780, default_height=560)
        self.servers: list[Server] = []
        self.connection = connection
        self.settings = settings
        self.tray: TrayIcon | None = None

        self._build_ui()
        self.connect("delete-event", self._on_close)
        self._restore_saved()

    def _restore_saved(self) -> None:
        if self.settings.subscription_url:
            self.source_entry.set_text(self.settings.subscription_url)
        if self.settings.servers:
            self.servers = [
                Server(
                    name=s.get("name", "Server"),
                    protocol=s.get("protocol", "vless"),
                    host=s.get("host", ""),
                    port=int(s.get("port", 443)),
                    raw_link=s.get("raw_link", ""),
                    params=s.get("params") or {},
                )
                for s in self.settings.servers
            ]
            self._refresh_list()
            self._set_status(f"Загружено серверов: {len(self.servers)}")

    def _persist_settings(self) -> None:
        self.settings.subscription_url = self.source_entry.get_text().strip()
        self.settings.tun_mode = self.tun_check.get_active()
        self.settings.auto_connect = self.auto_connect_check.get_active()
        self.settings.minimize_to_tray = self.tray_check.get_active()
        self.settings.servers = [
            {
                "name": s.name,
                "protocol": s.protocol,
                "host": s.host,
                "port": s.port,
                "raw_link": s.raw_link,
                "params": s.params,
            }
            for s in self.servers
        ]
        self.settings.save()

    def set_tray(self, tray: TrayIcon) -> None:
        self.tray = tray

    def _build_ui(self) -> None:
        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        root.set_border_width(16)
        self.add(root)

        header = Gtk.Label()
        header.set_markup(f"<span size='large' weight='bold'>{APP_NAME}</span>")
        header.set_xalign(0)
        root.pack_start(header, False, False, 0)

        hint = Gtk.Label(
            label="Вставьте ссылку на подписку или список серверов (vless://, vmess://, trojan://, ss://)"
        )
        hint.set_xalign(0)
        hint.set_line_wrap(True)
        root.pack_start(hint, False, False, 0)

        input_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.source_entry = Gtk.Entry()
        self.source_entry.set_placeholder_text("https://... или vless://...")
        self.source_entry.set_hexpand(True)
        input_row.pack_start(self.source_entry, True, True, 0)

        paste_btn = Gtk.Button(label="Вставить")
        paste_btn.connect("clicked", self._on_paste)
        input_row.pack_start(paste_btn, False, False, 0)

        load_btn = Gtk.Button(label="Загрузить")
        load_btn.get_style_context().add_class("suggested-action")
        load_btn.connect("clicked", self._on_load)
        input_row.pack_start(load_btn, False, False, 0)
        root.pack_start(input_row, False, False, 0)

        options = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
        self.tun_check = Gtk.CheckButton(label="Режим TUN (полный VPN)")
        self.tun_check.set_tooltip_text("Весь трафик через VPN. Нужны права администратора при установке.")
        self.tun_check.connect("toggled", self._on_tun_toggled)
        options.pack_start(self.tun_check, False, False, 0)

        self.auto_connect_check = Gtk.CheckButton(label="Автоподключение к самому быстрому")
        options.pack_start(self.auto_connect_check, False, False, 0)

        self.tray_check = Gtk.CheckButton(label="Сворачивать в трей")
        self.tray_check.set_active(True)
        options.pack_start(self.tray_check, False, False, 0)
        root.pack_start(options, False, False, 0)

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scrolled.set_min_content_height(260)

        self.store = Gtk.ListStore(str, str, str, str, str)
        self.tree = Gtk.TreeView(model=self.store)
        self.tree.set_headers_visible(True)
        self.tree.get_selection().set_mode(Gtk.SelectionMode.SINGLE)

        columns = [
            ("Сервер", 0, 220),
            ("Адрес", 1, 180),
            ("Протокол", 2, 90),
            ("Пинг", 3, 70),
            ("Статус", 4, 120),
        ]
        for title, col_id, width in columns:
            renderer = Gtk.CellRendererText()
            column = Gtk.TreeViewColumn(title, renderer, text=col_id)
            column.set_sort_column_id(col_id)
            column.set_resizable(True)
            column.set_min_width(width)
            self.tree.append_column(column)

        scrolled.add(self.tree)
        root.pack_start(scrolled, True, True, 0)

        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        ping_btn = Gtk.Button(label="Проверить пинг")
        ping_btn.connect("clicked", self._on_ping_all)
        actions.pack_start(ping_btn, False, False, 0)

        self.fastest_btn = Gtk.Button(label="Подключить самый быстрый")
        self.fastest_btn.connect("clicked", self._on_connect_fastest)
        actions.pack_start(self.fastest_btn, False, False, 0)

        self.connect_btn = Gtk.Button(label="Подключить")
        self.connect_btn.get_style_context().add_class("suggested-action")
        self.connect_btn.connect("clicked", self._on_connect)
        actions.pack_start(self.connect_btn, False, False, 0)

        self.disconnect_btn = Gtk.Button(label="Отключить")
        self.disconnect_btn.set_sensitive(False)
        self.disconnect_btn.connect("clicked", self._on_disconnect)
        actions.pack_start(self.disconnect_btn, False, False, 0)

        self.status = Gtk.Label(label="Не подключено")
        self.status.set_xalign(1)
        actions.pack_end(self.status, False, False, 0)
        root.pack_start(actions, False, False, 0)

    def _on_tun_toggled(self, check: Gtk.CheckButton) -> None:
        self.settings.tun_mode = check.get_active()
        self._persist_settings()

    def _set_status(self, text: str) -> None:
        GLib.idle_add(self.status.set_text, text)

    def _set_busy(self, busy: bool) -> None:
        self.connect_btn.set_sensitive(not busy and bool(self.servers))
        self.fastest_btn.set_sensitive(not busy and bool(self.servers))
        self.disconnect_btn.set_sensitive(not busy and self.connection.is_connected)

    def _refresh_list(self) -> None:
        self.store.clear()
        for server in self.servers:
            ping_text = f"{server.ping_ms} ms" if server.ping_ms is not None else "—"
            connected = self.connection.connected_server is server
            status = "Подключен" if connected else (server.ping_error or "")
            self.store.append(
                [
                    server.name,
                    f"{server.host}:{server.port}",
                    server.protocol.upper(),
                    ping_text,
                    status,
                ]
            )

    def on_disconnected(self) -> None:
        self._refresh_list()
        self._set_status("Отключено")
        self.connect_btn.set_sensitive(bool(self.servers))
        self.disconnect_btn.set_sensitive(False)
        if self.tray:
            self.tray.update()

    def on_connected(self, server: Server) -> None:
        self._refresh_list()
        mode = "TUN" if self.settings.tun_mode else "прокси"
        self._set_status(f"Подключено ({mode}): {server.name}")
        self.connect_btn.set_sensitive(False)
        self.disconnect_btn.set_sensitive(True)
        self._set_busy(False)
        if self.tray:
            self.tray.update()

    def _on_paste(self, _button) -> None:
        clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
        text = clipboard.wait_for_text()
        if not text or not text.strip():
            self._show_error("Буфер обмена пуст")
            return
        self.source_entry.set_text(text.strip())

    def _on_load(self, _button) -> None:
        source = self.source_entry.get_text().strip()
        if not source:
            self._show_error("Вставьте ссылку или текст подписки")
            return

        self._set_status("Загрузка...")
        self._set_busy(True)

        def worker() -> None:
            try:
                servers = parse_subscription(source)
            except Exception as exc:
                GLib.idle_add(self._show_error, str(exc))
                GLib.idle_add(self._set_status, "Ошибка загрузки")
                GLib.idle_add(self._set_busy, False)
                return

            def done() -> None:
                self.servers = servers
                self.connection.disconnect()
                self._refresh_list()
                self._set_status(f"Найдено серверов: {len(servers)}")
                self._set_busy(False)
                self._persist_settings()
                if self.auto_connect_check.get_active():
                    self._connect_fastest()

            GLib.idle_add(done)

        threading.Thread(target=worker, daemon=True).start()

    def _on_ping_all(self, _button) -> None:
        if not self.servers:
            self._show_error("Сначала загрузите подписку")
            return

        self._set_status("Проверка пинга...")
        self._set_busy(True)

        def worker() -> None:
            self.connection.ping_all(self.servers)

            def done() -> None:
                self._refresh_list()
                self._set_status("Пинг проверен")
                self._set_busy(False)

            GLib.idle_add(done)

        threading.Thread(target=worker, daemon=True).start()

    def _selected_server(self) -> Server | None:
        selection = self.tree.get_selection()
        model, tree_iter = selection.get_selected()
        if tree_iter is None:
            return None
        index = model.get_path(tree_iter).get_indices()[0]
        if 0 <= index < len(self.servers):
            return self.servers[index]
        return None

    def _on_connect(self, _button) -> None:
        server = self._selected_server()
        if server is None:
            self._show_error("Выберите сервер из списка")
            return
        self._connect_server(server)

    def _on_connect_fastest(self, _button) -> None:
        if not self.servers:
            self._show_error("Сначала загрузите подписку")
            return
        self._connect_fastest()

    def _connect_fastest(self) -> None:
        self.settings.auto_connect = self.auto_connect_check.get_active()
        self._set_status("Поиск самого быстрого сервера...")
        self._set_busy(True)

        def on_done(server: Server | None, error: str | None) -> None:
            if error:
                self._show_error(error)
                self._set_status("Ошибка подключения")
                self._set_busy(False)
                return
            if server:
                self.on_connected(server)

        self.connection.ping_and_connect_best(self.servers, lambda s, e: GLib.idle_add(on_done, s, e))

    def _connect_server(self, server: Server) -> None:
        self._set_status("Подключение...")
        self._set_busy(True)

        def on_done(error: str | None) -> None:
            if error:
                self._show_error(error)
                self._set_status("Ошибка подключения")
                self._set_busy(False)
                return
            self.on_connected(server)

        self.connection.connect_async(server, lambda e: GLib.idle_add(on_done, e))

    def _on_disconnect(self, _button) -> None:
        self.connection.disconnect()
        self.on_disconnected()

    def _on_close(self, _widget, _event) -> bool:
        if self.tray_check.get_active():
            self.hide()
            return True
        self._quit()
        return False

    def _quit(self) -> None:
        self.connection.shutdown()
        if self.tray:
            self.tray.icon.set_visible(False)
        Gtk.main_quit()

    def _show_error(self, message: str) -> None:
        dialog = Gtk.MessageDialog(
            transient_for=self,
            flags=0,
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK,
            text="Ошибка",
        )
        dialog.format_secondary_text(message)
        dialog.run()
        dialog.destroy()


class GreyVlessApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)
        self.settings = AppSettings()
        self.settings.load()
        self.connection = ConnectionManager(self.settings)
        self.window: MainWindow | None = None
        self.tray: TrayIcon | None = None

    def do_activate(self) -> None:
        if not self.window:
            self.window = MainWindow(self, self.connection, self.settings)
            self.tray = TrayIcon(self.window, self.connection, self._quit)
            self.window.set_tray(self.tray)
            self._schedule_update_check()
        self.window.show_all()
        self.window.present()

    def _schedule_update_check(self) -> None:
        def worker() -> None:
            try:
                info = check_for_update()
            except OSError:
                return
            if info and self.window:
                GLib.idle_add(prompt_update, self.window, info)

        threading.Thread(target=worker, daemon=True).start()

    def _quit(self) -> None:
        if self.window:
            self.window._quit()


def main() -> int:
    if not singbox_binary().exists():
        print(
            "sing-box не найден. Положите бинарник в bin/sing-box или установите пакет.",
            file=sys.stderr,
        )
        return 1

    app = GreyVlessApp()
    return app.run(sys.argv)


if __name__ == "__main__":
    raise SystemExit(main())
