#!/usr/bin/env node
// 3D PARTY WORLD 클라우드 게이트웨이 (의존성 없음, Node.js 18+)
//
// 한 개의 공개 포트(PORT, 기본 8080)로 WebSocket 접속을 받아 경로별로 내부 Godot 서버에 넘긴다.
//   wss://주소/                  → 공개 광장 (로비)
//   wss://주소/obstacle_race     → 공개 미니게임 (survival, racing, coop, party 도 같음)
//   wss://주소/r/K7QP            → 방 K7QP 전용 광장
//   wss://주소/r/K7QP/racing     → 방 K7QP 전용 미니게임
// 서버(방 × 모드)는 누가 접속할 때 켜지고, IDLE_SEC 동안 아무도 없으면 꺼진다 (무료 호스팅의 작은 메모리용).
// TLS(wss)는 호스팅 서비스(Render, Fly.io 등)가 앞단에서 처리한다.
//
// 환경 변수
//   PORT        공개 포트 (기본 8080)
//   GODOT_BIN   Godot 실행 파일 (필수)
//   GAME_DIR    프로젝트 폴더 (기본 .)
//   AUTH_MODE   firebase | dev (기본: config/firebase.cfg 있으면 firebase)
//   MAX_SERVERS 동시에 켤 수 있는 Godot 서버 수 (기본 8, 서버 하나 약 50MB)
//   IDLE_SEC    빈 서버를 끄기까지 기다리는 시간 (기본 60)
//   PORT_BASE   내부 포트 시작 번호 (기본 20000)
//   MINIGAME_ARGS 미니게임 서버 추가 인자 (테스트용, 예: "--min-players=1 --round-sec=8")
"use strict";
const http = require("http");
const net = require("net");
const { spawn } = require("child_process");

const PORT = parseInt(process.env.PORT || "8080", 10);
const MAX_SERVERS = parseInt(process.env.MAX_SERVERS || "8", 10);
const IDLE_SEC = parseFloat(process.env.IDLE_SEC || "60");
const PORT_BASE = parseInt(process.env.PORT_BASE || "20000", 10);
const START_TIMEOUT_MS = 30000;
// scripts/modes/mode_registry.gd 의 모드 ID와 같아야 한다
const MODES = ["lobby", "obstacle_race", "survival", "racing", "coop", "party"];
const ROOM_RE = /^[A-Z0-9]{4,8}$/;

/** 경로 → { room, mode } 또는 null.  room "" = 공개 */
function parsePath(url) {
  const parts = (url || "/").split("?")[0].split("/").filter(Boolean);
  let room = "";
  if (parts[0] === "r") {
    if (!parts[1]) return null;
    room = parts[1].toUpperCase();
    if (!ROOM_RE.test(room)) return null;
    parts.splice(0, 2);
  }
  if (parts.length > 1) return null;
  const mode = parts[0] || "lobby";
  return MODES.includes(mode) ? { room, mode } : null;
}

// ------------------------------------------------------------ Godot 서버 관리 (필요할 때 켜고 비면 끔)
const servers = new Map(); // key "ROOM/mode" → { room, mode, port, child, ready: Promise, conns, idleTimer, started }
let stopping = false;

function allocPort() {
  const used = new Set([...servers.values()].map((s) => s.port));
  for (let p = PORT_BASE; p < PORT_BASE + 1000; p++) if (!used.has(p)) return p;
  return -1;
}

function waitForPort(port, child) {
  return new Promise((resolve, reject) => {
    const t0 = Date.now();
    const tryOnce = () => {
      if (child.exitCode !== null) return reject(new Error("server exited during start"));
      const s = net.connect(port, "127.0.0.1", () => { s.destroy(); resolve(); });
      s.on("error", () => {
        s.destroy();
        if (Date.now() - t0 > START_TIMEOUT_MS) reject(new Error("start timeout"));
        else setTimeout(tryOnce, 150);
      });
    };
    tryOnce();
  });
}

function startServer(room, mode) {
  const key = `${room}/${mode}`;
  const port = allocPort();
  const prefix = room ? `/r/${room}` : "";
  const args = ["--headless", "--path", process.env.GAME_DIR || ".", "--", "--server", "--transport=ws",
    `--mode=${mode}`, `--port=${port}`];
  if (mode === "lobby") args.push("--routes=gateway", `--route-prefix=${prefix}`);
  else args.push(`--lobby=${prefix}/lobby`);
  if (process.env.AUTH_MODE) args.push(`--auth=${process.env.AUTH_MODE}`);
  if (mode !== "lobby" && process.env.MINIGAME_ARGS) args.push(...process.env.MINIGAME_ARGS.split(/\s+/).filter(Boolean));
  const child = spawn(process.env.GODOT_BIN, args, { stdio: ["ignore", "pipe", "pipe"] });
  const entry = { room, mode, port, child, conns: 0, idleTimer: null, started: new Date().toISOString() };
  servers.set(key, entry);
  const tag = `[${room || "public"}/${mode}] `;
  const log = (d) => d.toString().split(/\r?\n/).filter(Boolean).forEach((l) => console.log(tag + l));
  child.stdout.on("data", log);
  child.stderr.on("data", log);
  child.on("exit", (code) => {
    if (servers.get(key) === entry) servers.delete(key);
    if (!stopping) console.log(`${tag}stopped (${code})`);
  });
  console.log(`${tag}starting on port ${port} (${servers.size}/${MAX_SERVERS})`);
  entry.ready = waitForPort(port, child);
  entry.ready.catch((e) => {
    console.log(`${tag}${e.message}`);
    child.kill("SIGKILL");
  });
  return entry;
}

