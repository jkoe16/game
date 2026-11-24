class_name GameMode
extends Node
## 모든 게임 모드의 공통 기반 (서버 전용 규칙 실행). 클라이언트는 public_state()를 받아 표시만 한다.
##
## 라운드 흐름: waiting(인원 모으기) → countdown(출발선 정렬, 이동 금지) → playing → results → (로비 복귀 | 다시 waiting)
## 새 모드 추가 = 이 클래스를 상속해 아래 "모드별 재정의" 함수들만 구현 + 맵 씬 + ModeRegistry 등록.

signal round_finished(results: Array)

var server: Node          # GameServer
var map: GameMap
var phase := "waiting"
var phase_end_tick := 0
var round_start_tick := 0
var tick := 0
var dirty := true
## peer_id -> {peer_id, nickname, status: waiting|playing|finished|out|late, score, ...모드별}
var entries := {}
var last_results: Array = []

# 시간 설정 (틱). 실행 인자로 조정 가능 (테스트용 단축)
var min_players := 2
var waiting_ticks := 10 * 60
var countdown_ticks := 3 * 60
var round_ticks := 90 * 60
var results_ticks := 8 * 60
## 결과 후 로비로 돌려보낼 주소 ("" 이면 이 서버에서 다음 라운드 대기)
var lobby_route := ""

# ---- 공통 재미 요소: 아이템 상자 + 판마다 랜덤 이벤트
const ITEM_KINDS := ["speed", "jump", "shield"]
const ITEM_NAMES := {"speed": "속도 UP", "jump": "점프 강화", "shield": "보호막"}
const ITEM_PICK_RADIUS := 1.4
## [[x, y, z, alive(0/1), kind_index], ...] (맵의 item_spawns 위치)
var items: Array = []
var _item_back := {}   # 아이템 번호 → 다시 나타날 틱
var item_respawn_ticks := 8 * 60
## 이번 판 랜덤 이벤트 이름 ("" = 없음)
var event := ""
var _rng_round := RandomNumberGenerator.new()


func setup(p_server: Node, p_map: GameMap, cfg: Dictionary) -> void:
	server = p_server
	map = p_map
	min_players = int(cfg.get("min_players", min_players))
	waiting_ticks = int(float(cfg.get("wait_sec", waiting_ticks / 60.0)) * 60)
	countdown_ticks = int(float(cfg.get("countdown_sec", countdown_ticks / 60.0)) * 60)
	round_ticks = int(float(cfg.get("round_sec", round_ticks / 60.0)) * 60)
	results_ticks = int(float(cfg.get("results_sec", results_ticks / 60.0)) * 60)
	lobby_route = str(cfg.get("lobby", ""))


# ================================================================== 모드별 재정의

func mode_id() -> String:
	return ""

func title() -> String:
	return ""

func rules_text() -> String:
	return ""

func is_lobby() -> bool:
	return false

## 라운드 시작 순간 (playing 진입)
func _on_round_start() -> void:
	pass

## playing 중 매 틱
func _mode_tick() -> void:
	pass

## 조기 종료 조건
func _is_over() -> bool:
	return false

## 순위순(1등 먼저) 엔트리 목록
func _ranked() -> Array:
	return entries.values()

func _score_text(_e: Dictionary) -> String:
	return ""

func _is_win(_e: Dictionary, rank: int) -> bool:
	return rank == 1

## 모드 고유 공개 상태 (문, 코인 등)
func _extra_state() -> Dictionary:
	return {}

## 이 모드에서 나올 수 있는 랜덤 이벤트 (모드가 늘릴 수 있음)
func event_pool() -> Array:
	return ["아이템 폭풍", "부스트 출발", "보호막 출발"]

## 이벤트 시작 효과 (모드 고유 이벤트는 재정의해서 처리)
func _apply_event(ev: String) -> void:
	match ev:
		"아이템 폭풍":
			item_respawn_ticks = 3 * 60
		"부스트 출발":
			for e in playing_entries():
				server.give_item(e["peer_id"], "speed", 3.0)
		"보호막 출발":
			for e in playing_entries():
				server.give_item(e["peer_id"], "shield", 6.0)

