class_name MinigameTests
extends RefCounted
## 미니게임 월드/모드 단위 테스트: 모든 맵·모드 생성, 회전 막대 넉백, 이동 발판 탑승, 패드, 결정성.

static var t: Object


static func run(runner: Object) -> void:
	t = runner
	await test_all_maps_and_modes()
	await test_sweeper_knock()
	await test_mover_carry()
	await test_pads()
	await test_world_determinism()
	await test_jump_buffer()
	test_sweeper_speed_cap()
	test_survival_lives()
	test_rekey_keeps_progress()
	test_treasure_rules()
	await test_crumbling_island()
	test_items_and_events()
	await test_shield_and_wind()
	await test_new_hazards()
	test_attack_items()
	test_racing_stages()


## 모드 규칙 단위 테스트용 가짜 서버 (위치 고정, 알림 기록)
class FakeServer extends Node:
	var pos := {}
	var notes: Array = []
	func get_player_pos(id: int) -> Vector3: return pos.get(id, Vector3(0, -100, 0))
	func teleport_player(id: int, p: Vector3) -> void: pos[id] = p
	func notify_player(_id: int, text: String) -> void: notes.append(text)
	var given: Array = []
	func give_item(id: int, kind: String, secs: float) -> void: given.append([id, kind, secs])
	var knocked: Array = []
	func knock_player(id: int, impulse: Vector3, stun: float) -> void: knocked.append([id, impulse, stun])
	func transfer_all(_r: String, _t: String) -> void: pass


## 착지 직전(0.1초 전)에 누른 점프도 착지하자마자 실행된다
static func test_jump_buffer() -> void:
	var map := MapRegistry.instantiate("coin_arena")
	t.root.add_child(map)
	var p := _body(map, Vector3(8, 0.5, -3))  # 가운데 회전 막대가 닿지 않는 곳
	var tk := await _run_ticks(map, [p], 0, 30, func(_i: int) -> PlayerInput: return _inp(0, 0))
	var ground := p.global_position.y
	tk = await _run_ticks(map, [p], tk, 1, func(_i: int) -> PlayerInput: return _inp(0, 0, true))
	# 정점 지나 내려오다 땅에 닿기 직전 점프 입력
	var pressed := false
	var hold_left := -1
	var jumped_again := false
	for i in 120:
		var press := false
		# 착지 직전(0.35m 위)에 누르면 컨트롤러가 그 뒤 JUMP_HOLD_TICKS틱 동안 점프 입력을 유지한다
		if p.velocity.y < 0.0 and p.global_position.y < ground + 0.35:
			pressed = true
		if pressed:
			hold_left = hold_left - 1 if hold_left > 0 else (PlayerBody.JUMP_HOLD_TICKS if hold_left == -1 else 0)
			press = hold_left > 0
		tk = await _run_ticks(map, [p], tk, 1, func(_i: int) -> PlayerInput: return _inp(0, 0, press))
		if pressed and p.velocity.y > 5.0:
			jumped_again = true
			break
	t.check(pressed and jumped_again, "jump pressed just before landing still jumps (buffer)")
	map.queue_free()
	await t.process_frame


## 가속 막대는 최고 속도에서 멈춘다 (끝없이 빨라지지 않음)
static func test_sweeper_speed_cap() -> void:
	var map := GameMap.new()
	map.add_sweeper(Vector3.ZERO, 5.0, 0.5, 55.0, 0.0, 5.0)
	var s: Dictionary = map.sweepers[0]
	var w := (map.sweeper_angle(s, 600 * 60 + 1) - map.sweeper_angle(s, 600 * 60)) * 60.0
	t.check(absf(w - GameMap.MAX_SWEEP_OMEGA) < 0.01, "accelerating sweeper is capped at max speed", "%.3f rad/s" % w)
	var a0 := map.sweeper_angle(s, 1000)
	var a1 := map.sweeper_angle(s, 1001)
	t.check(absf(a1 - a0) < 0.1, "sweeper angle is continuous")
	map.free()


