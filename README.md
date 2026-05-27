# Grey vless

Десктопный VPN-клиент для подписок VLESS, VMess, Trojan и Shadowsocks. Вставляете ссылку — выбираете сервер — подключаетесь.

Есть две версии интерфейса: классическая на GTK (Python) и кроссплатформенная на Flutter. Ядро везде одно — sing-box.

**Быстрый старт (Linux)**

1. Скачайте `.deb` или AppImage из [Releases](https://github.com/GermannM3/grey-vless/releases) (когда появятся) или соберите сами (см. ниже).
2. Запустите **Grey vless** из меню или `./Grey-vless-*.AppImage`.
3. Вставьте ссылку на подписку → «Загрузить» → выберите сервер → «Подключить».

Запускайте без `sudo`. Если открыть от root, системный прокси часто не включается, и кажется, что «подключено», но интернет не идёт через VPN.

**Что умеет**

- импорт подписки по URL или вставкой списка ссылок;
- проверка пинга и подключение к самому быстрому серверу;
- режим TUN (полный VPN) или обычный системный прокси;
- иконка в трее (GTK-версия).

**Сборка на Linux**

```bash
# .deb (автономный, зависимости внутри)
./scripts/build-deb.sh

# AppImage (GTK)
./scripts/build-appimage.sh

# Ядра sing-box для Flutter и CI
./scripts/download-cores.sh
```

Готовые файлы лежат в `build/deb/` и `build/`.

**Windows, macOS, Android**

Flutter-приложение в папке `grey_vless/`. Сборка всех платформ — через GitHub Actions: вкладка Actions → workflow «Build Grey vless» → Run workflow. Артефакты: Linux, Windows, macOS (.dmg), Android (.apk).

Подробнее: [BUILD.md](BUILD.md).

**Структура репозитория**

- `vless_app/` — GTK-клиент (Python)
- `grey_vless/` — Flutter-клиент
- `scripts/` — сборка и загрузка sing-box
- `data/` — иконка и desktop-файл

**Лицензия**

MIT, см. [LICENSE](LICENSE).
