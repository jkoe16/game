class_name WebGoogleAuth
extends Node
## 웹 빌드용 Google 로그인: Firebase JS SDK(compat, 웹 페이지 <head>에서 로드) 팝업으로 Google ID 토큰만 받는다.
## 실제 Firebase 로그인/계정 연결은 기존 REST 경로(Auth.sign_in_with_google_id_token)가 처리 → PC와 동작 동일.
##
## 게스트 연결(link_mode): JS 팝업이 Google 계정으로 "새 Firebase 사용자"를 만들었다면 즉시 삭제하고
## 토큰만 돌려준다. 그래야 REST에서 게스트 uid에 Google을 연결할 수 있다 (이미 있던 계정이면 PC와 같은 오류).
##
## 페이지 쪽 JS는 export_presets.cfg 의 html/head_include (window.pwGoogleSignIn) 에 있다.
## 필요 설정: Firebase 콘솔 → Authentication → 설정 → 승인된 도메인에 배포 도메인(jkoe16.github.io) 추가.

signal _done(result: Dictionary)

var _cb: JavaScriptObject


func authorize(config: FirebaseConfig, link_mode: bool) -> Dictionary:
	if not OS.has_feature("web"):
		return {"ok": false, "error": "웹 전용 기능입니다."}
	var win := JavaScriptBridge.get_interface("window")
	if win == null or JavaScriptBridge.eval("typeof window.pwGoogleSignIn", true) != "function":
		return {"ok": false, "error": "Google 로그인 스크립트를 불러오지 못했습니다. 새로고침 후 다시 시도해 주세요."}
	_cb = JavaScriptBridge.create_callback(_on_js_result)
	win.pwGoogleSignIn(config.api_key, config.project_id + ".firebaseapp.com", link_mode, _cb)
	var r: Dictionary = await _done
	_cb = null
	return r


func _on_js_result(args: Array) -> void:
	var j: Variant = JSON.parse_string(str(args[0])) if args.size() > 0 else null
	if typeof(j) != TYPE_DICTIONARY:
		_done.emit({"ok": false, "error": "Google 로그인 응답이 올바르지 않습니다."})
		return
	if j.get("ok", false) and str(j.get("id_token", "")) != "":
		_done.emit({"ok": true, "id_token": str(j["id_token"])})
		return
	_done.emit({"ok": false, "error": _message(str(j.get("code", "")), str(j.get("message", "")))})


static func _message(code: String, raw: String) -> String:
	match code:
		"auth/popup-blocked":
			return "팝업이 차단되었습니다. 브라우저에서 팝업을 허용한 뒤 다시 눌러 주세요."
		"auth/popup-closed-by-user", "auth/cancelled-popup-request":
			return "Google 로그인 창이 닫혔습니다."
		"auth/unauthorized-domain":
			return "이 사이트 주소가 Firebase 승인 도메인에 없습니다. (Firebase 콘솔 → Authentication → 설정 → 승인된 도메인)"
		"auth/network-request-failed":
			return "인증 서버에 연결할 수 없습니다. 인터넷 연결을 확인해 주세요."
	return "Google 로그인 오류 (%s)" % (code if code != "" else raw)
