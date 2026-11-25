// 통합 테스트 결과 판정. 사용법: node check_results.js <scenario> <log_dir>
const fs = require("fs");
const path = require("path");

const [scenario, dir] = process.argv.slice(2);
const WALK_SPEED = 6.5;
let pass = 0, fail = 0;

function check(cond, label, detail = "") {
  if (cond) { pass++; console.log("  PASS  " + label); }
  else { fail++; console.log("  FAIL  " + label + (detail ? "  -- " + detail : "")); }
}

function result(name, tag) {
  const file = path.join(dir, name + ".log");
  if (!fs.existsSync(file)) return null;
  const line = fs.readFileSync(file, "utf8").split(/\r?\n/).find(l => l.startsWith(tag + " "));
  return line ? JSON.parse(line.slice(tag.length + 1)) : null;
}

function scriptErrors(name) {
  const file = path.join(dir, name + ".log");
  if (!fs.existsSync(file)) return ["missing log"];
  return fs.readFileSync(file, "utf8").split(/\r?\n/).filter(l => /SCRIPT ERROR|Parse Error|Invalid call|Invalid access/.test(l));
}

const NO_MAIN_SERVER = ["authflow", "minigames", "touch", "offline", "gateway", "rooms"].includes(scenario);
const server = NO_MAIN_SERVER ? { players: [], stats: {} } : result("server", "SERVER_RESULT");
if (!NO_MAIN_SERVER) check(server !== null, "server produced a report");
if (!server) process.exit(1);
const logs = fs.readdirSync(dir).filter(f => f.endsWith(".log")).map(f => f.slice(0, -4));
for (const n of logs) {
  const errs = scriptErrors(n);
  check(errs.length === 0, `no script errors in ${n}`, errs.slice(0, 3).join(" | "));
}
const byNick = Object.fromEntries(server.players.map(p => [p.nickname, p]));

function dist(a, b) { return Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]); }

if (scenario === "basic" || scenario === "ws") {
  const w1 = result("walker1", "CLIENT_RESULT");
  const w2 = result("walker2", "CLIENT_RESULT");
  check(w1 && w1.welcomed && w2 && w2.welcomed, "two clients joined");
  check(w1 && w2 && w1.remote_ids_seen.includes(w2.id) && w2.remote_ids_seen.includes(w1.id), "clients see each other");
  check(w1 && w1.snapshots > 250, "client received snapshots at ~30Hz", w1 && String(w1.snapshots));
  check(w1 && w1.distance_moved > 30, "bot actually moved", w1 && String(w1.distance_moved));
  if (w1 && w2) {
    // w1이 본 w2의 위치 vs w2 자신의 위치 (보간 지연 100ms + 종료 시점 차이 허용)
    // 두 봇이 거의 동시에 종료하므로 먼저 나간 쪽은 상대 목록에서 이미 제거될 수 있다 → 남아 있는 방향으로 비교
    const seen = w1.remote_positions[String(w2.id)] ? [w1.remote_positions[String(w2.id)], w2.pos] : w2.remote_positions[String(w1.id)] ? [w2.remote_positions[String(w1.id)], w1.pos] : null;
    check(seen && dist(seen[0], seen[1]) < 2.5, "remote position matches owner's position", seen ? dist(seen[0], seen[1]).toFixed(2) + "m" : "no remote view recorded");
    check(w1.max_correction < 0.5, "prediction corrections small (<0.5m)", String(w1.max_correction) + " / count " + w1.corrections);
  }
  const ks = server.stats.kicked || {};
  const rs = server.stats.rejected || {};
  check((ks.too_many_violations || 0) >= 1, "cheater kicked for violations", JSON.stringify(ks));
  check((ks.input_flood || 0) >= 1, "flooder kicked for input flood", JSON.stringify(ks));
  check((rs.version_mismatch || 0) >= 1, "old protocol rejected", JSON.stringify(rs));
  check((rs.hello_timeout || 0) >= 1, "silent peer timed out", JSON.stringify(rs));
  const cheat = result("cheat", "CLIENT_RESULT");
  check(cheat && cheat.rejected === "too_many_violations", "cheater notified of kick", cheat && cheat.rejected);
  const flood = result("flood", "CLIENT_RESULT");
  check(flood && flood.rejected === "input_flood", "flooder notified of kick", flood && flood.rejected);
  for (const p of server.players) {
    check(p.max_speed <= WALK_SPEED + 0.5, `server-side speed bounded for ${p.nickname}`, String(p.max_speed));
  }
  check(server.players.length === 2 && byNick.Walker1 && byNick.Walker2, "only the two honest clients remain", server.players.map(p => p.nickname).join(","));
}

