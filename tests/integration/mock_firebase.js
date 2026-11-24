// Firebase Auth REST API 목(mock) 서버 — 통합 테스트 전용. 실제 Firebase와 같은 경로/응답 형식/RS256 토큰을 흉내낸다.
// 사용: node mock_firebase.js <port> <project_id> <api_key>
//  - POST /identitytoolkit.googleapis.com/v1/accounts:{signUp,signInWithPassword,update,sendOobCode,signInWithIdp}?key=
//  - POST /securetoken.googleapis.com/v1/token?key=   (form: grant_type=refresh_token&refresh_token=)
//  - GET  /jwks   ({keys:[JWK]}, Cache-Control: max-age)
//  - GET  /stats  (테스트 판정용 호출 횟수)
const http = require("http");
const crypto = require("crypto");

const [port = "19099", projectId = "demo-party", apiKey = "test-api-key", saOutPath = ""] = process.argv.slice(2);
const fs = require("fs");

// ---- 테스트용 서비스 계정 (Google이 발급하는 JSON과 같은 형식, PKCS#8 키)
const sa = crypto.generateKeyPairSync("rsa", { modulusLength: 2048 });
const SA_EMAIL = `game-server@${projectId}.iam.gserviceaccount.com`;
const SA_TOKEN_URI = `http://127.0.0.1:${port}/oauth2/token`;
if (saOutPath) {
  fs.writeFileSync(saOutPath, JSON.stringify({
    type: "service_account", project_id: projectId, private_key_id: "sa-kid-1",
    private_key: sa.privateKey.export({ type: "pkcs8", format: "pem" }),
    client_email: SA_EMAIL, client_id: "1", token_uri: SA_TOKEN_URI,
  }, null, 2));
}
const saTokens = new Set();
const docs = new Map();   // "col/id" -> typed fields
const { privateKey, publicKey } = crypto.generateKeyPairSync("rsa", { modulusLength: 2048 });
const KID = "mock-key-1";
const jwk = { ...publicKey.export({ format: "jwk" }), kid: KID, alg: "RS256", use: "sig" };

const users = new Map();     // uid -> {uid, email, password, provider}
const byEmail = new Map();   // email -> uid
const refresh = new Map();   // refresh token -> uid
const stats = {};

const b64u = (b) => Buffer.from(b).toString("base64url");
function idToken(u) {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", kid: KID, typ: "JWT" };
  const payload = {
    iss: `https://securetoken.google.com/${projectId}`, aud: projectId, auth_time: now,
    user_id: u.uid, sub: u.uid, iat: now, exp: now + 3600,
    ...(u.email ? { email: u.email, email_verified: false } : {}),
    firebase: { identities: {}, sign_in_provider: u.provider },
  };
  const input = b64u(JSON.stringify(header)) + "." + b64u(JSON.stringify(payload));
  return input + "." + b64u(crypto.sign("RSA-SHA256", Buffer.from(input), privateKey));
}
function verifyOwn(tok) {
  try {
    const [h, p, s] = tok.split(".");
    if (!crypto.verify("RSA-SHA256", Buffer.from(h + "." + p), publicKey, Buffer.from(s, "base64url"))) return null;
    return JSON.parse(Buffer.from(p, "base64url").toString());
  } catch { return null; }
}
function session(u) {
  const rt = crypto.randomBytes(24).toString("hex");
  refresh.set(rt, u.uid);
  return { kind: "identitytoolkit#Response", localId: u.uid, email: u.email || "", idToken: idToken(u), refreshToken: rt, expiresIn: "3600" };
}
const fail = (res, msg, code = 400) => send(res, code, { error: { code, message: msg, errors: [{ message: msg, domain: "global", reason: "invalid" }] } });
function send(res, code, obj, headers = {}) {
  res.writeHead(code, { "Content-Type": "application/json", ...headers });
  res.end(JSON.stringify(obj));
}
function newUser(fields) {
  const u = { uid: crypto.randomBytes(14).toString("base64url"), ...fields };
  users.set(u.uid, u);
  if (u.email) byEmail.set(u.email, u.uid);
  return u;
}