static func test_survival_lives() -> void:
	var map := MapRegistry.instantiate("survival_arena")
	var srv := FakeServer.new()
	var mode := ModeRegistry.create("survival") as SurvivalMode
	mode.setup(srv, map, {"min_players": 2})
	mode.on_player_joined(1, "A")
	mode.on_player_joined(2, "B")
	mode._begin_countdown()
	mode.server_tick(mode.phase_end_tick)
	t.check(mode.phase == "playing", "survival round starts")
	var r1 := mode.on_fell(1)
	t.check(r1 != Vector3.INF and mode.entries[1]["status"] == "playing" and mode.entries[1]["lives"] == 1, "first fall: back on stage with 1 life")
	var r2 := mode.on_fell(1)
	t.check(r2 == Vector3.INF and mode.entries[1]["status"] == "out", "second fall: out")
	mode.server_tick(mode.tick + 1)
	t.check(mode.phase == "results" and mode.last_results[0]["peer_id"] == 2 and mode.last_results[0]["win"], "last survivor wins")
	mode.free()
	map.free()
	srv.free()


## 재접속: 새 연결 번호로 옮겨도 목숨·상태·결과가 그대로 이어진다
static func test_rekey_keeps_progress() -> void:
	var map := MapRegistry.instantiate("survival_arena")
	var srv := FakeServer.new()
	var mode := ModeRegistry.create("survival") as SurvivalMode
	mode.setup(srv, map, {"min_players": 2})
	mode.on_player_joined(1, "A")
	mode.on_player_joined(2, "B")
	mode._begin_countdown()
	mode.server_tick(mode.phase_end_tick)
	mode.on_fell(1)  # 목숨 1개 남음
	mode.on_player_rekeyed(1, 77)
	var e: Dictionary = mode.entries.get(77, {})
	t.check(not mode.entries.has(1) and e.get("peer_id") == 77 and e.get("lives") == 1 and e.get("status") == "playing", "rekey moves entry with lives/status to the new id", str(e))
	t.check(mode.public_state()["players"].has("77") and not mode.public_state()["players"].has("1"), "public state lists the new id only")
	mode.on_fell(2)
	mode.on_fell(2)
	mode.server_tick(mode.tick + 1)
	t.check(mode.phase == "results" and mode.last_results[0]["peer_id"] == 77, "resumed player wins under its new id")
	mode.on_player_rekeyed(77, 78)
	t.check(mode.last_results[0]["peer_id"] == 78, "rekey during results updates the result entry")
	mode.free()
	map.free()
	srv.free()

	var lmap := MapRegistry.instantiate("lobby_plaza")
	var lsrv := FakeServer.new()
	var lobby := ModeRegistry.create("lobby") as LobbyMode
	lobby.setup(lsrv, lmap, {})
	lobby.on_player_joined(5, "L")
	lobby._hold[5] = {"mode": "racing", "ticks": 50}
	lobby.on_player_rekeyed(5, 6)
	t.check(lobby.entries.has(6) and not lobby.entries.has(5) and not lobby._hold.has(5) and not lobby._hold.has(6), "lobby rekey moves entry and resets portal timer")
	lobby.free()
	lmap.free()
	lsrv.free()


static func test_treasure_rules() -> void:
	var map := MapRegistry.instantiate("coin_arena")
	var srv := FakeServer.new()
	var mode := ModeRegistry.create("party") as PartyCoinsMode
	mode.setup(srv, map, {"min_players": 1, "round_sec": 50})
	mode.on_player_joined(1, "A")
	mode._begin_countdown()
	mode.server_tick(mode.phase_end_tick)
	var gems := mode.coins.filter(func(c: Array) -> bool: return c[4] == 3)
	t.check(gems.size() == 2 and mode.coins.size() == 16, "wave has 14 coins + 2 gems on platforms", str(mode.coins.size()))
	srv.pos[1] = Vector3(gems[0][0], gems[0][1] - 0.8, gems[0][2])
	mode.server_tick(mode.tick + 1)
	t.check(mode.entries[1]["score"] == 3, "gem is worth 3 points", str(mode.entries[1]["score"]))
	mode.server_tick(mode.round_start_tick + 30 * 60)
	t.check(mode.coins.any(func(c: Array) -> bool: return c[4] == 5 and c[3] == 1), "golden star appears at 30s")
	srv.pos[1] = Vector3(0, 1.2 - 0.8, 0)
	mode.server_tick(mode.round_start_tick + 31 * 60)  # 남은 19초 = 보너스 타임, 별은 40초까지
	t.check(mode.entries[1]["score"] == 3 + 10, "star in bonus time is worth 5×2", str(mode.entries[1]["score"]))
	mode.free()
	map.free()
	srv.free()


static func _inp(x: float, z: float, jump := false) -> PlayerInput:
	var i := PlayerInput.new()
	i.set_move(Vector2(x, z))
	i.jump = jump
	return i