if (scenario === "capacity") {
  const results = [];
  for (let i = 1; i <= 9; i++) results.push(result("walker" + i, "CLIENT_RESULT"));
  const joined = results.filter(r => r && r.welcomed);
  const full = results.filter(r => r && r.rejected === "room_full");
  check(joined.length === 8, "exactly 8 players joined", String(joined.length));
  check(full.length === 1, "9th player rejected with room_full", String(full.length));
  check(joined.every(r => r.remote_ids_seen.length === 7), "every player sees the other 7", joined.map(r => r.remote_ids_seen.length).join(","));
  check(server.players.length === 8, "server holds 8 players", String(server.players.length));
  for (const p of server.players) check(p.max_speed <= WALK_SPEED + 0.5, `speed bounded for ${p.nickname}`, String(p.max_speed));
}

if (scenario === "auth") {
  const guest = result("guest", "CLIENT_RESULT");
  const e1 = result("email1", "CLIENT_RESULT");
  const e2 = result("email2", "CLIENT_RESULT");
  const forged = result("forged", "CLIENT_RESULT");
  const notoken = result("notoken", "CLIENT_RESULT");
  const badpw = result("badpw", "CLIENT_RESULT");
  check(guest && guest.welcomed, "guest (anonymous Firebase token) admitted");
  check(e1 && e1.welcomed, "email account admitted");
  check(forged && !forged.welcomed && forged.rejected === "auth_failed", "tampered token rejected", forged && forged.rejected);
  check(notoken && !notoken.welcomed && notoken.rejected === "auth_failed", "client without Firebase token rejected", notoken && notoken.rejected);
  check(badpw && !badpw.welcomed && badpw.rejected === "login_failed", "weak password blocked before connecting", badpw && badpw.rejected);
  check(e2 && e2.welcomed, "same account logs in from second device");
  check(e1 && e1.rejected === "logged_in_elsewhere", "first session kicked (one session per account)", e1 && e1.rejected);
  check(guest && guest.resumed >= 1 && guest.welcomed, "guest dropped and resumed its seat (Firebase auth)", guest && `reconnects=${guest.reconnects} resumed=${guest.resumed}`);
  check(e1 && e1.reconnects === 0, "kicked session does not try to reconnect", e1 && String(e1.reconnects));
  check((server.stats.resumed || 0) >= 1, "server counted the Firebase resume", JSON.stringify(server.stats));
  const providers = server.players.map(p => p.nickname + ":" + p.auth_provider).sort().join(",");
  check(providers === "Email2:password,Guest:anonymous", "server holds guest + newest email session with verified providers", providers);
  check((server.stats.rejected.auth_failed || 0) === 2, "server counted 2 auth failures", JSON.stringify(server.stats.rejected));
  const srvLog = fs.readFileSync(path.join(dir, "server.log"), "utf8");
  check(/auth failed for peer \d+: signature/.test(srvLog), "tampered token failed specifically on signature check");
  check(/Firebase auth enabled/.test(srvLog), "server ran in Firebase auth mode");
  const ms = fs.existsSync(path.join(dir, "mock_stats.json")) ? JSON.parse(fs.readFileSync(path.join(dir, "mock_stats.json"), "utf8")) : {};
  check((ms["/jwks"] || 0) >= 1, "server fetched public keys (JWKS)", JSON.stringify(ms));
}

