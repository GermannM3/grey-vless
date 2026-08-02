# Упаковка Windows: portable zip + простой install.cmd (без хрупкого PowerShell UI).
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

Установка:
  1. Запустите Установить.cmd
  2. Откройте Grey vless из меню Пуск

Файлы ставятся в:
  %LOCALAPPDATA%\Programs\Grey-vless

Не запускайте постоянно из Downloads — будут конфликты обновлений.

TUN (полный VPN) попросит UAC один раз.
Если не хотите админа — в настройках выберите «Системный прокси».
'@ | Set-Content -Path "$OutDir/ЧИТАЙ_МЕНЯ.txt" -Encoding UTF8

# Главный установщик — чистый cmd, без Read-Host и без Stop на мелочах.
@'
@echo off
chcp 65001 >nul
setlocal EnableExtensions
set "SRC=%~dp0"
set "TARGET=%LOCALAPPDATA%\Programs\Grey-vless"
set "EXE=grey_vless.exe"
set "STARTMENU=%APPDATA%\Microsoft\Windows\Start Menu\Programs"
set "LNK=%STARTMENU%\Grey vless.lnk"

echo.
echo Grey vless — установка
echo   %TARGET%
echo.

taskkill /F /IM grey_vless.exe /T >nul 2>&1
taskkill /F /IM sing-box.exe /T >nul 2>&1
timeout /t 1 /nobreak >nul

if not exist "%TARGET%" mkdir "%TARGET%"

where robocopy >nul 2>&1
if errorlevel 1 (
  echo robocopy не найден, копирую через xcopy...
  xcopy /E /Y /I /Q "%SRC%*" "%TARGET%\" >nul
) else (
  robocopy "%SRC%." "%TARGET%" /E /IS /IT /R:3 /W:1 /NFL /NDL /NJH /NJS /NP /XF "Установить.cmd" "install.ps1" "install.cmd" "ЧИТАЙ_МЕНЯ.txt" >nul
  if errorlevel 8 (
    echo robocopy с ошибкой, пробую xcopy...
    xcopy /E /Y /I /Q "%SRC%*" "%TARGET%\" >nul
  )
)

if not exist "%TARGET%\%EXE%" (
  echo ОШИБКА: не найден %TARGET%\%EXE%
  echo Запустите этот файл из распакованной папки zip.
  pause
  exit /b 1
)

> "%TARGET%\Запуск.cmd" (
  echo @echo off
  echo cd /d "%%~dp0"
  echo start "" "%%~dp0%EXE%"
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Get-ChildItem -LiteralPath '%TARGET%' -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue; ^
   $W=New-Object -ComObject WScript.Shell; ^
   $S=$W.CreateShortcut('%LNK%'); ^
   $S.TargetPath='%TARGET%\Запуск.cmd'; ^
   $S.WorkingDirectory='%TARGET%'; ^
   $S.IconLocation='%TARGET%\%EXE%'; ^
   $S.Save()" >nul 2>&1

echo.
echo Готово. Ярлык: меню Пуск → Grey vless
echo.
start "" "%TARGET%\%EXE%"
endlocal
exit /b 0
'@ | Set-Content -Path "$OutDir/Установить.cmd" -Encoding ASCII

# Дубликат на всякий случай (на скрине у пользователя был install без расширения в проводнике).
Copy-Item -Path "$OutDir/Установить.cmd" -Destination "$OutDir/install.cmd" -Force

@'
@echo off
chcp 65001 >nul
cd /d "%~dp0"
if not exist "%~dp0grey_vless.exe" (
  echo grey_vless.exe не найден рядом со скриптом.
  pause
  exit /b 1
)
start "" "%~dp0grey_vless.exe"
'@ | Set-Content -Path "$OutDir/Запуск.cmd" -Encoding ASCII

# Старый ps1 оставляем совместимым, но без Stop и без обязательного Read-Host.
@'
$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Target = Join-Path $env:LOCALAPPDATA "Programs\Grey-vless"
$ExeName = "grey_vless.exe"
$StartMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$ShortcutPath = Join-Path $StartMenu "Grey vless.lnk"
$Launcher = Join-Path $Target "Запуск.cmd"

Write-Host "Установка Grey vless → $Target"
taskkill /F /IM grey_vless.exe /T 2>$null | Out-Null
taskkill /F /IM sing-box.exe /T 2>$null | Out-Null
Start-Sleep -Seconds 1
New-Item -ItemType Directory -Force -Path $Target | Out-Null
$rc = Start-Process -FilePath "robocopy" -ArgumentList @(
  $Root, $Target, "/E", "/IS", "/IT", "/R:3", "/W:1",
  "/NFL", "/NDL", "/NJH", "/NJS", "/NP",
  "/XF", "Установить.cmd", "install.ps1", "install.cmd", "ЧИТАЙ_МЕНЯ.txt"
) -Wait -PassThru -WindowStyle Hidden
if ($rc.ExitCode -ge 8) {
  Copy-Item -Path (Join-Path $Root "*") -Destination $Target -Recurse -Force -ErrorAction SilentlyContinue
}
Get-ChildItem -Path $Target -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
  Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue
}
@"
@echo off
cd /d "%~dp0"
start "" "%~dp0$ExeName"
"@ | Set-Content -Path $Launcher -Encoding ASCII
try {
  $Wsh = New-Object -ComObject WScript.Shell
  $Sc = $Wsh.CreateShortcut($ShortcutPath)
  $Sc.TargetPath = $Launcher
  $Sc.WorkingDirectory = $Target
  $Sc.IconLocation = (Join-Path $Target $ExeName)
  $Sc.Save()
} catch {}
$exe = Join-Path $Target $ExeName
if (-not (Test-Path $exe)) {
  Write-Host "ОШИБКА: $exe не найден"
  exit 1
}
Write-Host "Готово."
Start-Process -FilePath $exe -WorkingDirectory $Target
'@ | Set-Content -Path "$OutDir/install.ps1" -Encoding UTF8

Remove-Item -Force $Zip -ErrorAction SilentlyContinue
Compress-Archive -Path "$OutDir/*" -DestinationPath $Zip
Write-Host "Created $Zip"
