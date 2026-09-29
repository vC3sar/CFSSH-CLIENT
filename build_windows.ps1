# Build script para CFSSH Client (Windows)
# Usar este script en lugar de "flutter build windows" directamente.
# El flag --no-tree-shake-icons es necesario porque la app selecciona
# iconos dinamicamente (segun estado), lo cual el Icon Tree Shaker de
# Flutter no detecta y elimina los glyphs del font en Release.

param(
    [switch]$Debug
)

if ($Debug) {
    Write-Host "Cerrando aplicacion si esta en ejecucion..." -ForegroundColor Yellow
    Stop-Process -Name "cfssh_client" -Force -ErrorAction SilentlyContinue

    $exePathDebug = "build\windows\x64\runner\Debug\cfssh_client.exe"
    if (Test-Path $exePathDebug) {
        Remove-Item $exePathDebug -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Building DEBUG..." -ForegroundColor Cyan
    flutter build windows --debug
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Iniciando aplicacion (Debug)..." -ForegroundColor Green
        Start-Process $exePathDebug
    }
} else {
    Write-Host "Cerrando aplicacion si esta en ejecucion..." -ForegroundColor Yellow
    Stop-Process -Name "cfssh_client" -Force -ErrorAction SilentlyContinue

    $exePathRelease = "build\windows\x64\runner\Release\cfssh_client.exe"
    if (Test-Path $exePathRelease) {
        Remove-Item $exePathRelease -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Building RELEASE (no-tree-shake-icons)..." -ForegroundColor Green
    flutter build windows --no-tree-shake-icons
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Build successful:" -ForegroundColor Green
        Write-Host "  $exePathRelease" -ForegroundColor White
        Write-Host "Iniciando aplicacion..." -ForegroundColor Green
        Start-Process $exePathRelease
    }
}