static func _body(map: GameMap, pos: Vector3) -> PlayerBody:
	var p: PlayerBody = load("res://scenes/player/player.tscn").instantiate()
	p.world = map
	map.add_child(p)
	p.teleport(pos)
	return p


static func _run_ticks(map: GameMap, bodies: Array, start_tick: int, n: int, fn: Callable) -> int:
	var tk := start_tick
	for i in n:
		await t.physics_frame
		tk += 1
		map.update_world(tk)
		for b in bodies:
			b.simulate(fn.call(i), 1.0 / 60.0, tk)
	return tk


static func test_all_maps_and_modes() -> void:
	for mode_id in ModeRegistry.MODES:
		var map := MapRegistry.instantiate(ModeRegistry.map_for(mode_id))
		t.check(map != null, "map for '%s' instantiates" % mode_id)
		if map == null:
			continue
		t.root.add_child(map)
		var mode := ModeRegistry.create(mode_id)
		t.check(mode != null and mode.mode_id() == mode_id, "mode '%s' created" % mode_id)
		t.check(map.spawn_points.size() >= 8, "'%s' has 8 spawn points" % mode_id)
		# 스폰 지점에 서면 바닥에 착지해야 함 (맵 레이아웃 검증)
		var p := _body(map, map.get_start_point(3))
		await _run_ticks(map, [p], 0, 45, func(_i: int) -> PlayerInput: return _inp(0, 0))
		t.check(p.is_on_floor() or p.floor_mover >= 0, "'%s' start point is on solid ground" % mode_id, str(p.global_position))
		if mode:
			mode.free()
		map.queue_free()
		await t.process_frame


static func test_sweeper_knock() -> void:
	var map := MapRegistry.instantiate("race_course")
	t.root.add_child(map)
	# 첫 회전 막대(중심 -3.5,0,40 반지름 4.5)의 원 위에 서서 막대가 오기를 기다린다
	var p := _body(map, Vector3(-3.5, 0.5, 43.0))
	var hit := false
	var tk := 0
	for i in 300:
		await t.physics_frame
		tk += 1
		map.update_world(tk)
		p.simulate(_inp(0, 0), 1.0 / 60.0, tk)
		if p.stun_time > 0.0:
			hit = true
			break
	t.check(hit, "rotating bar knocks a standing player down")
	t.check(hit and p.velocity.y > 0.0 and Vector2(p.velocity.x, p.velocity.z).length() > 5.0, "knockback launches player up and away", str(p.velocity))
	# 넘어진 동안 입력 무시
	var before_stun := p.stun_time
	await _run_ticks(map, [p], tk, 5, func(_i: int) -> PlayerInput: return _inp(1, 0, true))
	t.check(before_stun > 0.5, "stun lasts ~0.7s", str(before_stun))
	map.queue_free()
	await t.process_frame


static func test_mover_carry() -> void:
	var map := MapRegistry.instantiate("race_course")
	t.root.add_child(map)
	map.update_world(0)
	var start := map.mover_pos(0, 0) + Vector3(0, 0.6, 0)
	var p := _body(map, start)
	var tk := await _run_ticks(map, [p], 0, 30, func(_i: int) -> PlayerInput: return _inp(0, 0))
	t.check(p.floor_mover == 0, "player detected standing on moving platform", str(p.floor_mover))
	var rel_before := p.global_position.x - map.mover_pos(0, tk).x
	tk = await _run_ticks(map, [p], tk, 60, func(_i: int) -> PlayerInput: return _inp(0, 0))
	var rel_after := p.global_position.x - map.mover_pos(0, tk).x
	var platform_moved := absf(map.mover_pos(0, tk).x - map.mover_pos(0, tk - 60).x)
	t.check(platform_moved > 1.0 and absf(rel_after - rel_before) < 0.15, "player rides along with moving platform", "platform moved %.2f, relative drift %.3f" % [platform_moved, rel_after - rel_before])
	map.queue_free()
	await t.process_frame


static func test_pads() -> void:
	var map := MapRegistry.instantiate("race_track")
	t.root.add_child(map)
	var p := _body(map, Vector3(-20, 0.5, 3))
	var tk := await _run_ticks(map, [p], 0, 20, func(_i: int) -> PlayerInput: return _inp(0, 0))
	var top := 0.0
	for i in 60:
		tk = await _run_ticks(map, [p], tk, 1, func(_i: int) -> PlayerInput: return _inp(0, 1))
		top = maxf(top, Vector2(p.velocity.x, p.velocity.z).length())
	t.check(top > PlayerBody.WALK_SPEED * 1.4, "boost pad raises top speed", "%.2f" % top)

	var q := _body(map, Vector3(-3, 0.5, 24))
	var max_y := 0.0
	for i in 60:
		tk = await _run_ticks(map, [q], tk, 1, func(_i: int) -> PlayerInput: return _inp(0, 0))
		max_y = maxf(max_y, q.global_position.y)
	t.check(max_y > 2.0, "jump pad launches player higher than a normal jump", "%.2f" % max_y)
	map.queue_free()
	await t.process_frame


