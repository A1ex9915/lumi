# Redirige el puerto 8000 del dispositivo Android a tu PC y ejecuta la app.
# Uso:  .\run_android.ps1            (puerto 8000)
#       .\run_android.ps1 -Port 9000
param([int]$Port = 8000)

$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
    Write-Error "No se encontró adb en $adb. Instala Android SDK Platform-Tools."
    exit 1
}

& $adb reverse "tcp:$Port" "tcp:$Port"
if ($LASTEXITCODE -ne 0) {
    Write-Error "adb reverse falló. ¿Está el dispositivo conectado y con depuración USB activada? (adb devices)"
    exit 1
}
Write-Host "adb reverse tcp:$Port -> PC:$Port OK"

flutter run --dart-define=API_BASE_URL=http://localhost:$Port/api
