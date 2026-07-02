# Descarga los backups del blob al PC usando azcopy (solo lectura, via SAS).
# Los parametros se obtienen de 'terraform output' tras el apply.
#
# Uso manual:
#   .\pull-backups.ps1
# Se recomienda registrarlo como Tarea Programada diaria (ver README).

param(
  [string]$StorageAccount = $env:MC_STORAGE_ACCOUNT,
  [string]$Container      = "worldbackups",
  [string]$SasToken       = $env:MC_BACKUP_SAS,
  [string]$Destination    = "$PSScriptRoot\..\backups"
)

$ErrorActionPreference = "Stop"

if (-not $StorageAccount -or -not $SasToken) {
  Write-Error "Faltan StorageAccount o SasToken. Rellena las variables de entorno MC_STORAGE_ACCOUNT y MC_BACKUP_SAS, o pasalos como parametros. (Los saca 'terraform output'.)"
  exit 1
}

if (-not (Get-Command azcopy -ErrorAction SilentlyContinue)) {
  Write-Error "azcopy no esta instalado. Instalalo con: winget install Microsoft.Azure.AZCopy.10"
  exit 1
}

New-Item -ItemType Directory -Force -Path $Destination | Out-Null

# El SAS ya empieza por '?'
$src = "https://$StorageAccount.blob.core.windows.net/$Container$SasToken"

Write-Host "Sincronizando backups -> $Destination ..."
azcopy sync $src $Destination --recursive=true
Write-Host "Hecho. Backups en: $Destination"
