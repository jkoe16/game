#!/usr/bin/env node
// 게이트웨이 테스트용 가짜 Godot 서버: "--port=N" 으로 TCP를 열고 연결을 그냥 붙잡고 있는다.
// (gateway_api_test.js 가 GODOT_BIN 으로 사용. Godot 없이 게이트웨이 로직만 빠르게 검증)
"use strict";
const net = require("net");
const arg = process.argv.find((a) => a.startsWith("--port="));
const port = parseInt(arg ? arg.slice(7) : "0", 10);
const srv = net.createServer((s) => s.on("error", () => {}));
srv.listen(port, "127.0.0.1");
process.on("SIGTERM", () => process.exit(0));
