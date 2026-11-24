class_name OnlineConfig
extends RefCounted
## 공개 온라인 서버 주소 로더.  res://config/online.cfg
##   [online]
##   server_url="wss://my-game-server.fly.dev"
## 비어 있으면 메뉴에 "친구들과 온라인 플레이" 버튼이 나오지 않는다.
## 실행 인자 --server-url=<주소> 로 덮어쓸 수 있다.

const PATH := "res://config/online.cfg"


static func server_url() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--server-url="):
			return a.substr("--server-url=".length()).strip_edges()
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return ""
	return str(cf.get_value("online", "server_url", "")).strip_edges()


# ------------------------------------------------------------ 방 코드
## 헷갈리는 글자(0/O, 1/I/L)는 뺀 문자들
const ROOM_CHARS := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const ROOM_CODE_LEN := 4


static func new_room_code() -> String:
	var s := ""
	for i in ROOM_CODE_LEN:
		s += ROOM_CHARS[randi() % ROOM_CHARS.length()]
	return s


## 입력값 정리: 대문자, 공백·기호 제거. 4~8자 영문/숫자가 아니면 ""
static func normalize_room_code(text: String) -> String:
	var out := ""
	for ch in text.strip_edges().to_upper():
		if (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out if out.length() >= 4 and out.length() <= 8 else ""


## "wss://서버" + "K7QP" → "wss://서버/r/K7QP"
static func room_url(server: String, code: String) -> String:
	return server.trim_suffix("/") + "/r/" + code


## "wss://서버/r/K7QP/racing" → "K7QP" (방이 아니면 "")
static func room_from_url(url: String) -> String:
	var i := url.find("/r/")
	if i < 0 or not (url.begins_with("ws://") or url.begins_with("wss://")):
		return ""
	return url.substr(i + 3).get_slice("/", 0)


## 초대 링크: 웹이면 지금 페이지 주소, 아니면 config/online.cfg 의 web_url (기본 game-28f1b.web.app)
static func invite_link(code: String) -> String:
	var base := ""
	if OS.has_feature("web"):
		base = str(JavaScriptBridge.eval("location.origin + location.pathname", true))
	if base == "" or base == "null":
		var cf := ConfigFile.new()
		base = "https://game-28f1b.web.app/"
		if cf.load(PATH) == OK:
			base = str(cf.get_value("online", "web_url", base))
	return base + "?room=" + code


## 웹 주소의 ?room=코드 (초대 링크로 들어온 경우). 없으면 ""
static func room_from_page() -> String:
	if not OS.has_feature("web"):
		return ""
	var v: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('room') || ''", true)
	return normalize_room_code(str(v)) if v != null else ""
