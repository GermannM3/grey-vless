# Упаковка Windows: portable zip + автоустановка в LocalAppData (без MotW).
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

Get-ChildItem -Path $OutDir -Recurse -File | ForEach-Object {
  Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue
}

@'
Grey vless — Windows

ВАЖНО: не запускайте grey_vless.exe из Downloads после перезагрузки —
Windows часто блокирует такие файлы.

1. Запустите Установить.cmd (один раз).
2. Дальше открывайте «Grey vless» из меню Пуск или «Запуск.cmd»
   в %LOCALAPPDATA%\Programs\Grey-vless.

Приложение само перенесёт себя туда при первом запуске из Downloads.

Режимы: полный VPN (TUN, нужен UAC) или системный прокси.
Per-app туннель (только выбранные приложения) — в Android-версии.

Автообновление тянет сборки с GitHub Releases.
'@ | Set-Content -Path "$OutDir/ЧИТАЙ_МЕНЯ.txt" -Encoding UTF8

@'
@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
if errorlevel 1 pause
'@ | Set-Content -Path "$OutDir/Установить.cmd" -Encoding ASCII

@'
@echo off
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0' -Recurse -File | Unblock-File -ErrorAction SilentlyContinue"
start "" "%~dp0grey_vless.exe"
'@ | Set-Content -Path "$OutDir/Запуск.cmd" -Encoding ASCII

@'
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Target = Join-Path $env:LOCALAPPDATA "Programs\Grey-vless"
$ExeName = "grey_vless.exe"
$StartMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$ShortcutPath = Join-Path $StartMenu "Grey vless.lnk"
$Launcher = Join-Path $Target "Запуск.cmd"

Write-Host "Установка Grey vless в:"
Write-Host "  $Target"

New-Item -ItemType Directory -Force -Path $Target | Out-Null
Copy-Item -Path (Join-Path $Root "*") -Destination $Target -Recurse -Force

Get-ChildItem -Path $Target -Recurse -File | ForEach-Object {
  Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue
  $zone = $_.FullName + ":Zone.Identifier"
  if (Test-Path $zone) { Remove-Item $zone -Force -ErrorAction SilentlyContinue }
}

$Wsh = New-Object -ComObject WScript.Shell
$Sc = $Wsh.CreateShortcut($ShortcutPath)
$Sc.TargetPath = $Launcher
$Sc.WorkingDirectory = $Target
$Sc.Description = "Grey vless"
$Sc.IconLocation = (Join-Path $Target $ExeName)
$Sc.Save()
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($Wsh) | Out-Null

Unblock-File -Path $ShortcutPath -ErrorAction SilentlyContinue
$lnkZone = $ShortcutPath + ":Zone.Identifier"
if (Test-Path $lnkZone) { Remove-Item $lnkZone -Force -ErrorAction SilentlyContinue }

# Run key — после логина в Windows приложение доступно из установленного пути
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
# Не автостартуем VPN, только фиксируем путь ярлыка не нужен в Run.
# (автоподключение — внутри приложения)

Write-Host ""
Write-Host "Готово. Меню Пуск → Grey vless (Запуск.cmd снимает блокировку)."
Write-Host ""
$launch = Read-Host "Запустить сейчас? (Y/n)"
if ($launch -eq "" -or $launch -match "^[YyДд]") {
  Start-Process -FilePath $Launcher
}
'@ | Set-Content -Path "$OutDir/install.ps1" -Encoding UTF8

Remove-Item -Force $Zip -ErrorAction SilentlyContinue
Compress-Archive -Path "$OutDir/*" -DestinationPath $Zip
Write-Host "Created $Zip"
