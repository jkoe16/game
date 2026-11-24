#!/usr/bin/env node
// 3D PARTY WORLD 클라우드 게이트웨이 (의존성 없음, Node.js 18+)
//
// 한 개의 공개 포트(PORT, 기본 8080)로 WebSocket 접속을 받아 경로별로 내부 Godot 서버에 넘긴다.
//   wss://주소/            → 로비 (7777)
//   wss://주소/lobby       → 로비 (7777)
//   wss://주소/obstacle_race, /survival, /racing, /coop, /party → 각 미니게임 서버
// TLS(wss)는 호스팅 서비스(Fly.io, Render, Cloud Run 등)가 앞단에서 처리한다.
//
// GODOT_BIN 이 지정되면 게이트웨이가 Godot 서버 6개를 직접 띄우고, 죽으면 다시 띄운다.
//   GODOT_BIN=/usr/local/bin/godot GAME_DIR=/game node gateway.js
// GODOT_BIN 이 없으면 프록시만 한다 (서버는 따로 실행).
//
// 환경 변수: PORT, GODOT_BIN, GAME_DIR, AUTH_MODE(firebase|dev, 기본 자동), PORT_OFFSET(내부 포트 +N, 테스트용), MINIGAME_ARGS
"use strict";
const http = require("http");
const net = require("net");
const { spawn } = require("child_process");

const PORT = parseInt(process.env.PORT || "8080", 10);
const OFFSET = parseInt(process.env.PORT_OFFSET || "0", 10);
// scripts/modes/mode_registry.gd 의 포트와 같아야 한다
const MODES = { lobby: 7777, obstacle_race: 7781, survival: 7782, racing: 7783, coop: 7784, party: 7785 };
const route = (p) => {
  const name = (p.split("?")[0].replace(/^\/+|\/+$/g, "") || "lobby");
  return Object.prototype.hasOwnProperty.call(MODES, name) ? { name, port: MODES[name] + OFFSET } : null;
};
const status = {};
const children = {};
let stopping = false;

// ------------------------------------------------------------ Godot 서버 관리
function startServer(mode) {
  const args = ["--headless", "--path", process.env.GAME_DIR || ".", "--", "--server", "--transport=ws",
    `--mode=${mode}`, `--port=${MODES[mode] + OFFSET}`];
  if (mode === "lobby") args.push("--routes=gateway");
  else args.push("--lobby=/lobby");
  if (process.env.AUTH_MODE) args.push(`--auth=${process.env.AUTH_MODE}`);
  // 테스트용 추가 인자 (예: MINIGAME_ARGS="--min-players=1 --round-sec=8")
  if (mode !== "lobby" && process.env.MINIGAME_ARGS) args.push(...process.env.MINIGAME_ARGS.split(/\s+/).filter(Boolean));
  const child = spawn(process.env.GODOT_BIN, args, { stdio: ["ignore", "pipe", "pipe"] });
  children[mode] = child;
  status[mode] = { pid: child.pid, started: new Date().toISOString(), restarts: (status[mode]?.restarts ?? -1) + 1 };
  const tag = `[${mode}] `;
  const log = (d) => d.toString().split(/\r?\n/).filter(Boolean).forEach((l) => console.log(tag + l));
  child.stdout.on("data", log);
  child.stderr.on("data", log);
  child.on("exit", (code) => {
    status[mode].pid = null;
    if (stopping) return;
    console.log(`${tag}exited (${code}), restarting in 2s`);
    setTimeout(() => startServer(mode), 2000);
  });
}
if (process.env.GODOT_BIN) Object.keys(MODES).forEach(startServer);

// ------------------------------------------------------------ HTTP + WebSocket 프록시
const server = http.createServer((req, res) => {
  if (req.url === "/healthz" || req.url === "/") {
    res.writeHead(200, { "content-type": "application/json", "access-control-allow-origin": "*" });
    res.end(JSON.stringify({ ok: true, game: "3D PARTY WORLD", modes: Object.keys(MODES), servers: status }));
    return;
  }
  res.writeHead(404);
  res.end("not found");
});

server.on("upgrade", (req, client, head) => {
  const r = route(req.url || "/");
  if (!r) {
    client.end("HTTP/1.1 404 Not Found\r\n\r\n");
    return;
  }
  const upstream = net.connect(r.port, "127.0.0.1", () => {
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
  const close = () => { upstream.destroy(); client.destroy(); };
  upstream.on("error", () => {
    if (!client.destroyed) client.end("HTTP/1.1 503 Service Unavailable\r\n\r\n");
    close();
  });
  client.on("error", close);
  upstream.on("close", close);
  client.on("close", close);
});

server.listen(PORT, () => console.log(`GATEWAY_READY port=${PORT} modes=${Object.keys(MODES).join(",")}`));
const shutdown = () => {
  stopping = true;
  for (const c of Object.values(children)) c.kill("SIGTERM");
  setTimeout(() => process.exit(0), 300);
};
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
