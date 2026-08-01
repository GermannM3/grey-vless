# Упаковка Windows: portable zip + установщик в LocalAppData (без конфликта копий).
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

Единственный путь установки:
  %LOCALAPPDATA%\Programs\Grey-vless

1. Запустите Установить.cmd (закроет старую копию и обновит поверх).
2. Дальше — меню Пуск → Grey vless.

Не держите рабочую копию в Downloads: после reboot Windows её блокирует,
а две копии конфликтуют при обновлении.

Автообновление из приложения тоже пишет только в LocalAppData.
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

Write-Host "Обновление Grey vless в:"
Write-Host "  $Target"

# Снимаем lock: иначе dll/exe не перезаписываются и «конфликтует со старой сборкой».
taskkill /F /IM grey_vless.exe /T 2>$null | Out-Null
taskkill /F /IM sing-box.exe /T 2>$null | Out-Null
Start-Sleep -Seconds 1

New-Item -ItemType Directory -Force -Path $Target | Out-Null
$rc = Start-Process -FilePath "robocopy" -ArgumentList @(
  $Root, $Target, "/E", "/IS", "/IT", "/R:3", "/W:1",
  "/NFL", "/NDL", "/NJH", "/NJS", "/NP",
  "/XF", "Установить.cmd", "install.ps1", "ЧИТАЙ_МЕНЯ.txt"
) -Wait -PassThru
if ($rc.ExitCode -ge 8) {
  Copy-Item -Path (Join-Path $Root "*") -Destination $Target -Recurse -Force
}

Get-ChildItem -Path $Target -Recurse -File | ForEach-Object {
  Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue
  $zone = $_.FullName + ":Zone.Identifier"
  if (Test-Path $zone) { Remove-Item $zone -Force -ErrorAction SilentlyContinue }
}

@"
@echo off
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0' -Recurse -File | Unblock-File -ErrorAction SilentlyContinue"
start "" "%~dp0$ExeName"
"@ | Set-Content -Path $Launcher -Encoding ASCII

$Wsh = New-Object -ComObject WScript.Shell
$Sc = $Wsh.CreateShortcut($ShortcutPath)
$Sc.TargetPath = $Launcher
$Sc.WorkingDirectory = $Target
$Sc.Description = "Grey vless"
$Sc.IconLocation = (Join-Path $Target $ExeName)
$Sc.Save()
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($Wsh) | Out-Null

Unblock-File -Path $ShortcutPath -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Готово. Запускайте из меню Пуск → Grey vless"
Write-Host ""
$launch = Read-Host "Запустить сейчас? (Y/n)"
if ($launch -eq "" -or $launch -match "^[YyДд]") {
  Start-Process -FilePath (Join-Path $Target $ExeName) -WorkingDirectory $Target
}
'@ | Set-Content -Path "$OutDir/install.ps1" -Encoding UTF8

Remove-Item -Force $Zip -ErrorAction SilentlyContinue
Compress-Archive -Path "$OutDir/*" -DestinationPath $Zip
Write-Host "Created $Zip"
