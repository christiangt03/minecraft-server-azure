# Enciende el servidor (dueno). Usa la Function 'start': crea la IP publica
# bajo demanda, la conecta a la NIC y arranca la VM. NO usar 'az vm start' a
# secas: arrancaria la VM sin IP publica (sin internet ni acceso de jugadores).
$ErrorActionPreference = "Stop"
$url = terraform -chdir="$PSScriptRoot\..\terraform" output -raw start_url
if (-not $url -or $url -eq "no habilitada") { throw "La Function de arranque no esta habilitada (enable_start_function)." }
Write-Host "Encendiendo el servidor..."
$r = Invoke-RestMethod -Uri $url -Method POST -TimeoutSec 180
if ($r.ok) { Write-Host "Listo. Conecta en ~2 min." } else { throw "Error: $($r | ConvertTo-Json -Compress)" }
