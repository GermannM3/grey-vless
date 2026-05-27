# Grey vless — сборка для всех платформ

## Быстро (GitHub Actions)

1. Залейте репозиторий на GitHub.
2. Откройте **Actions** → **Build Grey vless (all platforms)** → **Run workflow**.
3. Скачайте артефакты:
   - `grey-vless-linux-x64` — Linux
   - `grey-vless-appimage` — AppImage
   - `grey-vless-windows-x64` — Windows (папка с `.exe`)
   - `grey-vless-macos` — `.dmg`
   - `grey-vless-android-apk` — `.apk`

## Локально (Linux)

```bash
# Зависимости
sudo apt install git curl unzip clang cmake ninja-build pkg-config libgtk-3-dev

# Ядра sing-box
./scripts/download-cores.sh

# Flutter (если нет)
# https://docs.flutter.dev/get-started/install/linux

cd grey_vless
flutter create . --org com.grey --project-name grey_vless --platforms=linux,windows,android
flutter pub get
flutter build linux --release
```

Бинарник: `grey_vless/build/linux/x64/release/bundle/grey_vless`

## macOS / Windows / Android

Сборка macOS возможна только на macOS (или через CI `macos-latest`).

Windows и Android можно собрать на Linux:

```bash
flutter build windows --release
flutter build apk --release
```

## Старый Python-клиент (GTK)

```bash
./scripts/build-appimage.sh
./scripts/build-deb.sh
```