## 같은 입력 + 같은 틱이면 장애물이 있어도 서버와 클라이언트 결과가 같아야 한다 (예측 정확성의 근거)
static func test_world_determinism() -> void:
	var results: Array = []
	for run in 2:
		var map := MapRegistry.instantiate("race_course")
		t.root.add_child(map)
		var p := _body(map, Vector3(0, 0.5, 34))
		await _run_ticks(map, [p], 100, 240, func(i: int) -> PlayerInput: return _inp(sin(i * 0.05) * 0.5, 1, i % 35 == 0))
		results.append([p.global_position, p.stun_time])
		map.queue_free()
		await t.process_frame
	t.check((results[0][0] as Vector3).distance_to(results[1][0]) < 0.001, "obstacle course simulation is deterministic", "%s vs %s" % [results[0][0], results[1][0]])



## 무너지는 섬: 시작 전엔 그대로, 30초 뒤 바깥 타일부터 떨어지고, 가운데는 끝까지 남는다. 다음 판엔 복구
static func test_crumbling_island() -> void:
	var map := MapRegistry.instantiate("survival_arena") as SurvivalArenaMap
	t.root.add_child(map)
	await t.process_frame
	var outer := Vector3(sin(TAU * 0.5 / 16) * 9.6, 0, cos(TAU * 0.5 / 16) * 9.6)
	map.update_world(5000)
	t.check(map.is_solid_at(outer) and map.tiles.all(func(x: Dictionary) -> bool: return not x["fallen"]), "island intact before round")
	map.crumble_start = 1000
	map.update_world(1000 + 29 * 60)
	t.check(map.tiles.all(func(x: Dictionary) -> bool: return not x["fallen"]), "nothing falls in first 29s")
	map.update_world(1000 + 120 * 60)
	var fallen := map.tiles.filter(func(x: Dictionary) -> bool: return x["fallen"]).size()
	t.check(fallen == 16 + 6, "all outer tiles and half the inner ring fall by 120s", str(fallen))
	t.check(map.is_solid_at(Vector3(2, 0, 2)) and not map.is_solid_at(Vector3(0, 0, 10)), "core stays, edge is gone")
	# 실제로 무너진 자리에 서면 떨어진다
	var p := _body(map, Vector3(0, 0.5, 9.6))
	await _run_ticks(map, [p], 1000 + 120 * 60, 40, func(_i: int) -> PlayerInput: return _inp(0, 0))
	t.check(p.global_position.y < -1.0, "player falls through a collapsed tile", str(p.global_position))
	map.crumble_start = 0
	map.update_world(9000)
	t.check(map.tiles.all(func(x: Dictionary) -> bool: return not x["fallen"]), "tiles restored for next round")
	map.queue_free()
	await t.process_frame


## 아이템 상자: 먹으면 효과, 일정 시간 뒤 다시 생김. 이벤트가 하나 정해짐
static func test_items_and_events() -> void:
	var map := MapRegistry.instantiate("race_course")
	map._ready()
	var srv := FakeServer.new()
	var mode := ModeRegistry.create("obstacle_race")
	mode.setup(srv, map, {"min_players": 1})
	mode.on_player_joined(1, "A")
	mode._begin_countdown()
	mode.server_tick(mode.phase_end_tick)
	t.check(mode.items.size() == map.item_spawns.size() and mode.items.size() >= 6 and mode.event != "", "round starts with item boxes and a random event", "%d %s" % [mode.items.size(), mode.event])
	t.check(mode.items.all(func(x: Array) -> bool: return GameMode.ITEM_KINDS[x[4]] == "mystery"), "race boxes are mystery boxes")
	var it: Array = mode.items[0]
	srv.pos[1] = Vector3(it[0], it[1] - 0.8, it[2])
	var before := srv.given.size() + srv.knocked.size()
	var notes_before := srv.notes.size()
	mode.server_tick(mode.tick + 1)
	# 혼자면 번개는 안 나오고, 충격파는 맞을 사람이 없어 알림만 뜬다
	t.check(mode.items[0][3] == 0 and srv.notes.size() > notes_before and srv.given.size() + srv.knocked.size() >= before, "touching a box uses an item and removes the box", str(srv.notes))
	srv.pos[1] = Vector3(0, -100, 0)
	mode.server_tick(mode.tick + mode.item_respawn_ticks + 1)
	t.check(mode.items[0][3] == 1, "box comes back later")
	mode.free()
	map.free()
	srv.free()


