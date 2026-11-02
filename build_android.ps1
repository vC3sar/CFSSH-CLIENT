# ==============================================================================
# Script de Compilación y Distribución Android (CFSSH Client)
# ==============================================================================
# Uso:
#   .\build_android.ps1                         -> Compila APK Release (universal)
#   .\build_android.ps1 -SplitPerAbi            -> Compila APKs separados (arm64, armeabi-v7a, x86_64)
#   .\build_android.ps1 -Install                -> Compila e instala directo a tu teléfono vía ADB
#   .\build_android.ps1 -UploadDiscord          -> Compila y sube el APK a tu Discord vía Webhook
#   .\build_android.ps1 -UploadTransfer         -> Compila y sube a bashupload.com (genera link QR y link de descarga directo)
#   .\build_android.ps1 -ServeQr                -> Abre servidor web local y muestra QR en terminal para instalar en tu cel por WiFi
# ==============================================================================

param(
    [switch]$SplitPerAbi,
    [switch]$Install,
    [switch]$UploadTransfer,
    [switch]$UploadDiscord,
    [string]$DiscordWebhookUrl = "",
    [switch]$ServeQr,
    [int]$Port = 8080
)

$ErrorActionPreference = "Stop"

Write-Host "`n===============================================" -ForegroundColor Cyan
Write-Host "   CFSSH CLIENT - Compilación para Android" -ForegroundColor Cyan
Write-Host "===============================================`n" -ForegroundColor Cyan

# 1. Ejecutar build de Flutter
if ($SplitPerAbi) {
    Write-Host "[1/3] Compilando APKs divididos por arquitectura (--split-per-abi)..." -ForegroundColor Yellow
    flutter build apk --release --split-per-abi
    $apkDir = "build\app\outputs\flutter-apk"
    $apkPath = "$apkDir\app-arm64-v8a-release.apk"
} else {
    Write-Host "[1/3] Compilando APK universal release (flutter build apk --release)..." -ForegroundColor Yellow
    flutter build apk --release
    $apkPath = "build\app\outputs\flutter-apk\app-release.apk"
}

if (-not (Test-Path $apkPath)) {
    Write-Error "No se encontró el APK generado en: $apkPath"
    exit 1
}

$apkItem = Get-Item $apkPath
$apkSizeMB = [math]::Round($apkItem.Length / 1MB, 2)
Write-Host "`n[✓] APK generado con éxito!" -ForegroundColor Green
Write-Host "    Ruta: $($apkItem.FullName)" -ForegroundColor White
Write-Host "    Tamaño: $apkSizeMB MB`n" -ForegroundColor White

# 2. Opcion: Instalar directo por ADB si se solicita (-Install)
if ($Install) {
    Write-Host "[2/3] Verificando dispositivos conectados vía ADB..." -ForegroundColor Yellow
    $devices = & adb devices | Select-String "device$"
    if ($devices) {
        Write-Host "Instalando $apkPath en el dispositivo..." -ForegroundColor Cyan
        adb install -r $apkPath
        Write-Host "[✓] Instalación completada en dispositivo!" -ForegroundColor Green
    } else {
        Write-Host "[!] No hay ningún dispositivo/celular conectado con USB Debugging activo." -ForegroundColor Red
        Write-Host "    Conecta tu teléfono con depuración USB o usa -UploadTransfer / -ServeQr" -ForegroundColor Yellow
    }
}

# 3. Opcion: Subida anónima a la nube (-UploadTransfer)
if ($UploadTransfer) {
    Write-Host "[2/3] Subiendo APK a bashupload.com para generar enlace de descarga..." -ForegroundColor Yellow
    try {
        $fileName = "cfssh-client-$($apkItem.Name)"
        $uploadUrl = "https://bashupload.com/$fileName"
        
        $response = Invoke-RestMethod -Uri $uploadUrl -Method Put -InFile $apkPath -TimeoutSec 120
        Write-Host "`n[✓] ¡APK SUBIDO CON ÉXITO!" -ForegroundColor Green
        Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
        Write-Host "Enlace de descarga para tu celular / navegador:" -ForegroundColor Yellow
        Write-Host "  $response" -ForegroundColor White
        Write-Host "--------------------------------------------------------`n" -ForegroundColor Cyan
    } catch {
        Write-Host "[!] Error al subir a bashupload: $_" -ForegroundColor Red
    }
}

