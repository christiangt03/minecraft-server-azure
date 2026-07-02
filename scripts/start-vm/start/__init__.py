"""HTTP trigger: enciende el servidor de Minecraft bajo demanda.

GET  -> devuelve una pagina con un boton.
POST -> via Managed Identity: crea la IP publica si no existe (misma con nombre
        y DNS que gestiona Terraform), la conecta a la NIC y arranca la VM.
        La IP se borra al apagarse (Function 'cleanup') para no pagarla en reposo.
No usa dependencias externas (solo stdlib + azure.functions)."""
import json
import os
import time
import urllib.request

import azure.functions as func

SUBSCRIPTION_ID = os.environ["SUBSCRIPTION_ID"]
RESOURCE_GROUP = os.environ["RESOURCE_GROUP"]
VM_NAME = os.environ["VM_NAME"]
LOCATION = os.environ["LOCATION"]
NIC_NAME = os.environ["NIC_NAME"]
PIP_NAME = os.environ["PIP_NAME"]
DNS_LABEL = os.environ["DNS_LABEL"]

ARM = "https://management.azure.com"
NET = (f"{ARM}/subscriptions/{SUBSCRIPTION_ID}/resourceGroups/{RESOURCE_GROUP}"
       f"/providers/Microsoft.Network")
NET_API = "2023-09-01"

PAGE = """<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Encender servidor Minecraft</title>
<style>
 body{font-family:system-ui,sans-serif;background:#1b1b1b;color:#eee;display:flex;
      min-height:100vh;align-items:center;justify-content:center;margin:0}
 .card{background:#262626;padding:2rem 2.5rem;border-radius:16px;text-align:center;max-width:420px}
 button{font-size:1.1rem;padding:.9rem 1.6rem;border:0;border-radius:10px;background:#3ba55d;
        color:#fff;cursor:pointer}
 button:disabled{background:#555;cursor:default}
 #msg{margin-top:1rem;min-height:1.5rem}
</style></head><body><div class="card">
 <h2>🟢 Servidor de Minecraft</h2>
 <p>Pulsa para encender el servidor. Tarda ~2 minutos en estar listo.</p>
 <button id="b" onclick="go()">▶ Encender servidor</button>
 <div id="msg"></div>
</div><script>
 async function go(){
   const b=document.getElementById('b'), m=document.getElementById('msg');
   b.disabled=true; m.textContent='Encendiendo (puede tardar ~1 min)...';
   try{ const r=await fetch(window.location.href,{method:'POST'});
        m.textContent = r.ok ? '✅ Arrancando. Conéctate en ~2 min.' : '❌ Error: '+r.status;
   }catch(e){ m.textContent='❌ '+e; }
 }
</script></body></html>"""


def _arm_token():
    endpoint = os.environ["IDENTITY_ENDPOINT"]
    header = os.environ["IDENTITY_HEADER"]
    url = f"{endpoint}?resource=https://management.azure.com/&api-version=2019-08-01"
    req = urllib.request.Request(url, headers={"X-IDENTITY-HEADER": header})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.load(r)["access_token"]


def _arm(method, url, token, body=None):
    data = json.dumps(body).encode() if body is not None else (b"" if method == "POST" else None)
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as r:
        raw = r.read()
        return r.status, (json.loads(raw) if raw else {})


def _wait_succeeded(url, token, tries=30):
    for _ in range(tries):
        _, obj = _arm("GET", url, token)
        if obj.get("properties", {}).get("provisioningState") == "Succeeded":
            return obj
        time.sleep(3)
    raise TimeoutError(f"provisioningState no llego a Succeeded: {url}")


def _ensure_ip_and_start():
    token = _arm_token()

    # 1. Crear (o reutilizar) la IP publica con el mismo nombre/DNS que usa Terraform.
    pip_url = f"{NET}/publicIPAddresses/{PIP_NAME}?api-version={NET_API}"
    _arm("PUT", pip_url, token, {
        "location": LOCATION,
        "sku": {"name": "Standard"},
        "properties": {
            "publicIPAllocationMethod": "Static",
            "dnsSettings": {"domainNameLabel": DNS_LABEL},
        },
    })
    pip = _wait_succeeded(pip_url, token)

    # 2. Conectarla a la NIC si no lo esta ya.
    nic_url = f"{NET}/networkInterfaces/{NIC_NAME}?api-version={NET_API}"
    _, nic = _arm("GET", nic_url, token)
    ipcfg = nic["properties"]["ipConfigurations"][0]["properties"]
    if ipcfg.get("publicIPAddress", {}).get("id") != pip["id"]:
        ipcfg["publicIPAddress"] = {"id": pip["id"]}
        _arm("PUT", nic_url, token, nic)
        _wait_succeeded(nic_url, token)

    # 3. Arrancar la VM.
    start_url = (f"{ARM}/subscriptions/{SUBSCRIPTION_ID}/resourceGroups/{RESOURCE_GROUP}"
                 f"/providers/Microsoft.Compute/virtualMachines/{VM_NAME}"
                 f"/start?api-version=2023-07-01")
    status, _ = _arm("POST", start_url, token)
    return status


def main(req: func.HttpRequest) -> func.HttpResponse:
    if req.method == "GET":
        return func.HttpResponse(PAGE, mimetype="text/html")
    try:
        status = _ensure_ip_and_start()
        return func.HttpResponse(
            json.dumps({"ok": True, "status": status, "vm": VM_NAME}),
            mimetype="application/json", status_code=202)
    except Exception as exc:  # noqa: BLE001
        return func.HttpResponse(
            json.dumps({"ok": False, "error": str(exc)}),
            mimetype="application/json", status_code=500)
