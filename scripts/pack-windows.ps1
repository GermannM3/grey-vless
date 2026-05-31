# Упаковка Windows: один exe + dll, без дубликатов.
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

# Убрать лишние exe (sing-box в assets, не в корне zip)
Get-ChildItem $OutDir -Recurse -Filter "sing-box*.exe" | Where-Object {
  $_.FullName -match "flutter_assets"
} | ForEach-Object { }  # оставляем в assets

@'
Grey vless — Windows

Запуск: grey_vless.exe
(Не переименовывайте exe — рядом должны лежать dll и папка data.)

Если системный прокси уже был включён, приложение подставит 127.0.0.1:7890
и при отключении вернёт прежние настройки.

'@ | Set-Content -Path "$OutDir/ЧИТАЙ_МЕНЯ.txt" -Encoding UTF8

Remove-Item -Force $Zip -ErrorAction SilentlyContinue
Compress-Archive -Path "$OutDir/*" -DestinationPath $Zip
Write-Host "Created $Zip"