# 4. Opcion: Subir a Discord vía Webhook (-UploadDiscord)
if ($UploadDiscord) {
    if ([string]::IsNullOrWhiteSpace($DiscordWebhookUrl)) {
        # Intentar leer desde .env si existe
        $envFilePath = Join-Path $PSScriptRoot ".env"
        if (Test-Path $envFilePath) {
            Get-Content $envFilePath | ForEach-Object {
                $line = $_.Trim()
                if ($line -and -not $line.StartsWith("#")) {
                    if ($line -match '^DISCORD_WEBHOOK_URL\s*=\s*["'']?(.*?)["'']?$') {
                        $DiscordWebhookUrl = $matches[1].Trim()
                    }
                }
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($DiscordWebhookUrl)) {
        $DiscordWebhookUrl = Read-Host "Introduce tu Discord Webhook URL"
    }
    
    if (-not [string]::IsNullOrWhiteSpace($DiscordWebhookUrl)) {
        Write-Host "[2/3] Enviando APK al canal de Discord..." -ForegroundColor Yellow
        try {
            $curlAvailable = Get-Command curl.exe -ErrorAction SilentlyContinue
            if ($curlAvailable) {
                & curl.exe -F "file=@$apkPath" -F "content=🚀 **Nuevo APK Release compilado**: CFSSH Client ($apkSizeMB MB)" $DiscordWebhookUrl
                Write-Host "`n[✓] ¡APK enviado a Discord exitosamente!" -ForegroundColor Green
            } else {
                Write-Host "[!] curl.exe no está disponible en este sistema." -ForegroundColor Red
            }
        } catch {
            Write-Host "[!] Error al enviar a Discord: $_" -ForegroundColor Red
        }
    }
}

# 5. Opcion: Servir localmente en tu red WiFi (-ServeQr)
if ($ServeQr) {
    # Obtener IP local de la máquina
    $localIp = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "vEthernet|Loopback" -and $_.IPAddress -notmatch "^169\." } | Select-Object -First 1).IPAddress
    if (-not $localIp) { $localIp = "127.0.0.1" }
    
    $downloadUrl = "http://${localIp}:${Port}/$($apkItem.Name)"
    Write-Host "`n--------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "SERVIDOR DE DESCARGA LOCAL (WIFI)" -ForegroundColor Green
    Write-Host "Asegúrate de que tu celular esté conectado a la misma red WiFi." -ForegroundColor Yellow
    Write-Host "Enlace directo para tu celular:" -ForegroundColor Cyan
    Write-Host "  $downloadUrl`n" -ForegroundColor White
    Write-Host "Presiona Ctrl+C en esta consola cuando termines de descargarlo." -ForegroundColor DarkGray
    Write-Host "--------------------------------------------------------`n" -ForegroundColor Cyan

    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://*:${Port}/")
    try {
        $listener.Start()
        while ($listener.IsListening) {
            $context = $listener.GetContext()
            $request = $context.Request
            $response = $context.Response

            Write-Host "Petición recibida desde: $($request.RemoteEndPoint)" -ForegroundColor Yellow
            $bytes = [System.IO.File]::ReadAllBytes($apkPath)
            $response.ContentType = "application/vnd.android.package-archive"
            $response.ContentLength64 = $bytes.Length
            $response.AddHeader("Content-Disposition", "attachment; filename=$($apkItem.Name)")
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
            $response.OutputStream.Close()
            Write-Host "[✓] ¡APK transferido con éxito al dispositivo!" -ForegroundColor Green
        }
    } catch {
        Write-Host "Servidor detenido." -ForegroundColor DarkGray
    } finally {
        $listener.Stop()
    }
}

Write-Host "Ruta final del APK: $($apkItem.FullName)`n" -ForegroundColor Cyan