if (scenario === "data") {
  for (const ph of ["datapre", "datapost"]) {
    const log = fs.existsSync(path.join(dir, ph + ".log")) ? fs.readFileSync(path.join(dir, ph + ".log"), "utf8") : "";
    const m = /DATA_FLOW_RESULT phase=\w+ passed=(\d+) failed=(\d+)/.exec(log);
    check(m && Number(m[2]) === 0 && Number(m[1]) > 0, `Firestore flow (${ph})`, m ? m[0] : "no result");
    for (const line of log.split(/\r?\n/).filter(l => l.includes("  FAIL  "))) console.log("    " + line.trim());
  }
  const pl = server.players[0];
  check(server.players.length === 1 && pl.nickname === "데이터봇", "server used Firestore nickname, not client's 'WrongNick'", pl && pl.nickname);
  check(pl && pl.appearance && pl.appearance.color === 3 && pl.appearance.hat === 2, "server used Firestore appearance", pl && JSON.stringify(pl.appearance));
  check(server.stats.profile_loaded === 1 && server.stats.data_errors === 0, "server profile load counted, no data errors", JSON.stringify(server.stats));
  const srvLog = fs.readFileSync(path.join(dir, "server.log"), "utf8");
  check(/Firestore enabled \(service account game-server@/.test(srvLog), "server authenticated with service account");
}

if (scenario === "minigames") {
  const modes = ["obstacle_race", "survival", "racing", "coop", "party"];
  for (const m of modes) {
    const srv = result("srv_" + m, "SERVER_RESULT");
    const srvLog = fs.existsSync(path.join(dir, `srv_${m}.log`)) ? fs.readFileSync(path.join(dir, `srv_${m}.log`), "utf8") : "";
    const rr = /ROUND_RESULTS (\[.*\])/.exec(srvLog);
    const results = rr ? JSON.parse(rr[1]) : [];
    check(srv && srv.rounds >= 1, `[${m}] a full round completed on the server`, srv ? `rounds=${srv.rounds} phase=${srv.phase}` : "no report");
    check(results.length === 2 && results.map(r => r.rank).sort().join() === "1,2", `[${m}] both players ranked`, JSON.stringify(results.map(r => [r.nickname, r.rank, r.score])));
    check(results.every(r => r.xp >= 20), `[${m}] everyone earned participation XP`, JSON.stringify(results.map(r => r.xp)));
    const bots = [1, 2].map(b => result(`bot_${m}_${b}`, "CLIENT_RESULT"));
    check(bots.every(c => c && ["waiting", "countdown", "playing", "results"].every(p => c.phases_seen.includes(p))), `[${m}] clients saw waiting→countdown→playing→results`, bots.map(c => c && c.phases_seen.join("/")).join(" | "));
    check(bots.every(c => c && c.my_result && c.my_result.rank >= 1), `[${m}] each client received its own result`);
    const s = results.map(r => r.score).join(" / ");
    if (m === "obstacle_race") check(results.some(r => /완주|진행 ([1-9]\d|[5-9])%/.test(r.score)), `[obstacle_race] bots made real progress on the course`, s);
    if (m === "racing") check(results.some(r => /완주|[23]\/3/.test(r.score)), `[racing] a bot completed at least one lap`, s);
    if (m === "coop") check(results.some(r => /성공|[123]\/3/.test(r.score)), `[coop] team opened at least one gate`, s);
    if (m === "party") check(results.some(r => /[1-9]\d*점/.test(r.score)), `[party] treasure was collected`, s);
    if (m === "survival") check(results.some(r => /생존|버팀/.test(r.score)), `[survival] survival scored`, s);
    const corr = bots.map(c => c ? c.corrections : -1);
    console.log(`    [${m}] small corrections per bot: ${bots.map(c => c && c.small_corrections).join(", ")} (max ${bots.map(c => c && c.max_small_correction).join(", ")} m) · teleports: ${bots.map(c => c && c.teleports).join(", ")}`);
  }
}

if (scenario === "portal") {
  const c = result("traveler", "CLIENT_RESULT");
  check(c && c.transfers.includes("obstacle_race"), "lobby portal moved the player to the obstacle race server", c && JSON.stringify(c.transfers));
  check(c && c.transfers.includes("round_over"), "after results the player was sent back to the lobby", c && JSON.stringify(c.transfers));
  const race = result("srv_race", "SERVER_RESULT");
  check(race && race.rounds >= 1, "race server completed a round with the transferred player", race && `rounds=${race.rounds}`);
  const lobbyLog = fs.readFileSync(path.join(dir, "server.log"), "utf8");
  check((lobbyLog.match(/joined as 'Traveler'/g) || []).length >= 2, "player re-joined the lobby after the round");
}

if (scenario === "jitter") {
  for (const n of ["walker1", "walker2"]) {
    const c = result(n, "CLIENT_RESULT");
    console.log(`    [${n}] corrections=${c && c.corrections} small=${c && c.small_corrections} max_small=${c && c.max_small_correction} teleports=${c && c.teleports} moved=${c && c.distance_moved}`);
    check(c && c.welcomed && c.distance_moved > 30, `${n} joined and moved through the jittery link`);
    check(c && c.small_corrections <= 12, `${n} few position corrections despite jitter (no sliding)`, c && String(c.small_corrections));
  }
}

if (scenario === "gateway") {
  const c = result("traveler", "CLIENT_RESULT");
  check(c && c.welcomed !== undefined, "client connected through the gateway", c && JSON.stringify(c).slice(0, 80));
  check(c && c.transfers.includes("obstacle_race"), "lobby portal moved the player to the race server via gateway path", c && JSON.stringify(c.transfers));
  check(c && c.transfers.includes("round_over"), "after results the player returned to the lobby via gateway path", c && JSON.stringify(c.transfers));
  const gw = fs.readFileSync(path.join(dir, "gateway.txt"), "utf8");
  check(gw.includes("GATEWAY_READY"), "gateway started");
  check((gw.match(/\[public\/lobby\].*joined as 'Traveler'/g) || []).length >= 2, "player re-joined the lobby after the round");
  check((gw.match(/\[public\/obstacle_race\].*joined as 'Traveler'/g) || []).length >= 1, "player joined the race server");
  const errs = gw.split(/\r?\n/).filter(l => /SCRIPT ERROR|Parse Error/.test(l));
  check(errs.length === 0, "no script errors in gateway-managed servers", errs.slice(0, 3).join(" | "));
}

if (scenario === "rooms") {
  const a1 = result("room_a1", "CLIENT_RESULT"), a2 = result("room_a2", "CLIENT_RESULT");
  const b1 = result("room_b1", "CLIENT_RESULT"), p1 = result("public1", "CLIENT_RESULT");
  check(a1 && a1.welcomed && a2 && a2.welcomed && b1 && b1.welcomed && p1 && p1.welcomed, "all room clients joined");
  check(a1 && a2 && a1.remote_ids_seen.includes(a2.id) && a2.remote_ids_seen.includes(a1.id), "same room code (case-insensitive) → players see each other");
  const others = [b1, p1].filter(Boolean).map(x => x.id);
  check(a1 && a2 && !others.some(id => a1.remote_ids_seen.includes(id) || a2.remote_ids_seen.includes(id)), "room ABCD does not see other rooms or public");
  check(b1 && b1.remote_ids_seen.length === 0 && p1 && p1.remote_ids_seen.length === 0, "room WXYZ and public are alone");
  const t = result("traveler", "CLIENT_RESULT");
  check(t && t.transfers.includes("obstacle_race") && t.transfers.includes("round_over"), "room portal → room race → back to room lobby", t && JSON.stringify(t.transfers));
  const gw = fs.readFileSync(path.join(dir, "gateway.txt"), "utf8");
  check(/\[TRIP\/obstacle_race\].*joined as 'Traveler'/.test(gw), "traveler played in the room's own race server");
  check((gw.match(/\[TRIP\/lobby\].*joined as 'Traveler'/g) || []).length >= 2, "traveler returned to the room's lobby");
  check(/idle 4s → stop/.test(gw), "empty servers are stopped automatically");
  const bad = result("bad", "CLIENT_RESULT");
  check(bad && !bad.welcomed, "invalid room code is refused");
  const errs = gw.split(/\r?\n/).filter(l => /SCRIPT ERROR|Parse Error/.test(l));
  check(errs.length === 0, "no script errors in gateway-managed servers", errs.slice(0, 3).join(" | "));
}

if (scenario === "offline") {
  // 서버 없이 로컬 GameMode: 로비 포털 → 장애물 레이스 한 판 → 로비 복귀 (웹 빌드 혼자 하기와 같은 경로)
  const c = result("offline_portal", "CLIENT_RESULT");
  check(c && c.transfers[0] === "obstacle_race", "offline lobby portal opened the obstacle race", c && JSON.stringify(c.transfers));
  const r = result("offline_race", "CLIENT_RESULT");
  const phases = r ? r.phases_seen : [];
  check(["waiting", "countdown", "playing", "results"].every(p => phases.includes(p)), "offline race went through every phase", JSON.stringify(phases));
  check(r && r.my_result && /완주/.test(r.my_result.score) && r.my_result.rank === 1, "offline bot finished the course", r && JSON.stringify(r.my_result));
  check(r && r.transfers.includes("lobby") && r.mode === "lobby", "offline race returned to the lobby after results", r && JSON.stringify(r.transfers));
}

if (scenario === "touch") {
  const log = fs.readFileSync(path.join(dir, "touch.log"), "utf8");
  const m = /TOUCH_TEST_RESULT passed=(\d+) failed=(\d+)/.exec(log);
  check(m && Number(m[2]) === 0 && Number(m[1]) > 0, "mobile touch controls", m ? m[0] : "no result");
}

if (scenario === "authflow") {
  const log = fs.readFileSync(path.join(dir, "authflow.log"), "utf8");
  const m = /AUTH_FLOW_RESULT passed=(\d+) failed=(\d+)/.exec(log);
  check(m && Number(m[2]) === 0 && Number(m[1]) > 0, "client auth flow (Godot)", m ? m[0] : "no result");
  for (const line of log.split(/\r?\n/).filter(l => l.includes("  FAIL  "))) console.log("    " + line.trim());
}

if (scenario === "reconnect") {
  const c = Object.fromEntries(["stay", "cutter", "hole", "dropper", "ghost", "quietghost", "leaver", "racer"].map(n => [n, result(n, "CLIENT_RESULT")]));
  const srvLog = fs.readFileSync(path.join(dir, "server.log"), "utf8");
  const names = server.players.map(p => p.nickname).sort().join(",");
  check(names === "Cutter,Dropper,Hole,Stay", "server keeps exactly the players who came back (ghosts and leaver gone)", names);
  for (const [n, nick, how] of [["cutter", "Cutter", "connection cut"], ["hole", "Hole", "silent link (blackhole)"], ["dropper", "Dropper", "abrupt close"]]) {
    const r = c[n];
    check(r && r.welcomed && r.reconnects >= 1 && r.resumed >= 1, `${nick} resumed its seat after ${how}`, r && `welcomed=${r.welcomed} reconnects=${r.reconnects} resumed=${r.resumed}`);
    check(r && r.distance_moved > 10, `${nick} kept moving after reconnecting`, r && String(r.distance_moved));
    // 끊긴 자리 그대로 돌아옴. (조용한 끊김은 감지까지 4초 동안 클라이언트 혼자 움직였으므로 비교하지 않음 — 서버 위치로 돌아감)
    if (n !== "hole") check(r && r.resume_offset >= 0 && r.resume_offset < 3, `${nick} came back where it was (< 3m)`, r && String(r.resume_offset) + "m");
    check(byNick[nick] && byNick[nick].resumes >= 1 && !byNick[nick].away, `server shows ${nick} resumed and connected`, byNick[nick] && JSON.stringify({ resumes: byNick[nick].resumes, away: byNick[nick].away }));
    check(c.stay && r && c.stay.remote_ids_seen.includes(r.id), `Stay sees ${nick} again under its new connection`, r && `id=${r.id}`);
  }
  check(c.stay && c.stay.reconnects === 0 && c.stay.welcomed, "unaffected player never had to reconnect");
  // (낙하 리스폰 같은 순간이동은 제외: 걷기 봇은 재접속 후 원 궤도가 처음부터 다시 시작돼 섬 밖으로 걸어갈 수 있음)
  for (const n of ["cutter", "dropper"]) check(c[n] && c[n].max_small_correction < 0.5, `${n}: prediction stays consistent after resume (<0.5m)`, c[n] && String(c[n].max_small_correction));
  check((server.stats.resumed || 0) >= 3, "server counted resumes", JSON.stringify(server.stats));
  check((server.stats.away_expired || 0) >= 2, "seats expired for players who never came back", JSON.stringify(server.stats));
  check((server.stats.silent_dropped || 0) >= 1, "server detected a silently dead connection by input silence", JSON.stringify(server.stats));
  check(/\(Ghost\) did not come back/.test(srvLog), "Ghost's seat was held, then released");
  check(/\(QuietGhost\) silent for/.test(srvLog) && /\(QuietGhost\) did not come back/.test(srvLog), "QuietGhost detected as silent, then released");
  check(/\(Leaver\) left/.test(srvLog) && !/\(Leaver\) disconnected — holding seat/.test(srvLog), "explicit leave removes the player at once (no seat held)");
  check(/resumed as \d+ \('Hole'\) after 0ms/.test(srvLog), "new connection took over a seat the server still thought was connected");
  for (const p of server.players) check(p.max_speed <= WALK_SPEED + 0.5, `server-side speed bounded for ${p.nickname}`, String(p.max_speed));
  // 미니게임 도중 끊겼다 돌아옴 (ENet): 순위·진행도 유지
  const race = result("srv_race", "SERVER_RESULT");
  const raceLog = fs.existsSync(path.join(dir, "srv_race.log")) ? fs.readFileSync(path.join(dir, "srv_race.log"), "utf8") : "";
  const rr = /ROUND_RESULTS (\[.*\])/.exec(raceLog);
  const results = rr ? JSON.parse(rr[1]) : [];
  check(race && race.rounds >= 1 && (race.stats.resumed || 0) >= 1, "race server: player dropped mid-round and resumed (ENet)", race && JSON.stringify(race.stats));
  check(results.length === 1 && results[0].nickname === "Racer" && results[0].rank === 1, "race results list the returning player once", JSON.stringify(results));
  check(results.length === 1 && /완주|진행 ([1-9]\d|[2-9])%/.test(results[0].score), "race progress survived the reconnect", results[0] && results[0].score);
  check(c.racer && c.racer.resumed >= 1 && c.racer.my_result && c.racer.my_result.rank === 1, "returning racer received its own result", c.racer && JSON.stringify(c.racer.my_result));
}

console.log(`NET_RESULT scenario=${scenario} passed=${pass} failed=${fail}`);
process.exit(fail ? 1 : 0);
