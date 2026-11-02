# ==============================================================================
# Script para enviar APK a Discord a traves de Webhook
# ==============================================================================

param(
    [switch]$Build,
    [switch]$SplitPerAbi,
    [string]$ApkPath = "",
    [string]$Message = ""
)

$ErrorActionPreference = "Stop"

Write-Host "`n===============================================" -ForegroundColor Cyan
Write-Host "   CFSSH CLIENT - Enviar APK a Discord" -ForegroundColor Cyan
Write-Host "===============================================`n" -ForegroundColor Cyan

# 1. Cargar webhook desde archivo .env
$envFilePath = Join-Path $PSScriptRoot ".env"
$webhookUrl = ""

if (Test-Path $envFilePath) {
    Get-Content $envFilePath | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#")) {
            if ($line -match '^DISCORD_WEBHOOK_URL\s*=\s*["'']?(.*?)["'']?$') {
                $webhookUrl = $matches[1].Trim()
            }
        }
    }
}

if ([string]::IsNullOrWhiteSpace($webhookUrl)) {
    Write-Error "No se encontro DISCORD_WEBHOOK_URL en el archivo .env."
    exit 1
}

# 2. Si se solicito -Build, compilar primero
if ($Build) {
    Write-Host "[1/3] Compilando APK..." -ForegroundColor Yellow
    flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons
}

# 3. Detectar ruta del APK mas reciente si no se especifico
if ([string]::IsNullOrWhiteSpace($ApkPath)) {
    $newestApk = Get-ChildItem "build\app\outputs\flutter-apk\*.apk" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($newestApk) {
        $ApkPath = $newestApk.FullName
    }
}

if ([string]::IsNullOrWhiteSpace($ApkPath) -or -not (Test-Path $ApkPath)) {
    Write-Error "No se encontro ningun APK compilado en build\app\outputs\flutter-apk\`nCompila primero con 'flutter build apk --release'."
    exit 1
}

$apkItem = Get-Item $ApkPath
$apkSizeMB = [math]::Round($apkItem.Length / 1MB, 2)
$dateStr = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Write-Host "[2/3] Archivo APK detectado:" -ForegroundColor Cyan
Write-Host "      Nombre: $($apkItem.Name)" -ForegroundColor White
Write-Host "      Tamano: $apkSizeMB MB" -ForegroundColor White
Write-Host "      Fecha:  $($apkItem.LastWriteTime)" -ForegroundColor White

# 4. Determinar metodo de envio a Discord
$discordMaxBytes = 24 * 1024 * 1024

if ($apkItem.Length -le $discordMaxBytes) {
    Write-Host "[3/3] Subiendo APK directo a Discord (<25MB)..." -ForegroundColor Yellow
    if ([string]::IsNullOrWhiteSpace($Message)) {
        $Message = "**Nuevo APK CFSSH Client Compilado**`n**Fecha:** $dateStr`n**Archivo:** ``$($apkItem.Name)`` ($apkSizeMB MB)"
    }
    
    $curlOut = & curl.exe -s -w "\n%{http_code}" -F "content=$Message" -F "file=@$($apkItem.FullName)" $webhookUrl
    $lines = $curlOut -split "`n"
    $httpCode = $lines[-1].Trim()
    $responseBody = ($lines[0..($lines.Length - 2)]) -join "`n"

    if ($httpCode -match '^(200|204)$') {
        Write-Host "`n[OK] APK enviado exitosamente como archivo adjunto a Discord!" -ForegroundColor Green
    } else {
        Write-Host "`n[!] Discord respondio con codigo ${httpCode}: $responseBody" -ForegroundColor Red
    }
} else {
    Write-Host "[3/3] El APK ($apkSizeMB MB) supera el limite de Discord (25MB)." -ForegroundColor Yellow
    Write-Host "      Subiendo a servidor de descarga directa (.apk)..." -ForegroundColor Cyan

    $downloadLink = ""

    # Intento 1: catbox.moe (Direct .apk raw file link)
    try {
        Write-Host "      Subiendo a catbox.moe..." -ForegroundColor DarkGray
        $catboxRes = & curl.exe -s -F "reqtype=fileupload" -F "fileToUpload=@$($apkItem.FullName)" https://catbox.moe/user/api.php
        if ($catboxRes -match '^https?://files\.catbox\.moe/.*\.apk$') {
            $downloadLink = $catboxRes.Trim()
        }
    } catch {
        Write-Host "      catbox.moe no respondio." -ForegroundColor DarkGray
    }

    # Intento 2: temp.sh
    if ([string]::IsNullOrWhiteSpace($downloadLink)) {
        try {
            Write-Host "      Subiendo a temp.sh..." -ForegroundColor DarkGray
            $uploadRes = & curl.exe -s -F "file=@$($apkItem.FullName)" https://temp.sh/upload
            if ($uploadRes -match '^https?://') {
                $downloadLink = $uploadRes.Trim()
            }
        } catch {
            Write-Host "      temp.sh no respondio." -ForegroundColor DarkGray
        }
    }

    if ([string]::IsNullOrWhiteSpace($downloadLink)) {
        Write-Error "No se pudo generar enlace de descarga para el APK."
        exit 1
    }

    Write-Host "      Enlace directo generado: $downloadLink" -ForegroundColor Green
    Write-Host "      Publicando tarjeta de descarga en Discord..." -ForegroundColor Yellow

    $embedPayload = @{
        username = "CFSSH Client Build Bot"
        content = "**Nuevo APK de CFSSH Client disponible para descargar (Fix Samsung Nav Bar)**"
        embeds = @(
            @{
                title = "Descargar e Instalar $($apkItem.Name)"
                url = $downloadLink
                description = "El APK esta listo para instalar en tu telefono Android con la correccion de navegacion Samsung.`nHaz clic en el enlace para descargarlo directamente:"
                color = 61439
                fields = @(
                    @{
                        name = "Archivo"
                        value = "``$($apkItem.Name)``"
                        inline = $true
                    },
                    @{
                        name = "Tamano"
                        value = "$apkSizeMB MB"
                        inline = $true
                    },
                    @{
                        name = "Fecha"
                        value = "$dateStr"
                        inline = $false
                    },
                    @{
                        name = "Enlace de Descarga Directa"
                        value = "[TOCA AQUI PARA DESCARGAR EL APK DIRECTO]($downloadLink)"
                        inline = $false
                    }
                )
                footer = @{
                    text = "CFSSH Client - Build Automatizado"
                }
            }
        )
    }

    $jsonBody = $embedPayload | ConvertTo-Json -Depth 5
    $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)

    try {
        $response = Invoke-RestMethod -Uri $webhookUrl -Method Post -ContentType "application/json; charset=utf-8" -Body $utf8Bytes
        Write-Host "`n[OK] Tarjeta de descarga enviada a Discord exitosamente!" -ForegroundColor Green
        Write-Host "    Link directo: $downloadLink`n" -ForegroundColor Cyan
    } catch {
        Write-Host "`n[!] Error enviando a Discord: $_" -ForegroundColor Red
    }
}
