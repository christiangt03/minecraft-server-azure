// Proxy TCP wake-on-connect para Minecraft Java.
// - Si la VM responde: reenvia el trafico tal cual (jugador <-> servidor).
// - Si la VM esta apagada:
//     * ping de la lista de servidores -> MOTD "apagado, entra para encenderlo"
//       (el ping NO enciende el servidor; solo el intento real de entrar)
//     * intento de login -> llama a la Function start y devuelve un kick
//       "encendiendo, vuelve en 1-2 min"
// Sin dependencias; corre en Container Apps con escala a cero.
'use strict';
const net = require('net');
const https = require('https');

const BACKEND_HOST = process.env.BACKEND_HOST;
const BACKEND_PORT = +(process.env.BACKEND_PORT || 25565);
const LISTEN_PORT = +(process.env.LISTEN_PORT || 25565);
const START_URL = process.env.START_URL;
const COOLDOWN_MS = +(process.env.START_COOLDOWN_MS || 90000);

let lastStart = 0;
function callStart() {
  if (Date.now() - lastStart < COOLDOWN_MS) return;
  lastStart = Date.now();
  https.get(START_URL, (res) => {
    console.log(`start -> HTTP ${res.statusCode}`);
    res.resume();
  }).on('error', (err) => {
    console.error('fallo llamando a start:', err.message);
    lastStart = 0; // permite reintentar sin esperar el cooldown
  });
}

// --- protocolo Minecraft: solo lo minimo (VarInt, String, framing) ---
function varInt(n) {
  const out = [];
  do {
    let b = n & 0x7f;
    n >>>= 7;
    if (n) b |= 0x80;
    out.push(b);
  } while (n);
  return Buffer.from(out);
}
function readVarInt(buf, off) {
  let n = 0, shift = 0, i = off;
  while (true) {
    if (i >= buf.length) return null; // incompleto: esperar mas datos
    const b = buf[i++];
    n |= (b & 0x7f) << shift;
    if (!(b & 0x80)) return [n >>> 0, i];
    shift += 7;
    if (shift > 35) throw new Error('varint invalido');
  }
}
function mcString(s) {
  const b = Buffer.from(s, 'utf8');
  return Buffer.concat([varInt(b.length), b]);
}
function packet(id, payload) {
  const body = Buffer.concat([varInt(id), payload]);
  return Buffer.concat([varInt(body.length), body]);
}

const STATUS_JSON = JSON.stringify({
  version: { name: 'Dormido', protocol: -1 },
  players: { max: 0, online: 0 },
  description: { text: '⏸ Servidor apagado — entra para encenderlo', color: 'yellow' },
});
const KICK_JSON = JSON.stringify({
  text: '⏳ Encendiendo el servidor... vuelve a entrar en 1-2 minutos',
  color: 'gold',
});

// Responde como un servidor Minecraft cuando la VM no esta disponible.
function fallback(sock, initial) {
  let buf = initial;
  let inStatus = false;
  sock.on('data', (d) => {
    buf = Buffer.concat([buf, d]);
    parse();
  });
  function parse() {
    try {
      while (true) {
        const frame = readVarInt(buf, 0);
        if (!frame) return;
        const [len, bodyOff] = frame;
        if (len > 4096) return sock.destroy(); // no es un cliente Minecraft
        if (buf.length < bodyOff + len) return;
        const pkt = buf.subarray(bodyOff, bodyOff + len);
        buf = buf.subarray(bodyOff + len);
        const [id, p0] = readVarInt(pkt, 0);
        if (!inStatus) {
          if (id !== 0x00) return sock.destroy();
          let p = p0;
          [, p] = readVarInt(pkt, p); // version de protocolo
          const [strLen, strOff] = readVarInt(pkt, p); // direccion usada
          p = strOff + strLen + 2; // saltar direccion + puerto
          const [nextState] = readVarInt(pkt, p);
          if (nextState === 1) {
            inStatus = true;
          } else { // 2 = login, 3 = transfer: intento real de entrar
            console.log('intento de login -> despertando el servidor');
            callStart();
            sock.end(packet(0x00, mcString(KICK_JSON)));
            return;
          }
        } else if (id === 0x00) { // status request
          sock.write(packet(0x00, mcString(STATUS_JSON)));
        } else if (id === 0x01) { // ping: devolver el mismo payload
          sock.end(packet(0x01, pkt.subarray(p0, p0 + 8)));
          return;
        }
      }
    } catch {
      sock.destroy();
    }
  }
  parse();
}

const server = net.createServer((client) => {
  client.on('error', () => {});
  let buffered = Buffer.alloc(0);
  const collect = (d) => { buffered = Buffer.concat([buffered, d]); };
  client.on('data', collect);

  let settled = false;
  const backend = net.connect({ host: BACKEND_HOST, port: BACKEND_PORT });
  backend.setTimeout(4000);
  backend.once('connect', () => {
    settled = true;
    backend.setTimeout(0);
    client.removeListener('data', collect);
    if (buffered.length) backend.write(buffered);
    client.pipe(backend);
    backend.pipe(client);
    backend.on('error', () => client.destroy());
    client.on('error', () => backend.destroy());
    client.on('close', () => backend.destroy());
    backend.on('close', () => client.destroy());
  });
  backend.on('timeout', () => backend.destroy(new Error('timeout')));
  backend.on('error', (err) => {
    if (settled) return;
    settled = true;
    console.log(`servidor no disponible (${err.message})`);
    client.removeListener('data', collect);
    fallback(client, buffered);
  });
});
server.on('error', (err) => {
  console.error('error del listener:', err.message);
  process.exit(1);
});
server.listen(LISTEN_PORT, () => console.log(`wake-proxy escuchando en :${LISTEN_PORT} -> ${BACKEND_HOST}:${BACKEND_PORT}`));
