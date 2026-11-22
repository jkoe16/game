class_name Jwt
extends RefCounted
## JWT / JWK 유틸리티 (외부 라이브러리 없이 Godot Crypto 사용).


static func b64url_decode(s: String) -> PackedByteArray:
	var t := s.replace("-", "+").replace("_", "/")
	while t.length() % 4 != 0:
		t += "="
	return Marshalls.base64_to_raw(t)


static func b64url_encode(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")


## "header.payload.signature" → {header, payload, signing_input, signature} / 실패 시 {}
static func split(token: String) -> Dictionary:
	var parts := token.split(".")
	if parts.size() != 3:
		return {}
	var header: Variant = JSON.parse_string(b64url_decode(parts[0]).get_string_from_utf8())
	var payload: Variant = JSON.parse_string(b64url_decode(parts[1]).get_string_from_utf8())
	if typeof(header) != TYPE_DICTIONARY or typeof(payload) != TYPE_DICTIONARY:
		return {}
	return {
		"header": header,
		"payload": payload,
		"signing_input": (parts[0] + "." + parts[1]).to_utf8_buffer(),
		"signature": b64url_decode(parts[2]),
	}


## 서명 검증 없이 payload만 읽기 (클라이언트에서 uid/만료 표시용. 서버 판단에 사용 금지)
static func unsafe_payload(token: String) -> Dictionary:
	var d := split(token)
	return d.get("payload", {})


static func sha256(bytes: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish()


# ------------------------------------------------------------------ JWK(RSA) → PEM 공개키

## JWK의 n, e (base64url)로 X.509 SubjectPublicKeyInfo PEM을 만든다.
static func rsa_pem_from_jwk(n_b64: String, e_b64: String) -> String:
	var rsa_key := _der_seq(_der_uint(b64url_decode(n_b64)) + _der_uint(b64url_decode(e_b64)))
	var alg_id := PackedByteArray([0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00])
	var bit_string := PackedByteArray([0x03]) + _der_len(rsa_key.size() + 1) + PackedByteArray([0x00]) + rsa_key
	var spki := _der_seq(alg_id + bit_string)
	var b64 := Marshalls.raw_to_base64(spki)
	var pem := "-----BEGIN PUBLIC KEY-----\n"
	for i in range(0, b64.length(), 64):
		pem += b64.substr(i, 64) + "\n"
	return pem + "-----END PUBLIC KEY-----\n"


static func _der_len(n: int) -> PackedByteArray:
	if n < 0x80:
		return PackedByteArray([n])
	if n < 0x100:
		return PackedByteArray([0x81, n])
	return PackedByteArray([0x82, (n >> 8) & 0xFF, n & 0xFF])


static func _der_seq(content: PackedByteArray) -> PackedByteArray:
	return PackedByteArray([0x30]) + _der_len(content.size()) + content


static func _der_uint(raw: PackedByteArray) -> PackedByteArray:
	var v := raw.duplicate()
	while v.size() > 1 and v[0] == 0:
		v.remove_at(0)
	if v[0] & 0x80:
		v.insert(0, 0)
	return PackedByteArray([0x02]) + _der_len(v.size()) + v
