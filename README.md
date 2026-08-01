# Grey vless

Десктопный и мобильный VPN-клиент для подписок VLESS, VMess, Trojan и Shadowsocks.

## Скачать (для всех)

Готовые сборки публикуются в **[Releases](https://github.com/GermannM3/grey-vless/releases)** — скачивание без входа в GitHub.

| Платформа | Файл |
|-----------|------|
| Android | `Grey-vless-android.apk` |
| Windows | `Grey-vless-windows-x64.zip` → `grey_vless.exe` |
| macOS M1/M2/M3 | `Grey-vless-macos-arm64.dmg` |
| macOS Intel (Monterey 12+) | `Grey-vless-macos-x86_64.dmg` |
| Linux | `Grey-vless-linux-x64.zip` или AppImage |

> **macOS:** на Intel Mac (например Monterey 12.7) нужен **x86_64**, не arm64.

> **Windows:** один путь — `%LOCALAPPDATA%\Programs\Grey-vless`. `Установить.cmd` и автообновление убивают старый процесс и пишут поверх (без «сноса»). Не держите рабочую копию в Downloads.

> **Android:** APK подписан одним ключом из репозитория — обновления ставятся поверх. Сборки до 0.4.20 могли быть с другим ключом: один раз удалите и поставьте заново.

Артефакты во вкладке Actions видны только владельцу репозитория — для пользователей используйте **Releases**.

## Быстрый старт (Linux GTK)

1. Скачайте `.deb` или AppImage из Releases или соберите сами.
2. Запустите **Grey vless**.
3. Вставьте подписку → «Загрузить» → «Подключить».

Запускайте без `sudo`.

## Сборка

См. [BUILD.md](BUILD.md).

## Лицензия

MIT — [LICENSE](LICENSE).