## 보호막이면 막대에 맞아도 넘어지지 않음 / 돌풍은 밀어내지만 걸어서 버틸 수 있음
static func test_shield_and_wind() -> void:
	var map := MapRegistry.instantiate("survival_arena") as SurvivalArenaMap
	t.root.add_child(map)
	await t.process_frame
	var p := _body(map, Vector3(0, 0.5, 3.0))
	p.shield_time = 5.0
	p.knock(Vector3(10, 5, 0), 0.7)
	t.check(p.stun_time == 0.0 and p.velocity == Vector3.ZERO, "shield blocks knockdown")
	p.shield_time = 0.0
	p.knock(Vector3(10, 5, 0), 0.7)
	t.check(p.stun_time > 0.0, "without shield, knockdown works")
	p.teleport(Vector3(0, 0.5, 3.0))
	map.crumble_start = 1000
	var gust_tick := 1000 + int(SurvivalArenaMap.GUST_FIRST * 60) + 5
	var w := map.gust_at(gust_tick)
	t.check(w.length() > 2.0, "gust blows at 40s", str(w))
	t.check(map.gust_at(gust_tick + 4 * 60) == Vector3.ZERO, "gust stops after 3s")
	p.shield_time = 10.0  # 회전 막대에 맞아 결과가 흔들리지 않게
	var start := p.global_position
	await _run_ticks(map, [p], gust_tick, 60, func(_i: int) -> PlayerInput: return _inp(0, 0))
	var drift := Vector2(p.global_position.x - start.x, p.global_position.z - start.z).length()
	t.check(drift > 1.5, "standing still, the gust pushes you", "%.2f m" % drift)
	p.teleport(Vector3(0, 0.5, 3.0))
	p.shield_time = 10.0
	var against := -w.normalized()
	await _run_ticks(map, [p], gust_tick, 60, func(_i: int) -> PlayerInput: return _inp(against.x, against.z))
	var moved := Vector2(p.global_position.x, p.global_position.z - 3.0).dot(Vector2(against.x, against.z))
	t.check(moved > 0.5, "walking against the gust still makes progress", "%.2f m" % moved)
	map.queue_free()
	await t.process_frame


## 새 장애물: 굴러오는 공·튀어나오는 벽은 맞으면 넘어지고, 사라지는 발판은 사라지면 떨어진다
static func test_new_hazards() -> void:
	var map := MapRegistry.instantiate("race_course")
	t.root.add_child(map)
	await t.process_frame
	# 공이 굴러오는 길(x=0) 위에 서서 기다리면 맞는다
	var p := _body(map, Vector3(0, 0.5, 25))
	var hit := false
	var tk := 0
	for i in 400:
		tk = await _run_ticks(map, [p], tk, 1, func(_i: int) -> PlayerInput: return _inp(0, 0))
		if p.stun_time > 0.0:
			hit = true
			break
	t.check(hit and p.velocity.z < 0.0, "rolling ball knocks a standing player back", str(p.velocity))
	# 쉬운 길(다리) 위 주먹 벽 앞에 서 있으면 다리 밖(-x)으로 밀린다
	var q := _body(map, Vector3(6.5, 0.5, 62))
	hit = false
	for i in 400:
		tk = await _run_ticks(map, [q], tk, 1, func(_i: int) -> PlayerInput: return _inp(0, 0))
		if q.stun_time > 0.0:
			hit = true
			break
	t.check(hit and q.velocity.x < -5.0, "pusher wall shoves player off the bridge", str(q.velocity))
	# 사라지는 발판
	var bl: Dictionary = map.blinkers[0]
	var solid_tick := -1
	var gone_tick := -1
	for k in 400:
		if solid_tick < 0 and map.blinker_solid(bl, k) and map.blinker_solid(bl, k + 60):
			solid_tick = k
		if solid_tick >= 0 and k > solid_tick and not map.blinker_solid(bl, k):
			gone_tick = k
			break
	var pos: Vector3 = (bl["body"] as Node3D).position + Vector3(0, 1.0, 0)
	var r := _body(map, pos)
	await _run_ticks(map, [r], solid_tick, 30, func(_i: int) -> PlayerInput: return _inp(0, 0))
	t.check(r.global_position.y > -0.2, "standing on a solid blink tile is fine", str(r.global_position))
	r.teleport(pos)
	await _run_ticks(map, [r], gone_tick, 40, func(_i: int) -> PlayerInput: return _inp(0, 0))
	t.check(r.global_position.y < -1.0, "blink tile vanishes and player falls", str(r.global_position))
	# 결정성: 같은 입력이면 공·벽·발판이 있어도 결과가 같다
	var res: Array = []
	for run in 2:
		var b := _body(map, Vector3(0, 0.5, 78))
		await _run_ticks(map, [b], 500, 200, func(i: int) -> PlayerInput: return _inp(sin(i * 0.07) * 0.4, 1, i % 30 == 0))
		res.append(b.global_position)
		b.queue_free()
	t.check((res[0] as Vector3).distance_to(res[1]) < 0.001, "blink tiles are deterministic", "%s vs %s" % res)
	map.queue_free()
	await t.process_frame


