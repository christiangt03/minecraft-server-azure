# deploy.ps1 - Despliega TODO el servidor de Minecraft en Azure desde cero con un solo comando.
#
# Uso (click derecho > Ejecutar con PowerShell, o desde una consola):
#   .\deploy.ps1                despliega todo y ofrece restaurar el ultimo backup del mundo
#   .\deploy.ps1 -SkipRestore   despliega todo sin restaurar el mundo
#
# Requisitos: Azure CLI y Terraform instalados (el script te dice como si faltan).
# OpenSSH (ssh/scp) ya viene incluido en Windows 10/11.
#
# Al terminar, la VM queda ENCENDIDA. Si nadie entra a jugar, se auto-apaga a los
# 20 minutos y la Function borra la IP -> vuelve al modo reposo (~1,4 EUR/mes).

param([switch]$SkipRestore)

$ErrorActionPreference = "Stop"
$RepoDir   = $PSScriptRoot
$TfDir     = Join-Path $RepoDir "terraform"
$SubId     = "ed313ee9-11b5-45d4-ac7c-6116fc894139"   # Azure for Students
$SshKey    = Join-Path $env:USERPROFILE ".ssh\mcserver"
$AdminUser = "azuremc"

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }

# ---------- 1. Herramientas ----------
Step "Comprobando herramientas"
$missing = @()
if (-not (Get-Command az        -ErrorAction SilentlyContinue)) { $missing += "Azure CLI  ->  winget install Microsoft.AzureCLI" }
if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) { $missing += "Terraform  ->  winget install Hashicorp.Terraform" }
if (-not (Get-Command ssh       -ErrorAction SilentlyContinue)) { $missing += "OpenSSH    ->  Configuracion > Aplicaciones > Caracteristicas opcionales > Cliente OpenSSH" }
if ($missing.Count -gt 0) {
  Write-Host "Faltan herramientas. Instalalas y vuelve a ejecutar este script:" -ForegroundColor Red
  $missing | ForEach-Object { Write-Host "  - $_" }
  exit 1
}
Write-Host "OK (az, terraform, ssh)"

# ---------- 2. Sesion de Azure ----------
Step "Comprobando sesion de Azure"
$prevEap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
$acct = az account show --query id -o tsv 2>$null
$ErrorActionPreference = $prevEap
if (-not $acct) {
  Write-Host "No hay sesion. Se abrira el navegador para iniciar sesion..."
  az login --output none
}
az account set --subscription $SubId
Write-Host "Suscripcion activa: Azure for Students ($SubId)"

# ---------- 3. Clave SSH ----------
Step "Comprobando clave SSH"
if (-not (Test-Path "$SshKey.pub")) {
  New-Item -ItemType Directory -Force -Path (Split-Path $SshKey) | Out-Null
  ssh-keygen -q -t ed25519 -f $SshKey -N '""' -C "mcserver"
  Write-Host "Clave nueva generada en $SshKey"
} else {
  Write-Host "Se reutiliza la clave existente ($SshKey)"
}

