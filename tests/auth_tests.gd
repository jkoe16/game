class_name AuthTests
extends RefCounted
## 인증 관련 단위 테스트 (네트워크 불필요: 로컬에서 RSA 키를 만들어 토큰을 서명/검증).

const PROJECT := "demo-party"

static var t: Object  # 테스트 러너 (check() 제공)


static func run(runner: Object) -> void:
	t = runner
	test_b64url()
	test_pem_from_jwk()
	await test_verifier()
	test_pkce_and_callback()
	test_error_mapping()
	test_firestore_codec()
	test_progression()


static func test_b64url() -> void:
	var raw := PackedByteArray([0xfb, 0xff, 0x00, 0x10, 0x7e])
	var enc := Jwt.b64url_encode(raw)
	t.check(not enc.contains("+") and not enc.contains("/") and not enc.contains("="), "b64url has no +/=")
	t.check(Jwt.b64url_decode(enc) == raw, "b64url roundtrip")


## Godot가 만든 공개키 PEM에서 n,e를 꺼내 JWK→PEM 변환기로 다시 만들었을 때 완전히 같은지
static func test_pem_from_jwk() -> void:
	var key := Crypto.new().generate_rsa(2048)
	var pem := key.save_to_string(true)
	var ne := _spki_to_ne(_pem_to_der(pem))
	t.check(not ne.is_empty(), "parse generated SPKI")
	if ne.is_empty():
		return
	var rebuilt := Jwt.rsa_pem_from_jwk(Jwt.b64url_encode(ne["n"]), Jwt.b64url_encode(ne["e"]))
	t.check(_pem_to_der(rebuilt) == _pem_to_der(pem), "JWK→PEM produces identical public key DER")
	var k2 := CryptoKey.new()
	t.check(k2.load_from_string(rebuilt, true) == OK, "rebuilt PEM loads as CryptoKey")


static func test_verifier() -> void:
	var crypto := Crypto.new()
	var priv := crypto.generate_rsa(2048)
	var pub := CryptoKey.new()
	pub.load_from_string(priv.save_to_string(true), true)
	var other_priv := crypto.generate_rsa(2048)

	var v := FirebaseTokenVerifier.new()
	v.project_id = PROJECT
	v.jwks_url = ""
	v.set_static_keys({"k1": pub})
	t.root.add_child(v)

	var now := int(Time.get_unix_time_from_system())
	var good := _claims(now)
	var r: Dictionary = await v.verify(_sign(good, priv, "k1"))
	t.check(r.get("ok") == true and r.get("uid") == "user123" and r.get("provider") == "password", "valid Firebase token accepted", str(r))

	var anon := _claims(now)
	anon["firebase"] = {"sign_in_provider": "anonymous"}
	r = await v.verify(_sign(anon, priv, "k1"))
	t.check(r.get("provider") == "anonymous", "provider read from token")

	var tok := _sign(good, priv, "k1")
	var parts := tok.split(".")
	var evil := good.duplicate()
	evil["sub"] = "attacker"
	var tampered := parts[0] + "." + Jwt.b64url_encode(JSON.stringify(evil).to_utf8_buffer()) + "." + parts[2]
	t.check((await v.verify(tampered)).get("reason") == "signature", "tampered payload rejected (signature)")
	t.check((await v.verify(_sign(good, other_priv, "k1"))).get("reason") == "signature", "token signed by other key rejected")
	t.check((await v.verify(_sign(good, priv, "nope"))).get("reason") == "unknown_kid", "unknown kid rejected")

	var c := _claims(now)
	c["aud"] = "other-project"
	t.check((await v.verify(_sign(c, priv, "k1"))).get("reason") == "aud", "wrong audience rejected")
	c = _claims(now)
	c["iss"] = "https://evil.example.com/" + PROJECT
	t.check((await v.verify(_sign(c, priv, "k1"))).get("reason") == "iss", "wrong issuer rejected")
	c = _claims(now)
	c["exp"] = now - 3600
	t.check((await v.verify(_sign(c, priv, "k1"))).get("reason") == "expired", "expired token rejected")
	c = _claims(now)
	c["iat"] = now + 3600
	t.check((await v.verify(_sign(c, priv, "k1"))).get("reason") == "issued_in_future", "future iat rejected")
	c = _claims(now)
	c["sub"] = ""
	t.check((await v.verify(_sign(c, priv, "k1"))).get("reason") == "sub", "empty uid rejected")

	var none_tok := Jwt.b64url_encode(JSON.stringify({"alg": "none", "kid": "k1"}).to_utf8_buffer()) + "." + Jwt.b64url_encode(JSON.stringify(good).to_utf8_buffer()) + "."
	t.check((await v.verify(none_tok)).get("reason") == "alg", "alg=none rejected")
	t.check((await v.verify("not.a.jwt.at.all")).get("ok") == false, "malformed token rejected")
	t.check((await v.verify(12345)).get("reason") == "token_type", "non-string token rejected")
	v.queue_free()


static func test_pkce_and_callback() -> void:
	# RFC 7636 부록 B 테스트 벡터
	t.check(GoogleDesktopOAuth.pkce_challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "PKCE S256 matches RFC 7636 vector")
	var s := GoogleDesktopOAuth.random_string(64)
	t.check(s.length() == 64, "PKCE verifier length 64")
	var p := GoogleDesktopOAuth.parse_callback("GET /?state=abc&code=4%2F0Ab_xyz&scope=email HTTP/1.1")
	t.check(p.get("ok") == true and p.get("code") == "4/0Ab_xyz" and p.get("state") == "abc", "OAuth callback parsed + url-decoded")
	t.check(GoogleDesktopOAuth.parse_callback("GET /?error=access_denied&state=abc HTTP/1.1").get("ok") == false, "OAuth denial detected")
	t.check(GoogleDesktopOAuth.parse_callback("GET /favicon.ico HTTP/1.1").get("ignore") == true, "unrelated request ignored")
	t.check(GoogleDesktopOAuth.parse_callback("POST / HTTP/1.1").get("ok") == false, "non-GET rejected")


