extends Node
## Autoload "Auth" — Firebase Authentication 클라이언트 (REST API 사용, PC/Android/iOS 공통).
##
## 지원: 게스트(익명) / 이메일 가입·로그인 / 비밀번호 재설정 메일 / 게스트→이메일 계정 연결 /
##       Google 로그인(PC: 브라우저 OAuth, 모바일: 추후 네이티브 플러그인) / 자동 로그인 / 토큰 자동 갱신
## 모든 공개 메서드는 await 가능하며 {ok:bool, error:String(한국어 메시지), code:String} 을 반환한다.

signal auth_changed

const DEFAULT_SESSION_PATH := "user://auth_session.cfg"
const REFRESH_MARGIN_SEC := 300

var config: FirebaseConfig
## 세션 파일 경로 (테스트는 --session-file= 로 분리)
var SESSION_PATH := DEFAULT_SESSION_PATH
var uid := ""
var id_token := ""
var refresh_token := ""
var expires_at := 0
var email := ""
var provider := ""          # anonymous | password | google.com
## false면 세션을 디스크에 저장하지 않음 (테스트 봇 등)
var persist_session := true

var _refreshing := false
signal _refresh_done(ok: bool)


func _ready() -> void:
	config = FirebaseConfig.load_default()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--session-file="):
			SESSION_PATH = a.substr("--session-file=".length())


func is_configured() -> bool:
	return config != null and config.is_client_ready()


func is_signed_in() -> bool:
	return uid != "" and refresh_token != ""


func is_anonymous() -> bool:
	return provider == "anonymous"


func display_account() -> String:
	if not is_signed_in():
		return "로그인 안 됨"
	match provider:
		"anonymous":
			return "게스트 (%s…)" % uid.substr(0, 6)
		"google.com":
			return "Google: %s" % email
		_:
			return email if email != "" else uid


# ------------------------------------------------------------------ 로그인 방법

func sign_in_anonymous() -> Dictionary:
	return await _auth_call("accounts:signUp", {"returnSecureToken": true})


func sign_up_email(p_email: String, password: String) -> Dictionary:
	var v := _validate_email_pw(p_email, password)
	if not v.is_empty():
		return v
	return await _auth_call("accounts:signUp", {"email": p_email.strip_edges(), "password": password, "returnSecureToken": true})


func sign_in_email(p_email: String, password: String) -> Dictionary:
	var v := _validate_email_pw(p_email, password)
	if not v.is_empty():
		return v
	return await _auth_call("accounts:signInWithPassword", {"email": p_email.strip_edges(), "password": password, "returnSecureToken": true})


func send_password_reset(p_email: String) -> Dictionary:
	if not _looks_like_email(p_email):
		return _err("INVALID_EMAIL")
	var r := await _post(config.auth_base_url + "/accounts:sendOobCode?key=" + config.api_key,
		{"requestType": "PASSWORD_RESET", "email": p_email.strip_edges()})
	return {"ok": true, "error": "", "code": ""} if r["ok"] else _from_response(r)


## 게스트 계정에 이메일/비밀번호를 연결 (같은 uid 유지 → 진행도 보존)
func link_email(p_email: String, password: String) -> Dictionary:
	if not is_signed_in() or not is_anonymous():
		return _err("NOT_ANONYMOUS")
	var v := _validate_email_pw(p_email, password)
	if not v.is_empty():
		return v
	var tok := await get_valid_id_token()
	if tok == "":
		return _err("TOKEN_EXPIRED")
	return await _auth_call("accounts:update", {"idToken": tok, "email": p_email.strip_edges(), "password": password, "returnSecureToken": true})


## Google 로그인. PC는 시스템 브라우저로 OAuth 진행. 게스트 상태면 게스트 계정에 연결한다.
func sign_in_google() -> Dictionary:
	if OS.has_feature("mobile"):
		return {"ok": false, "error": "모바일 Google 로그인은 준비 중입니다. (네이티브 플러그인 필요)", "code": "GOOGLE_MOBILE_NOT_READY"}
	if OS.has_feature("web"):
		# 웹: Firebase JS SDK 팝업으로 Google ID 토큰만 받고, 로그인/연결은 아래 REST 경로로 (PC와 동일)
		var web := WebGoogleAuth.new()
		add_child(web)
		var w: Dictionary = await web.authorize(config, is_signed_in() and is_anonymous())
		web.queue_free()
		if not w["ok"]:
			return {"ok": false, "error": w["error"], "code": "GOOGLE_WEB"}
		return await sign_in_with_google_id_token(w["id_token"])
	if not config.is_google_ready():
		return {"ok": false, "error": "Google 로그인 설정(데스크톱 OAuth 클라이언트 ID)이 없습니다.", "code": "GOOGLE_NOT_CONFIGURED"}
	var oauth := GoogleDesktopOAuth.new()
	add_child(oauth)
	var g := await oauth.authorize(config)
	oauth.queue_free()
	if not g["ok"]:
		return {"ok": false, "error": g["error"], "code": "GOOGLE_OAUTH"}
	return await sign_in_with_google_id_token(g["id_token"])