# ---------- 4. terraform.tfvars (config personal, no va a git) ----------
Step "Preparando terraform.tfvars"
$myIp   = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 15).ToString().Trim()
$tfvars = Join-Path $TfDir "terraform.tfvars"
if (-not (Test-Path $tfvars)) {
  @"
# Generado por deploy.ps1. Editable. NO se sube a git (esta en .gitignore).
allowed_ssh_cidr    = "$myIp/32"
dns_label           = "christmc"
alert_email         = "christiangt03@hotmail.com"
ssh_public_key_path = "~/.ssh/mcserver.pub"

enable_start_function = true
"@ | Set-Content -Path $tfvars -Encoding ascii
  Write-Host "terraform.tfvars creado."
} else {
  # Refresca solo la IP permitida para SSH (tu IP publica cambia con el tiempo)
  (Get-Content $tfvars) -replace 'allowed_ssh_cidr\s*=\s*"[^"]*"', "allowed_ssh_cidr    = `"$myIp/32`"" |
    Set-Content -Path $tfvars -Encoding ascii
  Write-Host "terraform.tfvars existente; IP de SSH actualizada."
}
Write-Host "SSH permitido solo desde: $myIp/32"

# ---------- 5. Terraform: crear toda la infraestructura ----------
Step "Desplegando con Terraform (la primera vez tarda 10-15 min)"
Push-Location $TfDir
try {
  terraform init -input=false | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "Fallo terraform init" }
  terraform apply -auto-approve -input=false | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "Fallo terraform apply" }

  $addr     = terraform output -raw server_address
  $startUrl = terraform output -raw start_url
} finally {
  Pop-Location
}

Set-Content -Path (Join-Path $RepoDir "start-url.txt") -Value $startUrl -Encoding ascii
Write-Host "Boton de encendido guardado en start-url.txt"

# ---------- 6. Restaurar el mundo desde el ultimo backup ----------
$backup = Get-ChildItem (Join-Path $RepoDir "backups\mc-*.tar.gz") -ErrorAction SilentlyContinue |
  Sort-Object Name | Select-Object -Last 1

if ($backup -and -not $SkipRestore) {
  Write-Host ""
  $resp = Read-Host "Hay un backup del mundo: $($backup.Name). Restaurarlo? (S/n)"
  if ($resp -eq "" -or $resp -match "^[sS]") {

    Step "Esperando a que la VM termine de instalar Minecraft (5-10 min la primera vez)"
    $ErrorActionPreference = "Continue"   # los reintentos de ssh escriben en stderr; no son errores
    ssh-keygen -R $addr 2>$null | Out-Null   # la huella SSH cambia con cada VM nueva

    $deadline = (Get-Date).AddMinutes(20)
    $ready = $false
    while ((Get-Date) -lt $deadline) {
      $state = ssh -i $SshKey -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 "$AdminUser@$addr" "systemctl is-active minecraft" 2>$null
      if ("$state".Trim() -eq "active") { $ready = $true; break }
      Write-Host ("  ... instalando ({0:HH:mm:ss}), reintento en 20 s" -f (Get-Date))
      Start-Sleep -Seconds 20
    }
    if (-not $ready) {
      Write-Host "El servidor no arranco en 20 min. Puedes restaurar a mano mas tarde:" -ForegroundColor Yellow
      Write-Host "  scp -i $SshKey `"$($backup.FullName)`" ${AdminUser}@${addr}:/tmp/restore.tar.gz"
      Write-Host "  ssh -i $SshKey ${AdminUser}@${addr} 'sudo systemctl stop minecraft; sudo tar -xzf /tmp/restore.tar.gz -C /opt/mc/server; sudo chown -R minecraft:minecraft /opt/mc/server; sudo systemctl start minecraft'"
      exit 1
    }

    Step "Subiendo y restaurando el mundo"
    scp -i $SshKey -o StrictHostKeyChecking=accept-new "$($backup.FullName)" "${AdminUser}@${addr}:/tmp/restore.tar.gz"
    if ($LASTEXITCODE -ne 0) { throw "Fallo al subir el backup por scp" }
    ssh -i $SshKey -o StrictHostKeyChecking=accept-new "$AdminUser@$addr" "sudo systemctl stop minecraft && sudo tar -xzf /tmp/restore.tar.gz -C /opt/mc/server && sudo chown -R minecraft:minecraft /opt/mc/server && sudo systemctl start minecraft && rm -f /tmp/restore.tar.gz"
    if ($LASTEXITCODE -ne 0) { throw "Fallo al restaurar el backup en la VM" }
    $ErrorActionPreference = "Stop"
    Write-Host "Mundo restaurado desde $($backup.Name)"
  }
}

# ---------- 7. Resumen ----------
Step "LISTO - Servidor desplegado"
Write-Host @"

  Java:    $addr : 25565
  Bedrock: $addr : 19132 (UDP)

  Boton de encendido (compartelo con tus amigos): guardado en start-url.txt

  La VM esta ENCENDIDA ahora. Si nadie entra, se apaga sola a los 20 min y la
  IP se borra -> coste en reposo ~1,4 EUR/mes. Para encender otro dia: abre la
  URL de start-url.txt o ejecuta scripts\start.ps1 (NUNCA 'az vm start' a secas).

"@
