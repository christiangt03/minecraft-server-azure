"""Webhook de la alerta de deallocate: borra la IP publica mientras el server duerme.

Espera a que la VM este realmente deallocated, desconecta la IP de la NIC y la
borra (la IP Standard cobra ~3 EUR/mes aunque la VM este apagada). La Function
'start' la recrea con el mismo nombre/DNS al encender. Idempotente: si la IP ya
no existe, no hace nada. Solo stdlib + azure.functions."""
import json
import os
import time
import urllib.error
import urllib.request

import azure.functions as func

SUBSCRIPTION_ID = os.environ["SUBSCRIPTION_ID"]
RESOURCE_GROUP = os.environ["RESOURCE_GROUP"]
VM_NAME = os.environ["VM_NAME"]
NIC_NAME = os.environ["NIC_NAME"]
PIP_NAME = os.environ["PIP_NAME"]

ARM = "https://management.azure.com"
NET = (f"{ARM}/subscriptions/{SUBSCRIPTION_ID}/resourceGroups/{RESOURCE_GROUP}"
       f"/providers/Microsoft.Network")
NET_API = "2023-09-01"


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


def _vm_deallocated(token):
    url = (f"{ARM}/subscriptions/{SUBSCRIPTION_ID}/resourceGroups/{RESOURCE_GROUP}"
           f"/providers/Microsoft.Compute/virtualMachines/{VM_NAME}"
           f"/instanceView?api-version=2023-07-01")
    _, view = _arm("GET", url, token)
    return any(s.get("code") == "PowerState/deallocated" for s in view.get("statuses", []))


def _cleanup():
    token = _arm_token()

    # 1. No tocar nada si la VM no esta deallocated (p.ej. alguien la reencendio).
    #    Reintenta ~2 min por si la alerta llega antes de acabar el deallocate.
    for _ in range(8):
        if _vm_deallocated(token):
            break
        time.sleep(15)
    else:
        return {"ok": True, "skipped": "la VM no esta deallocated; no se toca la IP"}

    # 2. Desconectar la IP de la NIC si sigue conectada.
    nic_url = f"{NET}/networkInterfaces/{NIC_NAME}?api-version={NET_API}"
    _, nic = _arm("GET", nic_url, token)
    ipcfg = nic["properties"]["ipConfigurations"][0]["properties"]
    if "publicIPAddress" in ipcfg:
        del ipcfg["publicIPAddress"]
        _arm("PUT", nic_url, token, nic)
        _wait_succeeded(nic_url, token)

    # 3. Borrar la IP (404 = ya no existe, perfecto).
    pip_url = f"{NET}/publicIPAddresses/{PIP_NAME}?api-version={NET_API}"
    try:
        _arm("DELETE", pip_url, token)
    except urllib.error.HTTPError as exc:
        if exc.code != 404:
            raise
    return {"ok": True, "deleted": PIP_NAME}


def main(req: func.HttpRequest) -> func.HttpResponse:
    try:
        result = _cleanup()
        return func.HttpResponse(json.dumps(result),
                                 mimetype="application/json", status_code=200)
    except Exception as exc:  # noqa: BLE001
        return func.HttpResponse(json.dumps({"ok": False, "error": str(exc)}),
                                 mimetype="application/json", status_code=500)