## 번개(앞사람 모두 감전)·충격파(주변 밀어내기)·물음표 상자의 순위별 확률
static func test_attack_items() -> void:
	var map := MapRegistry.instantiate("race_course")
	map._ready()
	var srv := FakeServer.new()
	var mode := ModeRegistry.create("obstacle_race")
	mode.setup(srv, map, {"min_players": 1})
	for i in 4:
		mode.on_player_joined(i + 1, "P%d" % (i + 1))
	mode._begin_countdown()
	mode.server_tick(mode.phase_end_tick)
	# 진행도: 1이 1등, 4가 꼴찌
	for i in 4:
		mode.entries[i + 1]["progress"] = 0.8 - i * 0.2
		srv.pos[i + 1] = Vector3(i * 2.0, 0, 50)
	var ranked: Array = mode._ranked()
	mode._use_bolt(ranked, mode.entries[4])
	var ids := srv.knocked.map(func(k: Array) -> int: return k[0])
	t.check(ids.size() == 3 and not ids.has(4), "bolt from last place stuns everyone ahead", str(ids))
	srv.knocked.clear()
	mode._use_bolt(ranked, mode.entries[1])
	t.check(srv.knocked.is_empty(), "bolt from the leader hits no one")
	srv.pos[1] = Vector3(0, 0, 50)
	srv.pos[2] = Vector3(3, 0, 50)
	srv.pos[3] = Vector3(20, 0, 50)
	srv.pos[4] = Vector3(0, 0, 53)
	srv.knocked.clear()
	mode._use_shock(mode.entries[1])
	ids = srv.knocked.map(func(k: Array) -> int: return k[0])
	t.check(ids.size() == 2 and ids.has(2) and ids.has(4), "shock knocks only nearby players", str(ids))
	t.check(srv.knocked.size() > 0 and (srv.knocked[0][1] as Vector3).x > 5.0, "shock pushes away from the user", str(srv.knocked))
	var lead_bolts := 0
	var last_bolts := 0
	for i in 400:
		if mode._mystery_kind(ranked, mode.entries[1]) == "bolt":
			lead_bolts += 1
		if mode._mystery_kind(ranked, mode.entries[4]) == "bolt":
			last_bolts += 1
	t.check(lead_bolts == 0 and last_bolts > 120, "leader never rolls a bolt, last place often does", "%d / %d" % [lead_bolts, last_bolts])
	mode.free()
	map.free()
	srv.free()


## 레이싱: 공·벽은 정해진 시간 전엔 없고, 그 뒤에 나타난다. 지름길 다리 위에 설 수 있다
static func test_racing_stages() -> void:
	var map := MapRegistry.instantiate("race_track") as RaceTrackMap
	map._ready()
	map.round_start_tick = 1000
	var r: Dictionary = map.rollers[0]
	var w: Dictionary = map.pushers[0]
	t.check(not map.hazard_active(r["from"], 1000 + 10 * 60) and map.hazard_active(r["from"], 1000 + 31 * 60), "rollers appear after 30s")
	t.check(not map.hazard_active(w["from"], 1000 + 50 * 60) and map.hazard_active(w["from"], 1000 + 61 * 60), "pusher walls appear after 60s")
	var early := false
	for k in 300:
		if map.roller_hit(r, map.roller_pos(r, 1000 + k), 1000 + k) != Vector3.ZERO:
			early = true
	t.check(not early, "inactive roller never hits")
	map.free()