const EVENT_TEXT := {
	"아이템 폭풍": "아이템 상자가 3초마다 다시 생겨요",
	"부스트 출발": "모두 속도 UP으로 출발!",
	"보호막 출발": "모두 6초 보호막으로 출발!",
	"황금 러시": "황금 별이 15초마다 나타나요!",
}

## 낙하 시 처리: 리스폰 위치 반환. Vector3.INF = 탈락(관전석으로)
func on_fell(_peer_id: int) -> Vector3:
	return map.get_spawn_point(0)

func _on_reset() -> void:
	pass


# ================================================================== 공통 흐름

## 모든 참가자 화면 가운데 위에 알림 (HUD가 "!"로 시작하는 알림을 크게 띄운다)
func announce(text: String) -> void:
	for e in entries.values():
		server.notify_player(e["peer_id"], "!" + text)


## 첫 완주자가 나오면 남은 시간을 secs초로 줄인다 (나머지가 오래 기다리지 않게)
func start_finish_timer(secs: int) -> void:
	var end := tick + secs * 60
	if end < phase_end_tick:
		phase_end_tick = end
		dirty = true
		announce("첫 완주! %d초 안에 들어오세요" % secs)

func on_player_joined(peer_id: int, nickname: String) -> Vector3:
	var late := phase in ["playing", "results"] or (phase == "countdown")
	entries[peer_id] = {"peer_id": peer_id, "nickname": nickname, "status": "late" if late else "waiting", "score": 0}
	_init_entry(entries[peer_id])
	dirty = true
	return spectator_point() if late else map.get_spawn_point(entries.size() - 1)


func _init_entry(_e: Dictionary) -> void:
	pass


func on_player_left(peer_id: int) -> void:
	entries.erase(peer_id)
	dirty = true


func is_frozen(peer_id: int) -> bool:
	if phase == "countdown":
		return true
	var e: Dictionary = entries.get(peer_id, {})
	return e.get("status") == "finished"


func is_out(peer_id: int) -> bool:
	var st: String = entries.get(peer_id, {}).get("status", "")
	return st == "out" or st == "late"


func spectator_point() -> Vector3:
	return map.get_spawn_point(0) + Vector3(0, 0, 0)


func playing_entries() -> Array:
	return entries.values().filter(func(e: Dictionary) -> bool: return e["status"] in ["playing", "finished", "out"])


func server_tick(t: int) -> void:
	tick = t
	match phase:
		"waiting":
			var n := entries.size()
			if n >= min_players:
				if phase_end_tick == 0:
					phase_end_tick = t + waiting_ticks
					dirty = true
				elif t >= phase_end_tick:
					_begin_countdown()
			elif phase_end_tick != 0:
				phase_end_tick = 0
				dirty = true
		"countdown":
			if t >= phase_end_tick:
				phase = "playing"
				round_start_tick = t
				phase_end_tick = t + round_ticks
				_on_round_start()
				_start_extras()
				dirty = true
		"playing":
			_items_tick()
			_mode_tick()
			if _is_over() or t >= phase_end_tick:
				_end_round()
		"results":
			if t >= phase_end_tick:
				_after_results()


## 라운드 시작: 아이템 상자 배치 + 랜덤 이벤트 하나
func _start_extras() -> void:
	_rng_round.seed = Time.get_ticks_usec() ^ hash(mode_id())
	item_respawn_ticks = 8 * 60
	items = []
	_item_back = {}
	for i in map.item_spawns.size():
		var p: Vector3 = map.item_spawns[i]
		items.append([p.x, p.y, p.z, 1, _rng_round.randi() % ITEM_KINDS.size()])
	var pool := event_pool()
	event = pool[_rng_round.randi() % pool.size()] if not pool.is_empty() else ""
	if event != "":
		_apply_event(event)
		announce("이번 판 이벤트: %s! %s" % [event, EVENT_TEXT.get(event, "")])