// ---- 서비스 계정 JWT Bearer → 액세스 토큰 (RFC 7523)
function oauthToken(res, body) {
  const f = new URLSearchParams(body);
  if (f.get("grant_type") !== "urn:ietf:params:oauth:grant-type:jwt-bearer") return send(res, 400, { error: "unsupported_grant_type" });
  try {
    const [h, p, s] = (f.get("assertion") || "").split(".");
    if (!crypto.verify("RSA-SHA256", Buffer.from(h + "." + p), sa.publicKey, Buffer.from(s, "base64url"))) throw 0;
    const c = JSON.parse(Buffer.from(p, "base64url").toString());
    const now = Date.now() / 1000;
    if (c.iss !== SA_EMAIL || c.aud !== SA_TOKEN_URI || !String(c.scope).includes("datastore") || c.exp < now) throw 0;
  } catch { return send(res, 400, { error: "invalid_grant", error_description: "Invalid JWT Signature." }); }
  const t = "sa-" + crypto.randomBytes(16).toString("hex");
  saTokens.add(t);
  return send(res, 200, { access_token: t, expires_in: 3599, token_type: "Bearer" });
}

// ---- Firestore REST (GET / PATCH updateMask / documents:commit) + 보안 규칙 흉내
const NICK_RE = /^[0-9A-Za-z_가-힣]{2,16}$/;
function validProfile(f) {
  const keys = Object.keys(f || {});
  const a = f && f.appearance && f.appearance.mapValue && f.appearance.mapValue.fields;
  const int = (v, max) => v && v.integerValue !== undefined && Number(v.integerValue) >= 0 && Number(v.integerValue) < max;
  return keys.length === 2 && keys.includes("nickname") && keys.includes("appearance")
    && f.nickname.stringValue !== undefined && NICK_RE.test(f.nickname.stringValue)
    && a && Object.keys(a).length === 2 && int(a.color, 12) && int(a.hat, 8);
}
function allowed(caller, op, col, id, newFields) {
  if (caller.admin) return true;                       // 서비스 계정은 규칙 우회
  if (!caller.uid) return false;
  if (col === "profiles") return op === "read" ? true : (caller.uid === id && validProfile(newFields));
  if (col === "stats") return op === "read" && caller.uid === id;
  return false;
}
function firestore(req, res, url, body) {
  const auth = (req.headers["authorization"] || "").replace(/^Bearer /, "");
  const claims = saTokens.has(auth) ? null : verifyOwn(auth);
  const caller = saTokens.has(auth) ? { admin: true } : claims ? { uid: claims.sub } : {};
  if (!caller.admin && !caller.uid) return send(res, 401, { error: { code: 401, status: "UNAUTHENTICATED", message: "unauthenticated" } });
  const denied = () => send(res, 403, { error: { code: 403, status: "PERMISSION_DENIED", message: "Missing or insufficient permissions." } });
  const prefix = `/firestore/v1/projects/${projectId}/databases/(default)/documents`;
  const p = decodeURIComponent(url.pathname);
  let j = {};
  try { j = JSON.parse(body || "{}"); } catch { return send(res, 400, { error: { status: "INVALID_ARGUMENT" } }); }

  if (req.method === "POST" && p === prefix + ":commit") {
    for (const w of j.writes || []) {
      const key = w.update.name.split("/documents/")[1];
      const [col, id] = key.split("/");
      if (!allowed(caller, "write", col, id, w.update.fields)) return denied();
      const cur = { ...(docs.get(key) || {}) };
      for (const t of w.updateTransforms || []) {
        if (t.increment) cur[t.fieldPath] = { integerValue: String(Number((cur[t.fieldPath] || {}).integerValue || 0) + Number(t.increment.integerValue)) };
        if (t.setToServerValue === "REQUEST_TIME") cur[t.fieldPath] = { timestampValue: new Date().toISOString() };
      }
      docs.set(key, cur);
    }
    return send(res, 200, { writeResults: [{}], commitTime: new Date().toISOString() });
  }
  if (!p.startsWith(prefix + "/")) return send(res, 404, { error: { status: "NOT_FOUND" } });
  const key = p.slice(prefix.length + 1);
  const [col, id] = key.split("/");
  if (req.method === "GET") {
    if (!allowed(caller, "read", col, id)) return denied();
    if (!docs.has(key)) return send(res, 404, { error: { code: 404, status: "NOT_FOUND", message: "Document not found" } });
    return send(res, 200, { name: `projects/${projectId}/databases/(default)/documents/${key}`, fields: docs.get(key) });
  }
  if (req.method === "PATCH") {
    const mask = url.searchParams.getAll("updateMask.fieldPaths");
    const merged = { ...(docs.get(key) || {}) };
    for (const m of mask) { if (j.fields && j.fields[m] !== undefined) merged[m] = j.fields[m]; else delete merged[m]; }
    if (!allowed(caller, "write", col, id, merged)) return denied();
    docs.set(key, merged);
    return send(res, 200, { name: `projects/${projectId}/databases/(default)/documents/${key}`, fields: merged });
  }
  return send(res, 405, { error: { status: "METHOD_NOT_ALLOWED" } });
}

