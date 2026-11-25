class_name Matchmaking
extends RefCounted
## 접속 전에 게이트웨이(server/cloud/gateway.js)에 물어보는 방 조회 · 빠른 매칭.
##   GET <서버>/api/room/K7QP   → 있는 방인지, 몇 명인지, 새로 만들 자리가 있는지
##   GET <서버>/api/quickmatch  → 자리가 남은 공개 광장 경로 ("/" 또는 "/p/2" ...)
## 서버가 잠들어 있거나(무료 호스팅) 응답이 없으면 {"ok": false} → 호출한 쪽은 예전처럼 그냥 접속한다
## (접속 단계가 "서버를 깨우는 중"을 보여 주며 다시 시도함).

const TIMEOUT_SEC := 6.0


## "wss://서버/r/K7QP" → "https://서버",  "ws://127.0.0.1:8080/" → "http://127.0.0.1:8080"
static func http_base(server_url: String) -> String:
	var base := _origin(server_url.strip_edges())
	if base.begins_with("wss://"):
		return "https://" + base.substr(6)
	if base.begins_with("ws://"):
		return "http://" + base.substr(5)
	return ""


## 방 상태. 성공: {"ok": true, "exists", "players", "max_players", "full", "can_create"}
static func check_room(parent: Node, server_url: String, code: String) -> Dictionary:
	return await _get_json(parent, http_base(server_url), "/api/room/" + code)


## 빠른 매칭: 들어갈 접속 주소. 서버가 답하지 않으면 공개 광장 1번 주소
static func quick_match_url(parent: Node, server_url: String) -> String:
	var r := await _get_json(parent, http_base(server_url), "/api/quickmatch")
	return quick_match_target(server_url, r)


## quickmatch 응답 → 접속 주소 (응답이 이상하면 공개 광장 1번)
static func quick_match_target(server_url: String, r: Dictionary) -> String:
	var p := str(r.get("path", "/")) if r.get("ok", false) else "/"
	if p == "/" or not (p.begins_with("/p/") and p.substr(3).is_valid_int()):
		return server_url
	return _origin(server_url) + p


## 방 조회 결과로 입장을 막아야 하면 안내 문구, 아니면 "". 서버가 답하지 않았으면(잠듦 등) 그냥 접속 시도
static func join_problem(r: Dictionary, code: String) -> String:
	if not r.get("ok", false):
		return ""
	if not r.get("exists", true):
		return "%s 방을 찾을 수 없어요. 코드를 확인하거나, 방을 만든 친구가 아직 들어가 있는지 물어봐 주세요" % code
	if r.get("full", false):
		return "%s 방이 꽉 찼어요 (%d명)" % [code, int(r.get("max_players", 0))]
	return ""


## "wss://host:port/path" → "wss://host:port"  (Net.ws_base 와 같음. 자동 로드 없이 테스트하려고 따로 둠)
static func _origin(url: String) -> String:
	var i := url.find("://")
	if i < 0:
		return url
	var slash := url.find("/", i + 3)
	return url if slash < 0 else url.substr(0, slash)


static func _get_json(parent: Node, base: String, path: String) -> Dictionary:
	if base == "" or parent == null or not parent.is_inside_tree():
		return {"ok": false, "error": "no_server"}
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT_SEC
	parent.add_child(req)
	if req.request(base + path) != OK:
		req.queue_free()
		return {"ok": false, "error": "request_failed"}
	var res: Array = await req.request_completed
	req.queue_free()
	var code: int = res[1]
	var parsed: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if res[0] != HTTPRequest.RESULT_SUCCESS or typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "http_%d" % code}
	return parsed
