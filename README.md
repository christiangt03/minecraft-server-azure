# Servidor de Minecraft (Java + Bedrock) en Azure — barato y bajo demanda

Servidor **PaperMC + Geyser + Floodgate** (Java 25) en una VM **B2s** de Azure (región `spaincentral`),
pensado para **gastar lo mínimo**: la VM está **apagada por defecto**, se enciende bajo demanda con un
botón web y se **auto-apaga** cuando no hay jugadores. Incluye **backups** al blob y al PC, y **alertas**
de CPU/RAM/disco, apagado y caídas.

## Cómo ahorra
- VM **deallocated** por defecto → 0 € de cómputo mientras está apagada.
- **IP pública bajo demanda**: al apagarse la VM, una Function la **borra** automáticamente
  (deja de facturar); al encender, la recrea con el mismo nombre y DNS.
- **Disco HDD** (`Standard_LRS`): suficiente para este uso y más barato que SSD.
- **Auto-apagado**: si no hay jugadores durante `idle_minutes` (20 por defecto) → backup + apagado.
- Coste real: **≈ 1,4 €/mes en reposo** (solo el disco) + **≈ 0,04 €/h** con el servidor encendido.
  Un 24/7 equivalente serían ~35 €/mes.

## Dirección de conexión
Sustituye `<TU_DNS_LABEL>` por el valor de `dns_label` que definas en `terraform.tfvars`; los
puertos son los que abras en `terraform/network.tf`:
- **Java:** `<TU_DNS_LABEL>.spaincentral.cloudapp.azure.com`, puerto `<PUERTO_JAVA>` (por defecto 25565)
- **Bedrock:** misma dirección, puerto `<PUERTO_BEDROCK>` (UDP, por defecto 19132)

> La IP numérica **cambia en cada ciclo** de encendido/apagado. Comparte siempre el **nombre DNS**, nunca la IP.

---

## 1. Prerrequisitos (una vez)

```bash
# Verifica la cuenta correcta (Azure for Students)
az account show --query "{user:user.name, sub:name}"

# Genera una clave SSH para la VM
ssh-keygen -t ed25519 -f ~/.ssh/mcserver -N ""

# Tu IP pública para el acceso SSH
curl -s https://api.ipify.org
```

Copia `terraform/terraform.tfvars.example` a `terraform/terraform.tfvars` y rellena:
`allowed_ssh_cidr` (tu IP `/32`), `dns_label`, `alert_email`, y opcional `discord_webhook_url`.

## 2. Desplegar la infraestructura

**Camino rápido (Windows):** ejecuta `.\deploy.ps1` en la raíz del repo. Hace todo lo anterior y esto
solo: comprueba herramientas y sesión de Azure, genera la clave SSH y `terraform.tfvars` si faltan
(redetectando tu IP), lanza `init` + `apply`, guarda el botón de encendido en `start-url.txt` y ofrece
restaurar el último backup del mundo de `backups/` por SSH. Con `-SkipRestore` despliega mundo nuevo.

**Camino manual:**

```bash
cd terraform
terraform init
terraform plan      # revisa lo que se va a crear
terraform apply     # crea los recursos (te pedirá confirmar)
```

Al terminar, `terraform output` te da la dirección, comandos de encendido/apagado y datos de backup.

El servidor se instala solo en el primer arranque (cloud-init): descarga la última build **estable**
de Paper vía la API Fill v3 y arranca con **Java 25**. Puedes seguirlo por SSH:
```bash
ssh azuremc@<TU_DNS_LABEL>.spaincentral.cloudapp.azure.com
sudo tail -f /var/log/cloud-init-output.log      # progreso de la instalación
journalctl -u minecraft -f                        # log del servidor
```

## 3. Encender / apagar

> ⚠️ **Nunca uses `az vm start` a secas**: arrancaría la VM **sin IP pública** (sin internet).
> Enciende siempre con el botón web o `scripts/start.ps1`, que primero recrean la IP.

- **Dueño (PC):** `./scripts/start.ps1` y `./scripts/stop.ps1`
- **Amigos (botón web):** habilita la Function (fase 2):
  ```bash
  terraform apply -var="enable_start_function=true"
  ```
  Comparte la URL completa (con clave incluida):
  ```bash
  terraform output -raw start_url
  ```
  La Function corre en `francecentral` (el plan Consumo Y1 no está disponible en `spaincentral`).
- **Apagar:** basta con salir del juego — a los `idle_minutes` sin jugadores hace backup y se apaga sola.
  Manualmente: `scripts/stop.ps1` o `az vm deallocate`.

### IP bajo demanda (cómo funciona)
Al hacerse el deallocate, una alerta del Activity Log llama a la Function `cleanup`, que desconecta
y **borra la IP pública** (tarda 4-8 min, latencia normal de las alertas). Al encender, la Function
`start` la recrea con el mismo nombre/DNS y arranca la VM (~50 s hasta que Minecraft está arriba).
Nota: un `terraform apply` con el servidor apagado recrea la IP — es esperado; se borra sola en el
siguiente ciclo.

## 4. Backups en este PC

Instala azcopy y configura la descarga:
```powershell
winget install Microsoft.Azure.AZCopy.10

# Datos desde terraform output:
$env:MC_STORAGE_ACCOUNT = terraform -chdir=terraform output -raw storage_account
$env:MC_BACKUP_SAS      = terraform -chdir=terraform output -raw backup_sas_token

.\scripts\pull-backups.ps1     # descarga a .\backups
```

Para que sea automático, crea una **Tarea Programada** diaria (Programador de tareas de Windows)
que ejecute `pull-backups.ps1` con esas dos variables de entorno definidas a nivel de usuario.

**Restaurar** un backup: súbelo a la VM, para el server, descomprímelo en `/opt/mc/server` y arráncalo:
```bash
sudo systemctl stop minecraft
sudo -u minecraft tar -xzf mc-YYYYMMDD-HHMMSS.tar.gz -C /opt/mc/server
sudo systemctl start minecraft
```

## 5. Alertas

- **Se apagó (deallocate/powerOff) o caída del host:** alertas de Azure → **email** (`alert_email`).
  El deallocate normal también dispara el email: es por diseño (confirma que se apagó).
- **CPU / RAM / disco:** script en la VM cada 5 min → **Discord** (opcional, si configuras el webhook).
  Umbrales en `terraform.tfvars` (`cpu_threshold`, `ram_threshold`, `disk_threshold`).
- **Crash del proceso Minecraft:** systemd `OnFailure` → alerta + reinicio automático.

## Estructura

```
terraform/      IaC (red, VM, storage, key vault, alertas, functions start/cleanup)
scripts/        scripts de la VM (rcon, backup, monitor, idle-stop, setup),
                función de arranque (start-vm/) y utilidades de PC (*.ps1)
backups/        destino local de los backups
```

## Notas de coste / operación
- La dirección estable es el **DNS** (`dns_label`); la IP se crea y destruye en cada ciclo.
- `use_spot=true` abarata el cómputo pero la VM puede ser desalojada (recuperable).
- Los backups del blob se borran automáticamente tras `backup_retention_days` (30 por defecto).
- Cambiar `cloud-init.yaml` o los scripts de la VM **recrea la VM** (custom_data): haz backup del
  mundo antes de aplicar. Tras recrearla, limpia la huella SSH:
  `ssh-keygen -R <TU_DNS_LABEL>.spaincentral.cloudapp.azure.com`.
