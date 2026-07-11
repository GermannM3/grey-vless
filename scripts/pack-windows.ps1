# Упаковка Windows: portable zip + установщик без MotW (для закрепления на панели).
$ErrorActionPreference = "Stop"
$Release = "grey_vless/build/windows/x64/runner/Release"
$OutDir = "dist/windows-pack"
$Zip = "dist/Grey-vless-windows-x64.zip"

if (-not (Test-Path $Release)) {
  Write-Error "Release folder not found: $Release"
}

Remove-Item -Recurse -Force $OutDir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $OutDir | Out-Null
Copy-Item -Path "$Release/*" -Destination $OutDir -Recurse -Force

# Снять Mark of the Web со всех файлов сборки (если есть)
Get-ChildItem -Path $OutDir -Recurse -File | ForEach-Object {
  Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue
}

@'
Grey vless — Windows

=== Как правильно поставить (чтобы TUN и закрепление на панели работали) ===

1. Запустите Установить.cmd (двойной клик).
2. Подтвердите UAC при необходимости.
3. Ярлык появится в меню Пуск: «Grey vless».
4. Закрепляйте на панели ИЗ меню Пуск, не из папки Downloads.

Установщик копирует приложение в %LOCALAPPDATA%\Programs\Grey-vless,
снимает метку «из Интернета» (MotW) и создаёт ярлык без блокировки.

=== Быстрый запуск без установки ===

grey_vless.exe — рядом должны лежать dll и папка data.

Без TUN: системный прокси 127.0.0.1:7890.
С TUN: нужен запуск от администратора (приложение само запросит UAC).

Автообновление тянет новые сборки с GitHub Releases.
'@ | Set-Content -Path "$OutDir/ЧИТАЙ_МЕНЯ.txt" -Encoding UTF8

@'
@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
if errorlevel 1 pause
'@ | Set-Content -Path "$OutDir/Установить.cmd" -Encoding ASCII

@'
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Target = Join-Path $env:LOCALAPPDATA "Programs\Grey-vless"
$ExeName = "grey_vless.exe"
$StartMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$ShortcutPath = Join-Path $StartMenu "Grey vless.lnk"

Write-Host "Установка Grey vless в:"
Write-Host "  $Target"

New-Item -ItemType Directory -Force -Path $Target | Out-Null
Copy-Item -Path (Join-Path $Root "*") -Destination $Target -Recurse -Force

Get-ChildItem -Path $Target -Recurse -File | ForEach-Object {
  Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue
  # На всякий случай снять Zone.Identifier ADS
  $zone = $_.FullName + ":Zone.Identifier"
  if (Test-Path $zone) { Remove-Item $zone -Force -ErrorAction SilentlyContinue }
}

$Wsh = New-Object -ComObject WScript.Shell
$Sc = $Wsh.CreateShortcut($ShortcutPath)
$Sc.TargetPath = Join-Path $Target $ExeName
$Sc.WorkingDirectory = $Target
$Sc.Description = "Grey vless"
$Sc.IconLocation = (Join-Path $Target $ExeName)
$Sc.Save()
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($Wsh) | Out-Null

# Снять MotW с ярлыка
Unblock-File -Path $ShortcutPath -ErrorAction SilentlyContinue
$lnkZone = $ShortcutPath + ":Zone.Identifier"
if (Test-Path $lnkZone) { Remove-Item $lnkZone -Force -ErrorAction SilentlyContinue }

Write-Host ""
Write-Host "Готово. Ярлык: меню Пуск → Grey vless"
Write-Host "Закрепите на панели задач из меню Пуск (ПКМ → Закрепить)."
Write-Host ""
$launch = Read-Host "Запустить сейчас? (Y/n)"
if ($launch -eq "" -or $launch -match "^[YyДд]") {
  Start-Process -FilePath (Join-Path $Target $ExeName)
}
'@ | Set-Content -Path "$OutDir/install.ps1" -Encoding UTF8

Remove-Item -Force $Zip -ErrorAction SilentlyContinue
Compress-Archive -Path "$OutDir/*" -DestinationPath $Zip
Write-Host "Created $Zip"