http.createServer((req, res) => {
  let body = "";
  req.on("data", (c) => (body += c));
  req.on("end", () => {
    const url = new URL(req.url, "http://x");
    const route = url.pathname;
    stats[route] = (stats[route] || 0) + 1;
    if (route === "/jwks") return send(res, 200, { keys: [jwk] }, { "Cache-Control": "public, max-age=21600" });
    if (route === "/stats") return send(res, 200, stats);
    if (route === "/debug/docs") return send(res, 200, Object.fromEntries(docs));
    if (route === "/oauth2/token") return oauthToken(res, body);
    if (route.startsWith("/firestore/v1/")) return firestore(req, res, url, body);
    if (url.searchParams.get("key") !== apiKey) return fail(res, "API key not valid. Please pass a valid API key.");

    if (route === "/securetoken.googleapis.com/v1/token") {
      const f = new URLSearchParams(body);
      const uid = refresh.get(f.get("refresh_token"));
      if (f.get("grant_type") !== "refresh_token" || !uid) return send(res, 400, { error: { code: 400, message: "INVALID_REFRESH_TOKEN" } });
      const u = users.get(uid);
      const rt = crypto.randomBytes(24).toString("hex");
      refresh.set(rt, uid);
      return send(res, 200, { access_token: idToken(u), expires_in: "3600", token_type: "Bearer", refresh_token: rt, id_token: idToken(u), user_id: uid, project_id: "0" });
    }

    let j = {};
    try { j = JSON.parse(body || "{}"); } catch { return fail(res, "INVALID_JSON"); }
    const op = route.replace("/identitytoolkit.googleapis.com/v1/", "");
    switch (op) {
      case "accounts:signUp": {
        if (!j.email) return send(res, 200, session(newUser({ provider: "anonymous" })));
        if (byEmail.has(j.email)) return fail(res, "EMAIL_EXISTS");
        if (!j.password || j.password.length < 6) return fail(res, "WEAK_PASSWORD : Password should be at least 6 characters");
        return send(res, 200, session(newUser({ email: j.email, password: j.password, provider: "password" })));
      }
      case "accounts:signInWithPassword": {
        const u = users.get(byEmail.get(j.email));
        if (!u || u.password !== j.password) return fail(res, "INVALID_LOGIN_CREDENTIALS");
        return send(res, 200, session(u));
      }
      case "accounts:update": {   // 게스트 → 이메일 연결
        const claims = verifyOwn(j.idToken || "");
        if (!claims) return fail(res, "INVALID_ID_TOKEN");
        const u = users.get(claims.sub);
        if (j.email && byEmail.has(j.email)) return fail(res, "EMAIL_EXISTS");
        if (j.password && j.password.length < 6) return fail(res, "WEAK_PASSWORD : Password should be at least 6 characters");
        Object.assign(u, { email: j.email, password: j.password, provider: "password" });
        byEmail.set(j.email, u.uid);
        return send(res, 200, session(u));
      }
      case "accounts:sendOobCode":
        if (!byEmail.has(j.email)) return fail(res, "EMAIL_NOT_FOUND");
        return send(res, 200, { kind: "identitytoolkit#GetOobConfirmationCodeResponse", email: j.email });
      case "accounts:signInWithIdp": {   // id_token=google-test-<sub> 형식만 허용
        const m = /id_token=google-test-([A-Za-z0-9]+)/.exec(j.postBody || "");
        if (!m) return fail(res, "INVALID_IDP_RESPONSE");
        const email = `${m[1]}@gmail.test`;
        let u = users.get(byEmail.get(email));
        if (!u) {
          const claims = j.idToken ? verifyOwn(j.idToken) : null;    // 게스트 연결
          u = claims ? users.get(claims.sub) : newUser({});
          Object.assign(u, { email, provider: "google.com" });
          byEmail.set(email, u.uid);
        }
        return send(res, 200, session(u));
      }
      default:
        return fail(res, "NOT_FOUND", 404);
    }
  });
}).listen(Number(port), "127.0.0.1", () => console.log(`MOCK_FIREBASE_READY port=${port} project=${projectId}`));
