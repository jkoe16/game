class_name PartyCoinsMode
extends GameMode
## 보물 수집: 보물섬에 흩어진 보물을 모아 점수 경쟁.
##  일반 금화 1 · 희귀 보석 3(높은 발판) · 황금 별 5(가운데, 회전 막대가 지킴) · 전설 보물상자 10(숨은 장소, 가끔)
##  높은 발판 = 보너스 구역(2배). 마지막 20초는 보너스 타임(전부 2배). 웨이브마다 배치 모양이 바뀐다.
## 위치와 획득 판정은 서버가 한다 (거리 1.3m). 코인 배열: [x, y, z, alive(0/1), value]

const WAVE_COINS := 14
const PICK_RADIUS := 1.3
const STAR_EVERY := 30        # 초마다 황금 별
const STAR_LIFETIME := 10     # 초 동안만 존재
const BONUS_LAST := 20        # 마지막 N초 점수 2배
const CHEST_FIRST := 35       # 전설 보물상자 첫 등장(초), 이후 40초마다
const CHEST_EVERY := 40
const CHEST_LIFETIME := 14

var coins: Array = []
var _rng := RandomNumberGenerator.new()
var wave := 0
var _next_star := 0
var _star_until := 0
var _bonus := false
var _next_chest := 0
var _chest_until := 0
var _star_every := STAR_EVERY


func _init() -> void:
	round_ticks = 120 * 60


func mode_id() -> String:
	return "party"

func title() -> String:
	return "보물 수집"

func rules_text() -> String:
	return "금화 1 · 보석 3 · 가운데 별 5 · 숨은 전설 상자 10점! 높은 발판은 2배 구역, 마지막 20초는 모두 2배"


func _on_round_start() -> void:
	_rng.seed = Time.get_ticks_usec()
	wave = 0
	_bonus = false
	_star_every = STAR_EVERY
	_next_star = tick + STAR_EVERY * 60
	_star_until = 0
	_next_chest = tick + CHEST_FIRST * 60
	_chest_until = 0
	_spawn_wave()


func event_pool() -> Array:
	return super.event_pool() + ["황금 러시"]


func _apply_event(ev: String) -> void:
	if ev == "황금 러시":
		_star_every = 15
		_next_star = mini(_next_star, tick + 15 * 60)
		return
	super._apply_event(ev)


func _on_reset() -> void:
	coins = []


func _spawn_wave() -> void:
	wave += 1
	coins = []
	var m := map as CoinArenaMap
	for p in m.random_coin_points(_rng, WAVE_COINS, (wave - 1) % 3):
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
		_next_star = tick + _star_every * 60
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
	# 전설 보물상자: 숨은 장소 중 한 곳에 잠깐 (위치는 알려 주지 않음 → 탐험)
	if tick >= _next_chest and left > CHEST_LIFETIME * 60:
		_next_chest = tick + CHEST_EVERY * 60
		_chest_until = tick + CHEST_LIFETIME * 60
		var spots: Array = (map as CoinArenaMap).HIDDEN_SPOTS
		var hp: Vector3 = spots[_rng.randi() % spots.size()]
		coins.append([hp.x, hp.y, hp.z, 1, 10])
		announce("어딘가에 전설 보물상자 등장! (10점, %d초)" % CHEST_LIFETIME)
		dirty = true
	if _chest_until > 0 and tick >= _chest_until:
		_chest_until = 0
		for c in coins:
			if c[4] == 10 and c[3] == 1:
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
				var zone := 2 if c[1] > 3.5 and int(c[4]) < 10 else 1   # 높은 발판 = 보너스 구역
				var pts: int = int(c[4]) * (2 if _bonus else 1) * zone
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
