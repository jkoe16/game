class_name PartyCoinsMode
extends GameMode
## 보물 수집: 경기장에 흩어진 보물을 모아 점수 경쟁.
##  금화 1점 · 보석 3점(높은 발판 위) · 황금 별 5점(가끔 가운데에 잠깐 등장)
##  마지막 20초는 "보너스 타임" — 모든 점수 2배 (역전 기회). 보물이 다 떨어지면 새 웨이브.
## 위치와 획득 판정은 서버가 한다 (거리 1.3m). 코인 배열: [x, y, z, alive(0/1), value]

const WAVE_COINS := 14
const PICK_RADIUS := 1.3
const STAR_EVERY := 30        # 초마다 황금 별
const STAR_LIFETIME := 10     # 초 동안만 존재
const BONUS_LAST := 20        # 마지막 N초 점수 2배

var coins: Array = []
var _rng := RandomNumberGenerator.new()
var wave := 0
var _next_star := 0
var _star_until := 0
var _bonus := false


func _init() -> void:
	round_ticks = 120 * 60


func mode_id() -> String:
	return "party"

func title() -> String:
	return "보물 수집"

func rules_text() -> String:
	return "금화 1점 · 높은 발판의 보석 3점 · 가운데 황금 별 5점! 마지막 20초는 점수 2배"


func _on_round_start() -> void:
	_rng.seed = Time.get_ticks_usec()
	wave = 0
	_bonus = false
	_next_star = tick + STAR_EVERY * 60
	_star_until = 0
	_spawn_wave()


func _on_reset() -> void:
	coins = []


func _spawn_wave() -> void:
	wave += 1
	coins = []
	var m := map as CoinArenaMap
	for p in m.random_coin_points(_rng, WAVE_COINS):
		coins.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), 1, 1])
	for pl in m.platforms:  # 발판마다 보석 1개 (높을수록 가치 있는 곳)
		var c: Vector3 = pl["center"]
		coins.append([c.x, float(pl["top"]) + 1.0, c.z, 1, 3])
	dirty = true


func _mode_tick() -> void:
	var left := phase_end_tick - tick
	if not _bonus and left <= BONUS_LAST * 60:
		_bonus = true
		announce("보너스 타임! 이제부터 점수 2배")
		dirty = true
	# 황금 별: 가운데에 잠깐 나타났다 사라진다
	if tick >= _next_star and left > STAR_LIFETIME * 60:
		_next_star = tick + STAR_EVERY * 60
		_star_until = tick + STAR_LIFETIME * 60
		coins.append([0.0, 1.2, 0.0, 1, 5])
		announce("가운데에 황금 별 등장! (5점)")
		dirty = true
	if _star_until > 0 and tick >= _star_until:
		_star_until = 0
		for c in coins:
			if c[4] == 5 and c[3] == 1:
				c[3] = 0
				dirty = true

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
				var pts: int = int(c[4]) * (2 if _bonus else 1)
				e["score"] += pts
				if c[4] >= 3:
					server.notify_player(e["peer_id"], "!+%d점!" % pts)
				dirty = true
				break
		if c[3] == 1 and c[4] < 5:
			any_alive = true
	if not any_alive:
		_spawn_wave()


func _ranked() -> Array:
	var arr := entries.values()
	arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	return arr


func _score_text(e: Dictionary) -> String:
	return "%d점" % e["score"]


func _is_win(e: Dictionary, rank: int) -> bool:
	return rank == 1 and e["score"] > 0


func _extra_state() -> Dictionary:
	return {"coins": coins, "wave": wave, "bonus": _bonus}