static func test_error_mapping() -> void:
	var a: Node = load("res://scripts/auth/firebase_auth.gd").new()
	var r: Dictionary = a._from_response({"code": 400, "json": {"error": {"code": 400, "message": "WEAK_PASSWORD : Password should be at least 6 characters"}}})
	t.check(r["code"] == "WEAK_PASSWORD" and r["error"].contains("6자"), "Firebase error 'WEAK_PASSWORD : ...' mapped to Korean")
	r = a._from_response({"code": 400, "json": {"error": {"message": "API key not valid. Please pass a valid API key."}}})
	t.check(r["code"] == "API_KEY_INVALID", "invalid API key detected")
	r = a._from_response({"code": 0, "json": null})
	t.check(r["code"] == "NETWORK", "network failure mapped")
	t.check(a._looks_like_email("kid@example.com") and not a._looks_like_email("kid@") and not a._looks_like_email("@x.com"), "email shape check")
	t.check(a._validate_email_pw("a@b.co", "12345").get("code") == "WEAK_PASSWORD", "short password rejected client-side")
	a.free()


# ------------------------------------------------------------------ 헬퍼

static func _claims(now: int) -> Dictionary:
	return {
		"iss": "https://securetoken.google.com/" + PROJECT,
		"aud": PROJECT,
		"auth_time": now - 10,
		"user_id": "user123",
		"sub": "user123",
		"iat": now - 10,
		"exp": now + 3600,
		"email": "kid@example.com",
		"firebase": {"sign_in_provider": "password"},
	}


static func _sign(claims: Dictionary, key: CryptoKey, kid: String) -> String:
	var h := Jwt.b64url_encode(JSON.stringify({"alg": "RS256", "kid": kid, "typ": "JWT"}).to_utf8_buffer())
	var p := Jwt.b64url_encode(JSON.stringify(claims).to_utf8_buffer())
	var sig := Crypto.new().sign(HashingContext.HASH_SHA256, Jwt.sha256((h + "." + p).to_utf8_buffer()), key)
	return h + "." + p + "." + Jwt.b64url_encode(sig)


static func _pem_to_der(pem: String) -> PackedByteArray:
	var body := ""
	for line in pem.split("\n"):
		var l := line.strip_edges()
		if l != "" and not l.begins_with("-----"):
			body += l
	return Marshalls.base64_to_raw(body)


## 최소 DER 파서: SPKI → {n, e}
static func _spki_to_ne(der: PackedByteArray) -> Dictionary:
	var pos := [0]
	if _tag(der, pos) != 0x30: return {}
	_len(der, pos)
	if _tag(der, pos) != 0x30: return {}
	pos[0] += _len(der, pos)            # AlgorithmIdentifier 건너뛰기
	if _tag(der, pos) != 0x03: return {}
	_len(der, pos)
	pos[0] += 1                          # unused bits
	if _tag(der, pos) != 0x30: return {}
	_len(der, pos)
	if _tag(der, pos) != 0x02: return {}
	var nl := _len(der, pos)
	var n := der.slice(pos[0], pos[0] + nl)
	pos[0] += nl
	if _tag(der, pos) != 0x02: return {}
	var el := _len(der, pos)
	var e := der.slice(pos[0], pos[0] + el)
	return {"n": n, "e": e}


static func _tag(der: PackedByteArray, pos: Array) -> int:
	var v := der[pos[0]]
	pos[0] += 1
	return v


static func _len(der: PackedByteArray, pos: Array) -> int:
	var b := der[pos[0]]
	pos[0] += 1
	if b < 0x80:
		return b
	var n := 0
	for i in (b & 0x7F):
		n = (n << 8) | der[pos[0]]
		pos[0] += 1
	return n


static func test_firestore_codec() -> void:
	var src := {"nickname": "파티왕", "appearance": {"color": 3, "hat": 2}, "xp": 9007199254740, "ratio": 0.5, "ok": true, "tags": ["a", 1], "none": null}
	var enc := FirestoreClient.encode_fields(src)
	t.check(enc["xp"] == {"integerValue": "9007199254740"}, "int64 encoded as string (Firestore format)")
	t.check(enc["appearance"].has("mapValue") and enc["tags"].has("arrayValue"), "map/array encoded")
	t.check(FirestoreClient.decode_fields(enc) == src, "Firestore codec roundtrip preserves types", str(FirestoreClient.decode_fields(enc)))
	t.check(FirestoreClient.decode_value({"timestampValue": "2026-11-22T07:00:00Z"}) == "2026-11-22T07:00:00Z", "timestamp decoded as string")


static func test_progression() -> void:
	t.check(Progression.level_for_xp(0) == 1 and Progression.level_for_xp(39) == 1 and Progression.level_for_xp(40) == 2, "level thresholds (Lv2 at 40xp)")
	t.check(Progression.level_for_xp(3240) == 10, "Lv10 at 3240xp")
	t.check(absf(Progression.progress(100) - 0.5) < 0.01, "progress within level", str(Progression.progress(100)))
