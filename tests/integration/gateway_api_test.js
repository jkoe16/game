#!/usr/bin/env node
// 게이트웨이 방 조회·빠른 매칭 API 테스트 (Godot 불필요, Node.js 18+)
// 실행: node tests/integration/gateway_api_test.js
"use strict";
const http = require("http");
const net = require("net");
const path = require("path");
const { spawn } = require("child_process");

const ROOT = path.resolve(__dirname, "../..");
const PORT = 18090;
let pass = 0, fail = 0;
function check(cond, label, detail = "") {
  if (cond) { pass++; console.log("  PASS  " + label); }
  else { fail++; console.log("  FAIL  " + label + (detail ? "  -- " + detail : "")); }
}

function get(p) {
  return new Promise((resolve, reject) => {
    http.get({ host: "127.0.0.1", port: PORT, path: p }, (res) => {
      let body = "";
      res.on("data", (d) => (body += d));
      res.on("end", () => {
        try { resolve({ status: res.statusCode, cors: res.headers["access-control-allow-origin"], json: JSON.parse(body) }); }
        catch (e) { resolve({ status: res.statusCode, json: null }); }
      });
    }).on("error", reject);
  });
}

/** WebSocket 업그레이드 요청만 보내고 연결을 붙잡아 둔다 (게이트웨이가 사람 1명으로 셈) */
function hold(p) {
  return new Promise((resolve) => {
    const s = net.connect(PORT, "127.0.0.1", () => {
      s.write(`GET ${p} HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n` +
        `Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n`);
      setTimeout(() => resolve(s), 50);
    });
    s.on("error", () => {});
  });
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const gw = spawn(process.execPath, [path.join(ROOT, "server/cloud/gateway.js")], {
    env: { ...process.env, PORT: String(PORT), PORT_BASE: "28000", GODOT_BIN: path.join(__dirname, "fake_godot.js"),
      GAME_DIR: ROOT, LOBBY_MAX: "3", MAX_SERVERS: "3", MAX_PUBLIC_LOBBIES: "3", IDLE_SEC: "30" },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let log = "";
  gw.stdout.on("data", (d) => (log += d));
  gw.stderr.on("data", (d) => (log += d));
  for (let i = 0; i < 50 && !log.includes("GATEWAY_READY"); i++) await sleep(100);
  const socks = [];
  try {
    let r = await get("/api/room/ABCD");
    check(r.status === 200 && r.json.ok && r.json.exists === false && r.json.can_create === true, "unknown room → exists:false, can_create", JSON.stringify(r.json));
    check(r.cors === "*", "API allows browser (CORS)");
    r = await get("/api/room/x!");
    check(r.status === 400 && r.json.error === "bad_code", "invalid code → 400 bad_code", JSON.stringify(r.json));

    socks.push(await hold("/r/ABCD"));
    await sleep(300);
    r = await get("/api/room/abcd");
    check(r.json.exists === true && r.json.players === 1 && r.json.full === false, "room appears once someone joins (case-insensitive)", JSON.stringify(r.json));

    r = await get("/api/quickmatch");
    check(r.json.path === "/" && r.json.max_players === 3, "quick match → main public plaza first", JSON.stringify(r.json));
    for (let i = 0; i < 3; i++) socks.push(await hold("/"));
    await sleep(300);
    r = await get("/api/quickmatch");
    check(r.json.path === "/p/2" && r.json.players === 0, "public plaza full → quick match opens plaza 2", JSON.stringify(r.json));
    socks.push(await hold("/p/2"));
    await sleep(300);
    r = await get("/api/quickmatch");
    check(r.json.path === "/p/2" && r.json.players === 1, "next player joins plaza 2 (fills before opening more)", JSON.stringify(r.json));
    check(/\[public2\/lobby\] starting/.test(log), "plaza 2 runs its own server");

    // 서버 3개(ABCD, 공개1, 공개2) 모두 사람이 있음 → 새 방을 만들 자리 없음
    r = await get("/api/room/NEWR");
    check(r.json.exists === false && r.json.can_create === false, "no free server slot → can_create:false", JSON.stringify(r.json));
    r = await get("/api/room/ABCD");
    check(r.json.can_create === true, "existing room can still be joined when slots are full", JSON.stringify(r.json));

    r = await get("/healthz");
    check(r.json.ok && r.json.servers.some((s) => s.room === "public2"), "healthz lists plaza 2", JSON.stringify(r.json.servers));
  } finally {
    socks.forEach((s) => s.destroy());
    gw.kill("SIGTERM");
  }
  console.log(`GATEWAY_API_RESULT passed=${pass} failed=${fail}`);
  if (fail) { console.log(log.split("\n").slice(-30).join("\n")); process.exit(1); }
}
main().catch((e) => { console.error(e); process.exit(1); });
