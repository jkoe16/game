extends Node
## Autoload "PlayerData" — 로그인한 플레이어 자신의 Firestore 데이터 (클라이언트 측).
##  profiles/{uid} : 닉네임·외형 — 본인만 수정 (보안 규칙이 형식 검증)
##  stats/{uid}    : 플레이 기록 — 읽기만 가능 (게임 서버만 기록)

var fs: FirestoreClient
var profile := {}   # 마지막으로 읽거나 저장한 프로필
var stats := {}


func _ready() -> void:
	fs = FirestoreClient.new()
	fs.name = "Firestore"
	add_child(fs)
	var cfg: FirebaseConfig = Auth.config
	fs.setup(cfg.project_id, Auth.get_valid_id_token, cfg.firestore_base_url)


func is_available() -> bool:
	return Auth.is_configured() and Auth.is_signed_in()


## 반환 {ok, exists, error}. 프로필이 아직 없으면 ok=true, exists=false
func load_profile() -> Dictionary:
	if not is_available():
		return {"ok": false, "exists": false, "error": "not_signed_in"}
	var r: Dictionary = await fs.get_doc("profiles/" + Auth.uid)
	if r["ok"]:
		profile = r["data"]
		return {"ok": true, "exists": true, "error": ""}
	if r["status"] == 404:
		profile = {}
		return {"ok": true, "exists": false, "error": ""}
	return {"ok": false, "exists": false, "error": r["error"]}


func save_profile(nickname: String, appearance: Dictionary) -> Dictionary:
	if not is_available():
		return {"ok": false, "error": "not_signed_in"}
	var nick := Validation.sanitize_nickname(nickname)
	if nick == "":
		return {"ok": false, "error": "bad_nickname"}
	var data := {"nickname": nick, "appearance": Appearance.sanitize(appearance)}
	if data == profile:
		return {"ok": true, "error": ""}  # 변경 없음
	var r: Dictionary = await fs.set_fields("profiles/" + Auth.uid, data)
	if r["ok"]:
		profile = data
	return {"ok": r["ok"], "error": r["error"]}


func load_stats() -> Dictionary:
	if not is_available():
		return {"ok": false, "error": "not_signed_in"}
	var r: Dictionary = await fs.get_doc("stats/" + Auth.uid)
	stats = r["data"] if r["ok"] else {}
	return {"ok": r["ok"] or r["status"] == 404, "error": r["error"]}


func clear() -> void:
	profile = {}
	stats = {}
