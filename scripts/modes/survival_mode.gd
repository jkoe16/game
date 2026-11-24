class_name SurvivalMode
extends GameMode
## 최후의 생존자: 점점 빨라지는 회전 막대(최고 속도 제한)를 넘으며 원형 무대에서 버티기.
## 목숨 2개 — 처음 떨어지면 무대로 돌아오고, 두 번째에 탈락(관전).
## 2명 이상 시작했으면 1명 남을 때, 혼자면 탈락할 때까지. 시간이 끝까지 가면 살아남은 모두 승리.

const LIVES := 2
## 단계 안내 (라운드 시작 후 초)
const STAGE_TIMES := [27, 55, 72]

var _started_with := 0
var _stage := 0
var _gust_warned := -1


func _init() -> void:
	round_ticks = 120 * 60


func mode_id() -> String:
	return "survival"

func title() -> String:
	return "최후의 생존자"

func rules_text() -> String:
	return "섬이 무너져요! 흔들리는 타일을 피하고, 돌풍엔 반대로 걸어 버텨요. 빨간 막대는 점프·파란 막대는 점프 금지! 목숨 2개"


func _init_entry(e: Dictionary) -> void:
	e["out_tick"] = 0
	e["lives"] = LIVES


func _on_round_start() -> void:
	_started_with = playing_entries().size()
	_stage = 0
	(map as SurvivalArenaMap).crumble_start = round_start_tick
	dirty = true


func _on_reset() -> void:
	(map as SurvivalArenaMap).crumble_start = 0


func _mode_tick() -> void:
	var m := map as SurvivalArenaMap
	var g := m.next_gust_tick(tick)
	if g > 0 and g - tick <= 120 and g != _gust_warned:
		_gust_warned = g
		announce("2초 뒤 돌풍! 바람 반대쪽으로 걸어요")
	if _stage < STAGE_TIMES.size() and tick - round_start_tick >= STAGE_TIMES[_stage] * 60:
		_stage += 1
		announce(["섬 가장자리가 무너지기 시작해요!", "막대가 더 빨라져요! 집중!", "안쪽 타일도 무너져요! 가운데로!"][_stage - 1])


func on_fell(peer_id: int) -> Vector3:
	var e: Dictionary = entries.get(peer_id, {})
	if phase == "playing" and e.get("status") == "playing":
		e["lives"] = int(e.get("lives", 1)) - 1
		dirty = true
		if e["lives"] > 0:
			server.notify_player(peer_id, "!목숨 %d개 남았어요" % e["lives"])
			return _safe_respawn(peer_id)
		e["status"] = "out"
		e["out_tick"] = tick - round_start_tick
		var left := _alive()
		if left >= 2:
			announce("%s 탈락! 남은 사람 %d명" % [e["nickname"], left])
		return Vector3.INF
	return (map as SurvivalArenaMap).spectator_point() if is_out(peer_id) else map.get_spawn_point(0)


## 다시 떨어질 때 막대 바로 앞이나 무너진 곳에 놓이지 않게: 가운데 원판 위, 두 막대에서 가장 먼 지점
func _safe_respawn(_peer_id: int) -> Vector3:
	var best := Vector3(0, 0.5, 3.0)
	var best_d := -1.0
	for i in 8:
		var a := TAU * i / 8.0
		var p := Vector3(sin(a) * 3.2, 0.5, cos(a) * 3.2)
		var d := INF
		for s in map.sweepers:
			var da := map.sweeper_angle(s, tick + 30) - atan2(p.x, p.z)
			d = minf(d, absf(wrapf(da, -PI, PI)))
			if s["arms"] == 2:
				d = minf(d, absf(wrapf(da + PI, -PI, PI)))
		if d > best_d:
			best_d = d
			best = p
	return best


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
		if aa:
			return int(a.get("lives", 0)) > int(b.get("lives", 0))
		return a["out_tick"] > b["out_tick"])
	return arr


func _score_text(e: Dictionary) -> String:
	if e["status"] == "playing":
		return "생존! 목숨 %d" % int(e.get("lives", 0))
	return "%.1f초 버팀" % (e["out_tick"] / 60.0)


## 끝까지 살아남은 사람은 모두 승리
func _is_win(e: Dictionary, _rank: int) -> bool:
	return e["status"] == "playing"


func _extra_state() -> Dictionary:
	return {"alive": _alive(), "crumble": (map as SurvivalArenaMap).crumble_start}
