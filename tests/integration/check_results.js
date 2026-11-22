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

const NO_MAIN_SERVER = ["authflow", "minigames", "touch"].includes(scenario);
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

if (scenario === "basic") {
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
    if (m === "party") check(results.some(r => /코인 [1-9]/.test(r.score)), `[party] coins were collected`, s);
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

console.log(`NET_RESULT scenario=${scenario} passed=${pass} failed=${fail}`);
process.exit(fail ? 1 : 0);
