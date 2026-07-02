# Apaga (deallocate) la VM manualmente. Normalmente se apaga sola por inactividad.
param(
  [string]$ResourceGroup,
  [string]$VmName
)
$ErrorActionPreference = "Stop"
if (-not $ResourceGroup) { $ResourceGroup = (terraform -chdir="$PSScriptRoot\..\terraform" output -raw resource_group) }
if (-not $VmName)        { $VmName        = (terraform -chdir="$PSScriptRoot\..\terraform" output -raw vm_name) }
Write-Host "Apagando (deallocate) $VmName ..."
az vm deallocate -g $ResourceGroup -n $VmName
Write-Host "Apagada. No se paga computo mientras este apagada."
