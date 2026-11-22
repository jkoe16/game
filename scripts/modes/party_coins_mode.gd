class_name PartyCoinsMode
extends GameMode
## 파티 미니게임 "코인 모으기": 경기장에 흩어진 코인을 많이 모은 순. 코인이 다 떨어지면 새 웨이브.
## 코인 위치는 서버가 정하고, 획득 판정도 서버가 한다 (거리 1.3m).

const WAVE_SIZE := 16
const PICK_RADIUS := 1.3

var coins: Array = []   # [[x, y, z, alive(0/1)], ...]
var _rng := RandomNumberGenerator.new()
var wave := 0


func mode_id() -> String:
	return "party"

func title() -> String:
	return "파티: 코인 모으기"

func rules_text() -> String:
	return "반짝이는 코인을 가장 많이 모아요!"


func _on_round_start() -> void:
	_rng.seed = Time.get_ticks_usec()
	wave = 0
	_spawn_wave()


func _on_reset() -> void:
	coins = []


func _spawn_wave() -> void:
	wave += 1
	coins = []
	for p in (map as CoinArenaMap).random_coin_points(_rng, WAVE_SIZE):
		coins.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), 1])
	dirty = true


func _mode_tick() -> void:
	var any_alive := false
	for c in coins:
		if c[3] == 0:
			continue
		var cp := Vector3(c[0], c[1], c[2])
		for e in entries.values():
			if e["status"] != "playing":
				continue
			var pos: Vector3 = server.get_player_pos(e["peer_id"]) + Vector3(0, 0.8, 0)
			if pos.distance_to(cp) <= PICK_RADIUS:
				c[3] = 0
				e["score"] += 1
				dirty = true
				break
		if c[3] == 1:
			any_alive = true
	if not any_alive:
		_spawn_wave()


func _ranked() -> Array:
	var arr := entries.values()
	arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	return arr


func _score_text(e: Dictionary) -> String:
	return "코인 %d개" % e["score"]


func _is_win(e: Dictionary, rank: int) -> bool:
	return rank == 1 and e["score"] > 0


func _extra_state() -> Dictionary:
	return {"coins": coins, "wave": wave}
