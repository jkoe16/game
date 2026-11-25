class_name LobbyMode
extends GameMode
## 로비: 라운드 없음. 게임 모드 포털 위에 1.5초 서 있으면 해당 모드 서버로 이동(transfer).
## routes: {"obstacle_race": "127.0.0.1:7781", ...} (실행 인자 --routes 로 지정, 추후 매치메이커가 대체)

const HOLD_TICKS := 90

var routes := {}
var _hold := {}   # peer_id -> {mode, ticks}


func mode_id() -> String:
	return "lobby"

func title() -> String:
	return "하늘 위의 광장"

func rules_text() -> String:
	return "포털 위에 서 있으면 게임에 입장해요"

func is_lobby() -> bool:
	return true


func on_player_joined(peer_id: int, nickname: String) -> Vector3:
	entries[peer_id] = {"peer_id": peer_id, "nickname": nickname, "status": "lobby", "score": 0}
	dirty = true
	return map.get_spawn_point(entries.size() - 1)


func is_frozen(_peer_id: int) -> bool:
	return false


func is_out(_peer_id: int) -> bool:
	return false


func server_tick(t: int) -> void:
	tick = t
	var portals: Array = (map as LobbyPlazaMap).portals
	for e in entries.values():
		var pid: int = e["peer_id"]
		var pos: Vector3 = server.get_player_pos(pid)
		var inside := ""
		for p in portals:
			if Vector2(pos.x - p["center"].x, pos.z - p["center"].z).length() <= p["radius"] and pos.y < 1.5:
				inside = p["mode"]
				break
		var h: Dictionary = _hold.get(pid, {"mode": "", "ticks": 0})
		if inside == "" or inside != h["mode"]:
			h = {"mode": inside, "ticks": 0}
		else:
			h["ticks"] += 1
			if h["ticks"] == HOLD_TICKS:
				if routes.has(inside):
					server.transfer_player(pid, routes[inside], inside)
				else:
					server.notify_player(pid, "아직 열리지 않은 게임이에요")
		_hold[pid] = h


func on_player_left(peer_id: int) -> void:
	entries.erase(peer_id)
	_hold.erase(peer_id)
	dirty = true


func on_player_rekeyed(old_id: int, new_id: int) -> void:
	super(old_id, new_id)
	_hold.erase(old_id)  # 포털 위에서 끊겼다면 다시 들어온 뒤 처음부터 기다림


func on_fell(_peer_id: int) -> Vector3:
	return map.get_spawn_point(0)


func public_state() -> Dictionary:
	return {"mode": "lobby", "title": title(), "rules": rules_text(), "phase": "lobby", "phase_end_tick": 0,
		"round_start_tick": 0, "tick": tick, "board": [], "players": {}, "results": [], "extra": {"open_modes": routes.keys()}}