/** 빈 서버를 잠시 기다렸다가 끈다. 다른 서버가 필요해서 자리가 없으면 오래 빈 서버부터 끈다 */
function scheduleIdle(entry) {
  clearTimeout(entry.idleTimer);
  entry.idleSince = Date.now();
  entry.idleTimer = setTimeout(() => {
    if (entry.conns === 0) {
      console.log(`[${entry.room || "public"}/${entry.mode}] idle ${IDLE_SEC}s → stop`);
      entry.child.kill("SIGTERM");
    }
  }, IDLE_SEC * 1000);
}

function freeIdleSlot() {
  const idle = [...servers.values()].filter((s) => s.conns === 0).sort((a, b) => (a.idleSince || 0) - (b.idleSince || 0));
  if (!idle.length) return false;
  const s = idle[0];
  clearTimeout(s.idleTimer);
  servers.delete(`${s.room}/${s.mode}`);
  s.child.kill("SIGTERM");
  return true;
}

function getServer(room, mode) {
  const key = `${room}/${mode}`;
  const existing = servers.get(key);
  if (existing) return existing;
  if (servers.size >= MAX_SERVERS && !freeIdleSlot()) return null;
  const e = startServer(room, mode);
  scheduleIdle(e); // 아무도 안 붙으면 결국 꺼지도록
  return e;
}

// ------------------------------------------------------------ HTTP + WebSocket 프록시
const server = http.createServer((req, res) => {
  const path = (req.url || "/").split("?")[0];
  if (path === "/healthz" || path === "/") {
    const list = [...servers.values()].map((s) => ({ room: s.room || "public", mode: s.mode, players: s.conns, started: s.started }));
    res.writeHead(200, { "content-type": "application/json", "access-control-allow-origin": "*" });
    res.end(JSON.stringify({ ok: true, game: "3D PARTY WORLD", servers: list, max_servers: MAX_SERVERS }));
    return;
  }
  res.writeHead(404);
  res.end("not found");
});

server.on("upgrade", async (req, client, head) => {
  client.on("error", () => client.destroy());
  const r = parsePath(req.url);
  if (!r || !process.env.GODOT_BIN) {
    client.end("HTTP/1.1 404 Not Found\r\n\r\n");
    return;
  }
  const entry = getServer(r.room, r.mode);
  if (!entry) {
    client.end("HTTP/1.1 503 Service Unavailable\r\nRetry-After: 10\r\n\r\n");
    return;
  }
  // 서버가 켜지는 동안(수 초) 연결을 붙잡아 둔다
  entry.conns++;
  clearTimeout(entry.idleTimer);
  let counted = true;
  const release = () => {
    if (!counted) return;
    counted = false;
    entry.conns--;
    if (entry.conns === 0 && servers.get(`${r.room}/${r.mode}`) === entry) scheduleIdle(entry);
  };
  client.on("close", release);
  try {
    await entry.ready;
  } catch {
    release();
    if (!client.destroyed) client.end("HTTP/1.1 503 Service Unavailable\r\n\r\n");
    return;
  }
  if (client.destroyed) return release();
  const upstream = net.connect(entry.port, "127.0.0.1", () => {
    // 원래 요청을 경로만 "/"로 바꿔 그대로 전달 (Godot WebSocket 서버는 경로를 보지 않음)
    let raw = `GET / HTTP/1.1\r\n`;
    for (let i = 0; i < req.rawHeaders.length; i += 2) raw += `${req.rawHeaders[i]}: ${req.rawHeaders[i + 1]}\r\n`;
    upstream.write(raw + "\r\n");
    if (head && head.length) upstream.write(head);
    upstream.pipe(client);
    client.pipe(upstream);
  });
  upstream.setNoDelay(true);
  client.setNoDelay(true);
  const close = () => { upstream.destroy(); client.destroy(); release(); };
  upstream.on("error", () => {
    if (!client.destroyed) client.end("HTTP/1.1 503 Service Unavailable\r\n\r\n");
    close();
  });
  upstream.on("close", close);
  client.on("close", close);
});

server.listen(PORT, () => console.log(`GATEWAY_READY port=${PORT} max_servers=${MAX_SERVERS} idle=${IDLE_SEC}s`));
const shutdown = () => {
  stopping = true;
  for (const s of servers.values()) s.child.kill("SIGTERM");
  setTimeout(() => process.exit(0), 300);
};
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
