# ============================================================
#  Servidor HTTP - Dashboard Cierre de Inventario Feltrex
#  Ejecutar como administrador para usar puerto 80
#  Si no tienes admin, usa puerto 8080 cambiando $puerto abajo
# ============================================================

$puerto    = 8080
$dashboard = "$PSScriptRoot\cierre_inventario.html"
$dataRoot  = "C:\Users\lfernandez\OneDrive - Feltrex S.A\Existencia - Macan & Feltrex - Documentos\General\Inventarios"

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Dashboard Cierre de Inventario - Feltrex" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Carpeta de datos : $dataRoot" -ForegroundColor Gray
Write-Host "  Dashboard        : $dashboard" -ForegroundColor Gray
Write-Host ""
Write-Host "  Acceso local     : http://localhost:$puerto" -ForegroundColor Green
Write-Host "  Acceso en red    : http://$($env:COMPUTERNAME):$puerto" -ForegroundColor Green
Write-Host ""
Write-Host "  Presiona Ctrl+C para detener el servidor" -ForegroundColor Yellow
Write-Host ""

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:$puerto/")

try {
    $listener.Start()
    Write-Host "  Servidor iniciado correctamente." -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "  ERROR: No se pudo iniciar el servidor en el puerto $puerto." -ForegroundColor Red
    Write-Host "  Intenta ejecutar como Administrador o cambia el puerto en este script." -ForegroundColor Red
    Read-Host "  Presiona Enter para salir"
    exit 1
}

function Send-Response($ctx, $bytes, $contentType, $status = 200) {
    $ctx.Response.StatusCode = $status
    $ctx.Response.ContentType = $contentType
    $ctx.Response.Headers.Add("Access-Control-Allow-Origin", "*")
    $ctx.Response.ContentLength64 = $bytes.Length
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $ctx.Response.OutputStream.Close()
}

while ($listener.IsListening) {
    try {
        $ctx = $listener.GetContext()
        $path = $ctx.Request.Url.AbsolutePath
        $method = $ctx.Request.HttpMethod
        Write-Host "  $(Get-Date -Format 'HH:mm:ss')  $method $path" -ForegroundColor DarkGray

        # ── GET / → dashboard HTML
        if ($path -eq "/" -or $path -eq "/index.html") {
            $bytes = [System.IO.File]::ReadAllBytes($dashboard)
            Send-Response $ctx $bytes "text/html; charset=utf-8"
        }

        # ── GET /api/archivos → lista de .xlsx en JSON
        elseif ($path -eq "/api/archivos") {
            $archivos = Get-ChildItem $dataRoot -Recurse -Filter "*.xlsx" -ErrorAction SilentlyContinue |
                Where-Object { -not $_.Name.StartsWith("~`$") } |
                ForEach-Object {
                    $rel = $_.FullName.Substring($dataRoot.Length).TrimStart("\").Replace("\", "/")
                    $empresa = ($rel -split "/")[0]
                    [PSCustomObject]@{
                        path    = $rel
                        name    = $_.Name
                        empresa = $empresa
                    }
                }
            if ($null -eq $archivos) { $archivos = @() }
            $json = @($archivos) | ConvertTo-Json -Compress
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            Send-Response $ctx $bytes "application/json; charset=utf-8"
        }

        # ── GET /data/<ruta> → sirve el archivo .xlsx
        elseif ($path.StartsWith("/data/")) {
            $rel  = [Uri]::UnescapeDataString($path.Substring(6)).Replace("/", "\")
            $full = Join-Path $dataRoot $rel
            if (Test-Path $full -PathType Leaf) {
                $bytes = [System.IO.File]::ReadAllBytes($full)
                Send-Response $ctx $bytes "application/octet-stream"
            } else {
                $msg   = [System.Text.Encoding]::UTF8.GetBytes("Archivo no encontrado: $rel")
                Send-Response $ctx $msg "text/plain; charset=utf-8" 404
            }
        }

        # ── 404 para todo lo demás
        else {
            $msg = [System.Text.Encoding]::UTF8.GetBytes("Not found")
            Send-Response $ctx $msg "text/plain" 404
        }

    } catch [System.Net.HttpListenerException] {
        break
    } catch {
        Write-Host "  Error: $_" -ForegroundColor Red
        try { $ctx.Response.OutputStream.Close() } catch {}
    }
}

$listener.Stop()
Write-Host ""
Write-Host "  Servidor detenido." -ForegroundColor Yellow
