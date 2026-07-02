#!/usr/bin/env python3
"""Cliente RCON minimo para Minecraft (sin dependencias externas).

Uso:
  rcon.py cmd "save-all flush"   -> ejecuta un comando y muestra la respuesta
  rcon.py list_count             -> imprime solo el numero de jugadores conectados

Lee RCON_PASSWORD y RCON_PORT del entorno (ver /etc/mc/env)."""
import os
import re
import socket
import struct
import sys

HOST = "127.0.0.1"
PORT = int(os.environ.get("RCON_PORT", "25575"))
PASSWORD = os.environ.get("RCON_PASSWORD", "")

TYPE_AUTH = 3
TYPE_COMMAND = 2


def _send(sock, req_id, req_type, payload):
    data = struct.pack("<ii", req_id, req_type) + payload.encode("utf-8") + b"\x00\x00"
    sock.sendall(struct.pack("<i", len(data)) + data)


def _recv(sock):
    raw_len = sock.recv(4)
    if len(raw_len) < 4:
        raise IOError("respuesta RCON vacia")
    length = struct.unpack("<i", raw_len)[0]
    data = b""
    while len(data) < length:
        chunk = sock.recv(length - len(data))
        if not chunk:
            break
        data += chunk
    req_id, _req_type = struct.unpack("<ii", data[:8])
    body = data[8:-2].decode("utf-8", errors="replace")
    return req_id, body


def run(command):
    with socket.create_connection((HOST, PORT), timeout=10) as sock:
        _send(sock, 1, TYPE_AUTH, PASSWORD)
        auth_id, _ = _recv(sock)
        if auth_id == -1:
            raise SystemExit("Auth RCON fallida (password incorrecta)")
        _send(sock, 2, TYPE_COMMAND, command)
        _, body = _recv(sock)
        return body


def main():
    if len(sys.argv) < 2:
        raise SystemExit("uso: rcon.py [cmd '<comando>' | list_count]")
    mode = sys.argv[1]
    if mode == "list_count":
        resp = run("list")
        m = re.search(r"(\d+)", resp)
        print(m.group(1) if m else "0")
    elif mode == "cmd":
        print(run(sys.argv[2] if len(sys.argv) > 2 else ""))
    else:
        raise SystemExit("modo desconocido: " + mode)


if __name__ == "__main__":
    main()
