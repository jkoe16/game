class_name ObstacleRaceMode
extends GameMode
## 장애물 레이스: 회전 막대·이동 발판·점프 패드 코스를 지나 결승선 통과 순서로 순위.
## 떨어지면 마지막 체크포인트에서 재출발(벌칙 없음). 첫 완주 후 25초 안에 들어와야 완주 인정.

const FINISH_WINDOW := 25


func _init() -> void:
	round_ticks = 150 * 60


func mode_id() -> String:
	return "obstacle_race"

func title() -> String:
	return "장애물 레이스"

func rules_text() -> String:
	return "망치를 점프로 넘고 결승선까지! ? 상자는 속도·점프·보호막 아이템. 떨어져도 체크포인트에서 다시 시작"


func _init_entry(e: Dictionary) -> void:
	e["checkpoint"] = 0
	e["progress"] = 0.0
	e["finish_tick"] = 0


func _mode_tick() -> void:
	var m := map as RaceCourseMap
	for e in entries.values():
		if e["status"] != "playing":
			continue
		var pos: Vector3 = server.get_player_pos(e["peer_id"])
		var cp := m.checkpoint_index_at(pos)
		if cp > e["checkpoint"]:
			e["checkpoint"] = cp
			server.notify_player(e["peer_id"], "!체크포인트 %d/%d" % [cp, m.checkpoints.size() - 1])
		e["progress"] = maxf(e["progress"], clampf(pos.z / m.finish_z, 0.0, 1.0))
		if m.is_finished(pos):
			e["status"] = "finished"
			e["finish_tick"] = tick - round_start_tick
			e["progress"] = 1.0
			dirty = true
			if _finished_count() == 1:
				start_finish_timer(FINISH_WINDOW)
			else:
				server.notify_player(e["peer_id"], "!완주! %d등" % _finished_count())


func _finished_count() -> int:
	return entries.values().filter(func(e: Dictionary) -> bool: return e["status"] == "finished").size()


func _is_over() -> bool:
	var active := playing_entries()
	return active.size() > 0 and active.all(func(e: Dictionary) -> bool: return e["status"] == "finished")


func on_fell(peer_id: int) -> Vector3:
	var e: Dictionary = entries.get(peer_id, {})
	return (map as RaceCourseMap).checkpoint_point(int(e.get("checkpoint", 0)), peer_id)


func _ranked() -> Array:
	var arr := entries.values()
	arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var af: bool = a["status"] == "finished"
		var bf: bool = b["status"] == "finished"
		if af != bf:
			return af
		if af:
			return a["finish_tick"] < b["finish_tick"]
		return a["progress"] > b["progress"])
	return arr


func _score_text(e: Dictionary) -> String:
	if e["status"] == "finished":
		return "완주 %.1f초" % (e["finish_tick"] / 60.0)
	return "진행 %d%%" % int(e["progress"] * 100)


## 완주자는 모두 승리 보너스 (1등만이 아니라 "결승선까지 간 것"을 보상)
func _is_win(e: Dictionary, _rank: int) -> bool:
	return e["status"] == "finished"
