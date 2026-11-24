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
var _clear_tick := 0


func _init() -> void:
	round_ticks = 180 * 60


func mode_id() -> String:
	return "coop"

func title() -> String:
	return "협동 미션"

func rules_text() -> String:
	return "주황 발판 %d개를 동시에 밟고 버티면 문이 열려요! 2·3번 방은 막대를 점프로 넘으며 버티기. 빨리 깰수록 보너스" % required


func _on_round_start() -> void:
	stage = 0
	hold = 0
	success = false
	_clear_tick = 0
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
	# 중간에 나간 사람이 있어도 막히지 않게 필요 인원을 매 틱 다시 계산
	var need := clampi(entries.values().filter(func(e: Dictionary) -> bool: return e["status"] == "playing").size(), 1, 4)
	if need != required:
		required = need
		dirty = true
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
	# 방이 깊어질수록 조금 더 오래 버텨야 한다 (1초 → 1.5초 → 2초)
	if hold >= HOLD_TICKS + stage * 30:
		m.set_gate_open(stage, true)
		stage += 1
		hold = 0
		occupied = []
		for e in entries.values():
			if e["status"] == "playing":
				e["score"] = stage
		if stage >= m.stage_plates.size():
			success = true
			_clear_tick = tick - round_start_tick
		else:
			announce("%d번 문 열림! 다음 방으로" % stage)
		dirty = true


func _is_over() -> bool:
	return success


func on_fell(_peer_id: int) -> Vector3:
	return (map as CoopRoomsMap).stage_start(stage)


func _ranked() -> Array:
	return entries.values()


func _score_text(_e: Dictionary) -> String:
	return ("성공! %.0f초" % (_clear_tick / 60.0)) if success else "%d/3 단계" % stage


func _is_win(_e: Dictionary, _rank: int) -> bool:
	return success


## 협동: 순위 없이 모두 같은 보상
func _xp_for(_rank: int, _n: int, win: bool) -> int:
	if not win:
		return 25 + stage * 5   # 연 문 개수만큼 조금씩
	return 60 + (30 if _clear_tick < 90 * 60 else (15 if _clear_tick < 130 * 60 else 0))  # 빠른 클리어 팀 보너스


## 협동은 서로 경쟁하지 않으므로 보호막·속도만
func event_pool() -> Array:
	return ["부스트 출발", "보호막 출발"]


func _extra_state() -> Dictionary:
	var opened: Array = []
	for i in stage:
		opened.append(i)
	return {"stage": stage, "required": required, "occupied": occupied, "opened": opened, "success": success}
