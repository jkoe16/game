class_name ModeRegistry
extends RefCounted
## 모드 ID → (규칙 스크립트, 맵 ID, 기본 포트). 새 게임 모드는 여기에 한 줄 추가.

const MODES := {
	"lobby": {"script": "res://scripts/modes/lobby_mode.gd", "map": "lobby_plaza", "port": 7777, "max_players": 24},
	"obstacle_race": {"script": "res://scripts/modes/obstacle_race_mode.gd", "map": "race_course", "port": 7781, "max_players": 8},
	"survival": {"script": "res://scripts/modes/survival_mode.gd", "map": "survival_arena", "port": 7782, "max_players": 8},
	"racing": {"script": "res://scripts/modes/racing_mode.gd", "map": "race_track", "port": 7783, "max_players": 8},
	"coop": {"script": "res://scripts/modes/coop_mode.gd", "map": "coop_rooms", "port": 7784, "max_players": 4},
	"party": {"script": "res://scripts/modes/party_coins_mode.gd", "map": "coin_arena", "port": 7785, "max_players": 8},
}


static func has_mode(mode_id: String) -> bool:
	return MODES.has(mode_id)


static func create(mode_id: String) -> GameMode:
	if not MODES.has(mode_id):
		return null
	var mode: GameMode = load(MODES[mode_id]["script"]).new()
	mode.name = "Mode"
	return mode


static func map_for(mode_id: String) -> String:
	return MODES.get(mode_id, {}).get("map", "")


## 같은 PC에서 모든 모드 서버를 띄울 때의 기본 경로표.
## host를 비우면 ":7781" 형태 → 클라이언트가 "지금 접속한 서버와 같은 주소"의 다른 포트로 이동 (친구가 내 PC IP로 접속해도 동작)
static func default_routes(host := "") -> Dictionary:
	var r := {}
	for id in MODES:
		if id != "lobby":
			r[id] = "%s:%d" % [host, MODES[id]["port"]]
	return r
