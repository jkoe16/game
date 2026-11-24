// 테스트용 "들쭉날쭉한 인터넷" TCP 프록시: 클라이언트→서버 데이터를 순서는 지키되 0~MAX_MS씩 몰아서 늦게 보낸다.
// 사용법: node jitter_proxy.js <listen_port> <target_port> [max_ms]
"use strict";
const net = require("net");
const [listen, target, maxMs] = [parseInt(process.argv[2]), parseInt(process.argv[3]), parseInt(process.argv[4] || "300")];
net.createServer((c) => {
  const up = net.connect(target, "127.0.0.1");
  c.setNoDelay(true); up.setNoDelay(true);
  let q = [];
  let holdUntil = 0;
  // 가끔(평균 1초에 한 번) 0~maxMs 동안 막았다가 한꺼번에 내보낸다 (TCP 재전송/모바일 지연 흉내)
  const pump = () => {
    const now = Date.now();
    if (now >= holdUntil) {
      while (q.length) up.write(q.shift());
      if (Math.random() < 0.05) holdUntil = now + Math.random() * maxMs;
    }
  };
  const timer = setInterval(pump, 16);
  c.on("data", (d) => { q.push(d); pump(); });
  up.on("data", (d) => c.write(d));
  const close = () => { clearInterval(timer); c.destroy(); up.destroy(); };
  c.on("error", close); up.on("error", close); c.on("close", close); up.on("close", close);
}).listen(listen, () => console.log("JITTER_READY"));