## Google ID 토큰으로 Firebase 로그인 (모바일 플러그인도 이 함수를 사용하게 될 것)
func sign_in_with_google_id_token(google_id_token: String) -> Dictionary:
	var body := {
		"postBody": "id_token=%s&providerId=google.com" % google_id_token,
		"requestUri": "http://localhost",
		"returnIdpCredential": true,
		"returnSecureToken": true,
	}
	if is_signed_in() and is_anonymous():
		var tok := await get_valid_id_token()
		if tok != "":
			body["idToken"] = tok
	return await _auth_call("accounts:signInWithIdp", body)


func sign_out() -> void:
	uid = ""
	id_token = ""
	refresh_token = ""
	expires_at = 0
	email = ""
	provider = ""
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(SESSION_PATH)
	auth_changed.emit()


# ------------------------------------------------------------------ 세션

## 저장된 세션으로 자동 로그인 (리프레시 토큰으로 새 ID 토큰 발급). 성공 여부 반환.
func restore_session() -> bool:
	if not is_configured() or not FileAccess.file_exists(SESSION_PATH):
		return false
	var cf := ConfigFile.new()
	if cf.load_encrypted_pass(SESSION_PATH, _session_pass()) != OK:
		return false
	refresh_token = str(cf.get_value("session", "refresh_token", ""))
	uid = str(cf.get_value("session", "uid", ""))
	if refresh_token == "" or uid == "":
		sign_out()
		return false
	var ok := await refresh()
	if not ok:
		sign_out()
	return ok


## 서버 접속 시 사용할 유효한 ID 토큰 (만료 5분 전이면 자동 갱신). 실패 시 "".
func get_valid_id_token() -> String:
	if not is_signed_in():
		return ""
	if int(Time.get_unix_time_from_system()) >= expires_at - REFRESH_MARGIN_SEC:
		if not await refresh():
			return ""
	return id_token


func refresh() -> bool:
	if _refreshing:
		return await _refresh_done
	_refreshing = true
	var r := await HttpUtil.post_form(self, config.token_base_url + "/token?key=" + config.api_key,
		{"grant_type": "refresh_token", "refresh_token": refresh_token})
	var ok := false
	if r["ok"] and typeof(r["json"]) == TYPE_DICTIONARY:
		var j: Dictionary = r["json"]
		_apply_tokens(str(j.get("id_token", "")), str(j.get("refresh_token", "")), int(j.get("expires_in", "3600")))
		ok = id_token != ""
	_refreshing = false
	_refresh_done.emit(ok)
	return ok


# ------------------------------------------------------------------ 내부

func _auth_call(endpoint: String, body: Dictionary) -> Dictionary:
	if not is_configured():
		return {"ok": false, "error": "Firebase 설정(config/firebase.cfg)이 없습니다.", "code": "NOT_CONFIGURED"}
	var r := await _post(config.auth_base_url + "/" + endpoint + "?key=" + config.api_key, body)
	if not r["ok"]:
		return _from_response(r)
	var j: Dictionary = r["json"]
	_apply_tokens(str(j.get("idToken", "")), str(j.get("refreshToken", "")), int(j.get("expiresIn", "3600")))
	if id_token == "":
		return _err("NO_TOKEN")
	return {"ok": true, "error": "", "code": ""}


func _post(url: String, body: Dictionary) -> Dictionary:
	return await HttpUtil.post_json(self, url, body)


func _apply_tokens(p_id_token: String, p_refresh: String, expires_in: int) -> void:
	if p_id_token == "":
		return
	id_token = p_id_token
	if p_refresh != "":
		refresh_token = p_refresh
	expires_at = int(Time.get_unix_time_from_system()) + expires_in
	# 표시용 정보는 토큰 payload에서 읽는다 (신뢰 판단은 게임 서버가 서명 검증으로 수행)
	var p := Jwt.unsafe_payload(id_token)
	uid = str(p.get("user_id", p.get("sub", uid)))
	email = str(p.get("email", ""))
	var fb: Variant = p.get("firebase")
	provider = str(fb.get("sign_in_provider", "")) if typeof(fb) == TYPE_DICTIONARY else ""
	_save_session()
	auth_changed.emit()


