class_name RacingMode
extends GameMode
## 레이싱(달리기): 순환 트랙 3바퀴. 체크포인트를 순서대로 통과해야 바퀴가 인정된다(지름길 방지).
## 부스트 패드·점프 패드 활용. 완주 순서로 순위.

const LAPS := 3
const FINISH_WINDOW := 25


func _init() -> void:
	round_ticks = 180 * 60


func mode_id() -> String:
	return "racing"

func title() -> String:
	return "레이싱"

func rules_text() -> String:
	return "트랙 %d바퀴! 노란 부스터로 빨라지고, 초록 점프대로 벽을 넘고, 남쪽 막대는 점프! ? 상자 = 아이템" % LAPS


func _init_entry(e: Dictionary) -> void:
	e["lap"] = 0
	e["next_cp"] = 1
	e["finish_tick"] = 0


func _mode_tick() -> void:
	var m := map as RaceTrackMap
	for e in entries.values():
		if e["status"] != "playing":
			continue
		var pos: Vector3 = server.get_player_pos(e["peer_id"])
		if m.in_checkpoint(pos, e["next_cp"]):
			if e["next_cp"] == 0:
				e["lap"] += 1
				if e["lap"] >= LAPS:
					e["status"] = "finished"
					e["finish_tick"] = tick - round_start_tick
					var n := entries.values().filter(func(x: Dictionary) -> bool: return x["status"] == "finished").size()
					if n == 1:
						start_finish_timer(FINISH_WINDOW)
					else:
						server.notify_player(e["peer_id"], "!완주! %d등" % n)
				elif e["lap"] == LAPS - 1:
					server.notify_player(e["peer_id"], "!마지막 바퀴!")
				else:
					server.notify_player(e["peer_id"], "!%d바퀴째" % (e["lap"] + 1))
			e["next_cp"] = (e["next_cp"] + 1) % m.checkpoints.size()
			dirty = true


func on_fell(peer_id: int) -> Vector3:
	var e: Dictionary = entries.get(peer_id, {})
	var m := map as RaceTrackMap
	var last := posmod(int(e.get("next_cp", 1)) - 1, m.checkpoints.size())
	return m.checkpoint_point(last)


func _is_over() -> bool:
	var active := playing_entries()
	return active.size() > 0 and active.all(func(e: Dictionary) -> bool: return e["status"] == "finished")


func _progress(e: Dictionary) -> int:
	var n := (map as RaceTrackMap).checkpoints.size()
	return e["lap"] * n + posmod(e["next_cp"] - 1, n)


func _ranked() -> Array:
	var arr := entries.values()
	arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var af: bool = a["status"] == "finished"
		var bf: bool = b["status"] == "finished"
		if af != bf:
			return af
		if af:
			return a["finish_tick"] < b["finish_tick"]
		return _progress(a) > _progress(b))
	return arr


func _score_text(e: Dictionary) -> String:
	if e["status"] == "finished":
		return "완주 %.1f초" % (e["finish_tick"] / 60.0)
	return "%d/%d 바퀴" % [mini(e["lap"] + 1, LAPS), LAPS]


func _is_win(e: Dictionary, _rank: int) -> bool:
	return e["status"] == "finished"
