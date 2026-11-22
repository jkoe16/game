class_name FirebaseTokenVerifier
extends Node
## 게임 서버용 Firebase ID 토큰 검증기 (Firebase 공식 검증 규칙 구현).
##  - 헤더: alg == RS256, kid 가 Google 공개키 목록에 존재
##  - 서명: 해당 공개키로 RS256 검증
##  - 클레임: aud == 프로젝트 ID, iss == https://securetoken.google.com/<프로젝트 ID>,
##            exp > 현재, iat <= 현재, auth_time <= 현재, sub(=uid) 비어있지 않고 128자 이하
## 공개키는 Cache-Control max-age 동안 캐시하고, 모르는 kid가 오면 (최소 간격을 두고) 다시 받는다.

const CLOCK_SKEW_SEC := 60
const MIN_REFETCH_INTERVAL_MS := 30000

var project_id := ""
var jwks_url := ""
var keys := {}                 # kid -> CryptoKey
var keys_expire_unix := 0
var _last_fetch_ms := -MIN_REFETCH_INTERVAL_MS
var _fetching := false
var _crypto := Crypto.new()

signal keys_updated(ok: bool)


func setup(config: FirebaseConfig) -> void:
	project_id = config.project_id
	jwks_url = config.jwks_url


## 테스트용: 공개키를 직접 주입 (네트워크 없이)
func set_static_keys(k: Dictionary) -> void:
	keys = k
	keys_expire_unix = int(Time.get_unix_time_from_system()) + 1000000


func fetch_keys() -> bool:
	if _fetching:
		var ok: bool = await keys_updated
		return ok
	_fetching = true
	_last_fetch_ms = Time.get_ticks_msec()
	var r := await HttpUtil.request(self, jwks_url)
	var ok := false
	if r["ok"] and typeof(r["json"]) == TYPE_DICTIONARY and r["json"].has("keys"):
		var fresh := {}
		for jwk in r["json"]["keys"]:
			if typeof(jwk) != TYPE_DICTIONARY or jwk.get("kty") != "RSA":
				continue
			var key := CryptoKey.new()
			if key.load_from_string(Jwt.rsa_pem_from_jwk(str(jwk["n"]), str(jwk["e"])), true) == OK:
				fresh[str(jwk["kid"])] = key
		if not fresh.is_empty():
			keys = fresh
			keys_expire_unix = int(Time.get_unix_time_from_system()) + HttpUtil.max_age(r["headers"])
			ok = true
	if not ok:
		push_warning("[AUTH] failed to fetch Firebase public keys (HTTP %d)" % r["code"])
	_fetching = false
	keys_updated.emit(ok)
	return ok


## 반환: {ok:true, uid, provider, email, email_verified} 또는 {ok:false, reason}
func verify(token: Variant) -> Dictionary:
	if typeof(token) != TYPE_STRING or (token as String).length() > 4096:
		return _fail("token_type")
	var jwt := Jwt.split(token)
	if jwt.is_empty():
		return _fail("token_format")
	var header: Dictionary = jwt["header"]
	var p: Dictionary = jwt["payload"]
	if header.get("alg") != "RS256":
		return _fail("alg")
	var kid := str(header.get("kid", ""))

	var now := int(Time.get_unix_time_from_system())
	if not keys.has(kid) or now >= keys_expire_unix:
		if jwks_url != "" and (now >= keys_expire_unix or Time.get_ticks_msec() - _last_fetch_ms > MIN_REFETCH_INTERVAL_MS):
			await fetch_keys()
	if not keys.has(kid):
		return _fail("unknown_kid")

	var digest := Jwt.sha256(jwt["signing_input"])
	if not _crypto.verify(HashingContext.HASH_SHA256, digest, jwt["signature"], keys[kid]):
		return _fail("signature")

	if p.get("aud") != project_id:
		return _fail("aud")
	if p.get("iss") != "https://securetoken.google.com/" + project_id:
		return _fail("iss")
	if not (_num(p, "exp") > now - CLOCK_SKEW_SEC):
		return _fail("expired")
	if _num(p, "iat") > now + CLOCK_SKEW_SEC or _num(p, "auth_time") > now + CLOCK_SKEW_SEC:
		return _fail("issued_in_future")
	var uid := str(p.get("sub", ""))
	if uid == "" or uid.length() > 128:
		return _fail("sub")

	var fb: Dictionary = p.get("firebase", {}) if typeof(p.get("firebase")) == TYPE_DICTIONARY else {}
	return {
		"ok": true,
		"uid": uid,
		"provider": str(fb.get("sign_in_provider", "unknown")),
		"email": str(p.get("email", "")),
		"email_verified": p.get("email_verified", false) == true,
	}


func _num(p: Dictionary, k: String) -> int:
	var v: Variant = p.get(k)
	return int(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else -1


func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
