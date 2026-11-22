class_name GoogleDesktopOAuth
extends Node
## PC용 Google OAuth 2.0 (설치형 앱 방식: 루프백 리디렉션 + PKCE, RFC 8252).
## 1) 127.0.0.1 임의 포트에서 대기 → 2) 시스템 브라우저로 Google 로그인 페이지 열기
## 3) 브라우저가 http://127.0.0.1:<port>/?code=... 로 돌아오면 코드 수신 → 4) 코드를 ID 토큰으로 교환

const PORT_FIRST := 53682
const PORT_LAST := 53702
const TIMEOUT_SEC := 180.0
const SUCCESS_HTML := "<html><head><meta charset='utf-8'></head><body style='font-family:sans-serif;text-align:center;padding-top:80px'><h2>로그인 완료!</h2><p>이 창을 닫고 3D PARTY WORLD로 돌아가세요.</p></body></html>"
const FAIL_HTML := "<html><head><meta charset='utf-8'></head><body style='font-family:sans-serif;text-align:center;padding-top:80px'><h2>로그인 실패</h2><p>게임으로 돌아가 다시 시도해 주세요.</p></body></html>"

var _server := TCPServer.new()


## 반환: {ok, id_token, error}
func authorize(cfg: FirebaseConfig) -> Dictionary:
	var port := 0
	for p in range(PORT_FIRST, PORT_LAST + 1):
		if _server.listen(p, "127.0.0.1") == OK:
			port = p
			break
	if port == 0:
		return _fail("로그인용 로컬 포트를 열 수 없습니다.")
	var redirect := "http://127.0.0.1:%d" % port
	var verifier := random_string(64)
	var state := random_string(24)
	var url := cfg.google_auth_url + "?" + _query({
		"client_id": cfg.google_client_id,
		"redirect_uri": redirect,
		"response_type": "code",
		"scope": "openid email profile",
		"code_challenge": pkce_challenge(verifier),
		"code_challenge_method": "S256",
		"state": state,
		"prompt": "select_account",
	})
	OS.shell_open(url)

	var cb := await _wait_for_callback()
	_server.stop()
	if not cb.get("ok", false):
		return _fail(cb.get("error", "로그인이 취소되었거나 시간이 초과되었습니다."))
	if cb.get("state") != state:
		return _fail("로그인 응답 검증(state)에 실패했습니다.")

	var form := {
		"code": cb["code"],
		"client_id": cfg.google_client_id,
		"redirect_uri": redirect,
		"grant_type": "authorization_code",
		"code_verifier": verifier,
	}
	if cfg.google_client_secret != "":
		form["client_secret"] = cfg.google_client_secret
	var r := await HttpUtil.post_form(self, cfg.google_token_url, form)
	if not r["ok"] or typeof(r["json"]) != TYPE_DICTIONARY or not r["json"].has("id_token"):
		return _fail("Google 토큰 교환 실패 (HTTP %d)" % r["code"])
	return {"ok": true, "id_token": str(r["json"]["id_token"]), "error": ""}


func _wait_for_callback() -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(TIMEOUT_SEC * 1000)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not _server.is_connection_available():
			continue
		var conn := _server.take_connection()
		var line := await _read_request_line(conn)
		var parsed := parse_callback(line)
		if parsed.get("ignore", false):
			conn.disconnect_from_host()  # favicon 등 무관한 요청
			continue
		var html := SUCCESS_HTML if parsed.get("ok", false) else FAIL_HTML
		var body := html.to_utf8_buffer()
		var head := "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % body.size()
		conn.put_data(head.to_utf8_buffer() + body)
		conn.disconnect_from_host()
		return parsed
	return {"ok": false, "error": "로그인 시간이 초과되었습니다."}


func _read_request_line(conn: StreamPeerTCP) -> String:
	var buf := PackedByteArray()
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		conn.poll()
		var n := conn.get_available_bytes()
		if n > 0:
			var res := conn.get_data(n)
			buf.append_array(res[1])
			var text := buf.get_string_from_utf8()
			var eol := text.find("\r\n")
			if eol >= 0:
				return text.substr(0, eol)
		await get_tree().process_frame
	return ""


## "GET /?code=..&state=.. HTTP/1.1" 해석. 반환 {ok, code, state} / {ok:false, error} / {ignore:true}
static func parse_callback(request_line: String) -> Dictionary:
	var parts := request_line.split(" ")
	if parts.size() < 2 or parts[0] != "GET":
		return {"ok": false, "error": "잘못된 요청"}
	var target := parts[1]
	var q := target.find("?")
	if q < 0:
		return {"ignore": true}
	var params := {}
	for kv in target.substr(q + 1).split("&"):
		var pair := kv.split("=", true, 1)
		params[pair[0].uri_decode()] = pair[1].uri_decode() if pair.size() > 1 else ""
	if params.has("error"):
		return {"ok": false, "error": "Google 로그인이 거부되었습니다 (%s)" % params["error"], "state": params.get("state", "")}
	if not params.has("code"):
		return {"ignore": true}
	return {"ok": true, "code": params["code"], "state": params.get("state", "")}


static func pkce_challenge(verifier: String) -> String:
	return Jwt.b64url_encode(Jwt.sha256(verifier.to_utf8_buffer()))


static func random_string(length: int) -> String:
	const CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
	var bytes := Crypto.new().generate_random_bytes(length)
	var s := ""
	for b in bytes:
		s += CHARS[b % CHARS.length()]
	return s


static func _query(d: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in d:
		parts.append("%s=%s" % [str(k).uri_encode(), str(d[k]).uri_encode()])
	return "&".join(parts)


func _fail(msg: String) -> Dictionary:
	return {"ok": false, "id_token": "", "error": msg}


func _exit_tree() -> void:
	_server.stop()
