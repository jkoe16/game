class_name SurvivalMode
extends GameMode
## 생존: 점점 빨라지는 회전 막대를 점프로 넘으며 원형 무대에서 버티기. 떨어지면 탈락(관전).
## 2명 이상 시작했으면 1명 남을 때, 혼자면 탈락하거나 시간이 끝날 때 종료. 오래 버틴 순.

var _started_with := 0


func mode_id() -> String:
	return "survival"

func title() -> String:
	return "생존 게임"

func rules_text() -> String:
	return "빨라지는 막대를 점프로 넘으며 끝까지 버텨요!"


func _init_entry(e: Dictionary) -> void:
	e["out_tick"] = 0


func _on_round_start() -> void:
	_started_with = playing_entries().size()


func on_fell(peer_id: int) -> Vector3:
	var e: Dictionary = entries.get(peer_id, {})
	if phase == "playing" and e.get("status") == "playing":
		e["status"] = "out"
		e["out_tick"] = tick - round_start_tick
		dirty = true
		return Vector3.INF
	return (map as SurvivalArenaMap).spectator_point() if is_out(peer_id) else map.get_spawn_point(0)


func spectator_point() -> Vector3:
	return (map as SurvivalArenaMap).spectator_point()


func _alive() -> int:
	return entries.values().filter(func(e: Dictionary) -> bool: return e["status"] == "playing").size()


func _is_over() -> bool:
	if _started_with >= 2:
		return _alive() <= 1
	return _alive() == 0


func _ranked() -> Array:
	var arr := entries.values()
	arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var aa: bool = a["status"] == "playing"
		var ba: bool = b["status"] == "playing"
		if aa != ba:
			return aa
		return a["out_tick"] > b["out_tick"])
	return arr


func _score_text(e: Dictionary) -> String:
	if e["status"] == "playing":
		return "생존!" if phase != "playing" else "생존 중"
	return "%.1f초 버팀" % (e["out_tick"] / 60.0)


func _is_win(e: Dictionary, rank: int) -> bool:
	return rank == 1 and e["status"] == "playing"


func _extra_state() -> Dictionary:
	return {"alive": _alive()}
