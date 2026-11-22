class_name ServiceAccountAuth
extends Node
## 게임 서버 전용: Google 서비스 계정 키(JSON)로 OAuth2 액세스 토큰 발급 (JWT Bearer, RFC 7523).
## 키 파일은 서버 PC에만 둔다 — 저장소/게임 클라이언트에 절대 포함 금지.
## 경로 지정: 실행 인자 --service-account=<경로> 또는 환경변수 GOOGLE_APPLICATION_CREDENTIALS

const SCOPE := "https://www.googleapis.com/auth/datastore"
const REFRESH_MARGIN_SEC := 300

var client_email := ""
var token_uri := "https://oauth2.googleapis.com/token"
var project_id := ""
var _key: CryptoKey
var _key_id := ""
var _access_token := ""
var _expires_at := 0


static func find_key_path(args: Dictionary) -> String:
	if args.has("service-account"):
		return str(args["service-account"])
	return OS.get_environment("GOOGLE_APPLICATION_CREDENTIALS")


## 반환: 오류 메시지 ("" = 성공)
func load_key_file(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return "서비스 계정 파일을 읽을 수 없습니다: %s" % path
	var j: Variant = JSON.parse_string(text)
	if typeof(j) != TYPE_DICTIONARY or j.get("type") != "service_account":
		return "서비스 계정 JSON 형식이 아닙니다."
	client_email = str(j.get("client_email", ""))
	token_uri = str(j.get("token_uri", token_uri))
	project_id = str(j.get("project_id", ""))
	_key_id = str(j.get("private_key_id", ""))
	_key = CryptoKey.new()
	if _key.load_from_string(str(j.get("private_key", ""))) != OK:
		return "서비스 계정 비공개 키를 불러올 수 없습니다."
	return ""


## await 가능. 실패 시 ""
func get_access_token() -> String:
	if _access_token != "" and int(Time.get_unix_time_from_system()) < _expires_at - REFRESH_MARGIN_SEC:
		return _access_token
	var now := int(Time.get_unix_time_from_system())
	var header := {"alg": "RS256", "typ": "JWT", "kid": _key_id}
	var claims := {"iss": client_email, "scope": SCOPE, "aud": token_uri, "iat": now, "exp": now + 3600}
	var input := Jwt.b64url_encode(JSON.stringify(header).to_utf8_buffer()) + "." + Jwt.b64url_encode(JSON.stringify(claims).to_utf8_buffer())
	var sig := Crypto.new().sign(HashingContext.HASH_SHA256, Jwt.sha256(input.to_utf8_buffer()), _key)
	var r := await HttpUtil.post_form(self, token_uri, {
		"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
		"assertion": input + "." + Jwt.b64url_encode(sig),
	})
	if not r["ok"] or typeof(r["json"]) != TYPE_DICTIONARY or not r["json"].has("access_token"):
		push_warning("[DATA] service account token request failed (HTTP %d): %s" % [r["code"], r["text"].left(200)])
		return ""
	_access_token = str(r["json"]["access_token"])
	_expires_at = now + int(r["json"].get("expires_in", 3600))
	return _access_token
