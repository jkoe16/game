// 테스트용 "끊기는 인터넷" TCP 프록시 (재접속 검증).
// 사용법: node drop_proxy.js <listen_port> <target_port> <mode> <at_sec>
//   mode = cut       : at_sec초에 그때 열려 있던 연결을 양쪽 모두 즉시 끊는다 (와이파이 끊김 → 양쪽이 바로 알아챔)
//        = blackhole : at_sec초에 그때 열려 있던 연결을 "조용히" 막는다. 데이터를 더 이상 전달하지 않고,
//                      클라이언트가 연결을 닫아도 서버 쪽 연결은 열어 둔다 (서버는 끊긴 줄 모름 → 입력 끊김으로 감지해야 함)
//   at_sec 이후에 새로 들어온 연결은 정상 전달한다 (다시 연결된 인터넷).
"use strict";
const net = require("net");
const [listen, target, mode, atSec] = [parseInt(process.argv[2]), parseInt(process.argv[3]), process.argv[4], parseFloat(process.argv[5])];
const conns = new Set();
net.createServer((c) => {
  const up = net.connect(target, "127.0.0.1");
  c.setNoDelay(true); up.setNoDelay(true);
  const conn = { c, up, dead: false };
  conns.add(conn);
  c.on("data", (d) => { if (!conn.dead) up.write(d); });
  up.on("data", (d) => { if (!conn.dead) c.write(d); });
  const close = () => {
    conns.delete(conn);
    c.destroy();
    if (!conn.dead || mode !== "blackhole") up.destroy();  // 블랙홀: 서버 쪽은 열어 둔 채로
  };
  c.on("error", close); up.on("error", close); c.on("close", close); up.on("close", close);
}).listen(listen, () => console.log(`DROP_PROXY_READY ${mode} at ${atSec}s`));

setTimeout(() => {
  console.log(`DROP ${mode}: ${conns.size} connection(s)`);
  for (const conn of [...conns]) {
    conn.dead = true;
    if (mode === "cut") { conn.c.destroy(); conn.up.destroy(); }
  }
}, atSec * 1000);