func _items_tick() -> void:
	for i in items.size():
		var it: Array = items[i]
		if it[3] == 0:
			if tick >= int(_item_back.get(i, 0)):
				it[3] = 1
				it[4] = _rng_round.randi() % ITEM_KINDS.size()
				dirty = true
			continue
		var ip := Vector3(it[0], it[1], it[2])
		for e in entries.values():
			if e["status"] != "playing":
				continue
			var pos: Vector3 = server.get_player_pos(e["peer_id"]) + Vector3(0, 0.8, 0)
			if pos.distance_to(ip) <= ITEM_PICK_RADIUS:
				it[3] = 0
				_item_back[i] = tick + item_respawn_ticks
				var kind: String = ITEM_KINDS[it[4]]
				# 역전 기회: 뒤처진 절반은 효과가 1.5배 길다
				var ranked := _ranked()
				var behind := ranked.size() >= 2 and ranked.find(e) >= ranked.size() / 2
				var secs: float = {"speed": 3.0, "jump": 6.0, "shield": 6.0}[kind] * (1.5 if behind else 1.0)
				server.give_item(e["peer_id"], kind, secs)
				server.notify_player(e["peer_id"], "!%s%s" % [ITEM_NAMES[kind], " (역전 찬스 1.5배!)" if behind else ""])
				dirty = true
				break


func _begin_countdown() -> void:
	phase = "countdown"
	phase_end_tick = tick + countdown_ticks
	# 라운드 시작 틱을 카운트다운 시작 때 미리 공개 → 클라이언트가 가속 장애물을 처음부터 정확히 예측
	round_start_tick = phase_end_tick
	var i := 0
	for e in entries.values():
		e["status"] = "playing"
		e["score"] = 0
		_init_entry(e)
		server.teleport_player(e["peer_id"], map.get_start_point(i))
		i += 1
	dirty = true


func _end_round() -> void:
	var ranked := _ranked().filter(func(e: Dictionary) -> bool: return e["status"] != "late")
	var results: Array = []
	var n := ranked.size()
	for i in n:
		var e: Dictionary = ranked[i]
		var rank := i + 1
		var win := _is_win(e, rank)
		results.append({
			"peer_id": e["peer_id"], "nickname": e["nickname"], "rank": rank,
			"score": _score_text(e), "win": win, "xp": _xp_for(rank, n, win),
		})
	last_results = results
	phase = "results"
	phase_end_tick = tick + results_ticks
	dirty = true
	round_finished.emit(results)


## 참여만 해도 20, 순위 보너스, 승리 보너스 (꼴찌도 참여 보상의 대부분을 받는다)
func _xp_for(rank: int, n: int, win: bool) -> int:
	return 20 + (n - rank) * 5 + (30 if win else 0)


func _after_results() -> void:
	if lobby_route != "":
		server.transfer_all(lobby_route, "round_over")
	phase = "waiting"
	phase_end_tick = 0
	items = []
	event = ""
	for e in entries.values():
		e["status"] = "waiting"
		e["score"] = 0
	_on_reset()
	dirty = true


func public_state() -> Dictionary:
	var plist := {}
	for e in entries.values():
		var pub := {}
		for k in e:
			if typeof(e[k]) in [TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_BOOL]:
				pub[k] = e[k]
		plist[str(e["peer_id"])] = pub
	return {
		"mode": mode_id(), "title": title(), "rules": rules_text(), "phase": phase,
		"phase_end_tick": phase_end_tick, "round_start_tick": round_start_tick, "tick": tick,
		"min_players": min_players, "board": _board_lines(), "players": plist,
		"results": last_results if phase == "results" else [], "extra": _extra_with_items(),
	}


func _extra_with_items() -> Dictionary:
	var x := _extra_state()
	x["items"] = items
	x["event"] = event
	return x


func _board_lines() -> Array:
	var lines: Array = []
	var i := 1
	for e in _ranked():
		if e["status"] == "late":
			continue
		lines.append("%d. %s  %s" % [i, e["nickname"], _score_text(e)])
		i += 1
	return lines
