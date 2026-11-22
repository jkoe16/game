class_name FirebaseConfig
extends RefCounted
## Firebase 설정 로더.
## 기본 파일: res://config/firebase.cfg (git 제외). 예시: res://config/firebase.example.cfg
## 실행 인자 --firebase-config=<경로> 로 다른 파일 사용 가능 (테스트용 목 서버 등).
##
## 주의: 웹 API 키 / 프로젝트 ID / 데스크톱 OAuth 클라이언트 정보는 클라이언트 배포가 전제된 값이다.
##       서비스 계정 키·DB 비밀번호 같은 진짜 비밀은 절대 이 파일에 넣지 않는다.

const DEFAULT_PATH := "res://config/firebase.cfg"

var api_key := ""
var project_id := ""
var auth_base_url := "https://identitytoolkit.googleapis.com/v1"
var token_base_url := "https://securetoken.googleapis.com/v1"
var jwks_url := "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"
var firestore_base_url := "https://firestore.googleapis.com/v1"
var google_client_id := ""
var google_client_secret := ""
var google_auth_url := "https://accounts.google.com/o/oauth2/v2/auth"
var google_token_url := "https://oauth2.googleapis.com/token"
var source_path := ""


static func load_default() -> FirebaseConfig:
	var path := DEFAULT_PATH
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--firebase-config="):
			path = a.substr("--firebase-config=".length())
	return load_from(path)


static func load_from(path: String) -> FirebaseConfig:
	var c := FirebaseConfig.new()
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return c
	c.source_path = path
	c.api_key = str(cf.get_value("firebase", "api_key", "")).strip_edges()
	c.project_id = str(cf.get_value("firebase", "project_id", "")).strip_edges()
	c.auth_base_url = str(cf.get_value("firebase", "auth_base_url", c.auth_base_url))
	c.token_base_url = str(cf.get_value("firebase", "token_base_url", c.token_base_url))
	c.jwks_url = str(cf.get_value("firebase", "jwks_url", c.jwks_url))
	c.firestore_base_url = str(cf.get_value("firebase", "firestore_base_url", c.firestore_base_url))
	c.google_client_id = str(cf.get_value("google_oauth", "desktop_client_id", "")).strip_edges()
	c.google_client_secret = str(cf.get_value("google_oauth", "desktop_client_secret", "")).strip_edges()
	c.google_auth_url = str(cf.get_value("google_oauth", "auth_url", c.google_auth_url))
	c.google_token_url = str(cf.get_value("google_oauth", "token_url", c.google_token_url))
	return c


func is_client_ready() -> bool:
	return api_key != "" and project_id != ""


func is_server_ready() -> bool:
	return project_id != ""


func is_google_ready() -> bool:
	return google_client_id != ""