func _save_session() -> void:
	if not persist_session:
		return
	var cf := ConfigFile.new()
	cf.set_value("session", "uid", uid)
	cf.set_value("session", "refresh_token", refresh_token)
	cf.save_encrypted_pass(SESSION_PATH, _session_pass())


## 세션 파일 암호화 키: 기기 고유값 기반 (다른 기기로 복사된 파일은 열리지 않음)
func _session_pass() -> String:
	# 웹은 기기 고유값이 없음 → 고정값 (세션은 이 사이트의 브라우저 저장소에만 있음)
	return "3dpw-" + ("web" if OS.has_feature("web") else OS.get_unique_id())


func _validate_email_pw(p_email: String, password: String) -> Dictionary:
	if not _looks_like_email(p_email):
		return _err("INVALID_EMAIL")
	if password.length() < 6:
		return _err("WEAK_PASSWORD")
	return {}


func _looks_like_email(s: String) -> bool:
	var t := s.strip_edges()
	var at := t.find("@")
	return at > 0 and t.find(".", at) > at + 1 and not t.ends_with(".") and t.length() <= 254


func _from_response(r: Dictionary) -> Dictionary:
	if r["code"] == 0:
		return _err("NETWORK")
	var msg := ""
	if typeof(r["json"]) == TYPE_DICTIONARY and typeof(r["json"].get("error")) == TYPE_DICTIONARY:
		msg = str(r["json"]["error"].get("message", ""))
	elif typeof(r["json"]) == TYPE_DICTIONARY:
		msg = str(r["json"].get("error", ""))  # securetoken / oauth 형식
	var code := msg.get_slice(" ", 0).get_slice(":", 0).strip_edges()
	if msg.begins_with("API key not valid"):
		code = "API_KEY_INVALID"
	return _err(code if code != "" else "HTTP_%d" % r["code"])


const MESSAGES := {
	"EMAIL_EXISTS": "이미 가입된 이메일입니다.",
	"EMAIL_NOT_FOUND": "이메일 또는 비밀번호가 올바르지 않습니다.",
	"INVALID_PASSWORD": "이메일 또는 비밀번호가 올바르지 않습니다.",
	"INVALID_LOGIN_CREDENTIALS": "이메일 또는 비밀번호가 올바르지 않습니다.",
	"INVALID_EMAIL": "이메일 형식이 올바르지 않습니다.",
	"WEAK_PASSWORD": "비밀번호는 6자 이상이어야 합니다.",
	"USER_DISABLED": "이용이 정지된 계정입니다.",
	"TOO_MANY_ATTEMPTS_TRY_LATER": "시도가 너무 많습니다. 잠시 후 다시 시도해 주세요.",
	"OPERATION_NOT_ALLOWED": "Firebase 콘솔에서 이 로그인 방법이 꺼져 있습니다.",
	"ADMIN_ONLY_OPERATION": "Firebase 콘솔에서 이 로그인 방법이 꺼져 있습니다.",
	"CREDENTIAL_TOO_OLD_LOGIN_AGAIN": "보안을 위해 다시 로그인해 주세요.",
	"TOKEN_EXPIRED": "로그인이 만료되었습니다. 다시 로그인해 주세요.",
	"INVALID_REFRESH_TOKEN": "로그인이 만료되었습니다. 다시 로그인해 주세요.",
	"USER_NOT_FOUND": "계정을 찾을 수 없습니다. 다시 로그인해 주세요.",
	"FEDERATED_USER_ID_ALREADY_LINKED": "이 Google 계정은 이미 다른 계정에 연결되어 있습니다.",
	"API_KEY_INVALID": "Firebase API 키가 올바르지 않습니다. (config/firebase.cfg 확인)",
	"NOT_ANONYMOUS": "게스트 계정에서만 연결할 수 있습니다.",
	"NETWORK": "인증 서버에 연결할 수 없습니다. 인터넷 연결을 확인해 주세요.",
	"NO_TOKEN": "로그인 응답이 올바르지 않습니다.",
}


func _err(code: String) -> Dictionary:
	return {"ok": false, "error": MESSAGES.get(code, "로그인 오류 (%s)" % code), "code": code}
