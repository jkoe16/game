class_name CoopMode
extends GameMode
## 협동 미션: 각 방의 발판을 "동시에" 필요한 수만큼 밟고 1초 버티면 다음 문이 열린다. 3단계 클리어 = 팀 전원 승리.
## 필요 발판 수 = 참가 인원(최대 4). 순위 경쟁 없음 — 결과도 팀 단위.

const HOLD_TICKS := 60

var stage := 0
var required := 1
var hold := 0
var occupied: Array = []
var success := false


func mode_id() -> String:
	return "coop"

func title() -> String:
	return "협동 미션"

func rules_text() -> String:
	return "다 같이 발판을 밟아 문을 열어요! (필요 인원만큼 동시에)"


func _on_round_start() -> void:
	stage = 0
	hold = 0
	success = false
	required = clampi(playing_entries().size(), 1, 4)
	var m := map as CoopRoomsMap
	for i in m.gates.size():
		m.set_gate_open(i, false)


func _on_reset() -> void:
	_on_round_start()


func _mode_tick() -> void:
	var m := map as CoopRoomsMap
	if stage >= m.stage_plates.size():
		return
	var plates: Array = m.stage_plates[stage]
	var occ: Array = []
	for p in plates:
		var on := false
		for e in entries.values():
			if e["status"] != "playing":
				continue
			var pos: Vector3 = server.get_player_pos(e["peer_id"])
			if Vector2(pos.x - p.x, pos.z - p.z).length() <= m.PLATE_RADIUS and pos.y - p.y > -0.5 and pos.y - p.y < 2.5:  # 발판 위에서 점프해도 인정
				on = true
				break
		occ.append(on)
	if occ != occupied:
		occupied = occ
		dirty = true
	var count := occ.count(true)
	hold = hold + 1 if count >= required else 0
	if hold >= HOLD_TICKS:
		m.set_gate_open(stage, true)
		stage += 1
		hold = 0
		occupied = []
		for e in entries.values():
			if e["status"] == "playing":
				e["score"] = stage
		if stage >= m.stage_plates.size():
			success = true
		dirty = true


func _is_over() -> bool:
	return success


func on_fell(_peer_id: int) -> Vector3:
	return (map as CoopRoomsMap).stage_start(stage)


func _ranked() -> Array:
	return entries.values()


func _score_text(_e: Dictionary) -> String:
	return "성공!" if success else "%d/3 단계" % stage


func _is_win(_e: Dictionary, _rank: int) -> bool:
	return success


## 협동: 순위 없이 모두 같은 보상
func _xp_for(_rank: int, _n: int, win: bool) -> int:
	return 60 if win else 25


func _extra_state() -> Dictionary:
	var opened: Array = []
	for i in stage:
		opened.append(i)
	return {"stage": stage, "required": required, "occupied": occupied, "opened": opened, "success": success}
