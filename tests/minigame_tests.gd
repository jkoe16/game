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
	var p := _body(map, Vector3(-16, 0.5, 3))
	var tk := await _run_ticks(map, [p], 0, 20, func(_i: int) -> PlayerInput: return _inp(0, 0))
	var top := 0.0
	for i in 60:
		tk = await _run_ticks(map, [p], tk, 1, func(_i: int) -> PlayerInput: return _inp(0, 1))
		top = maxf(top, Vector2(p.velocity.x, p.velocity.z).length())
	t.check(top > PlayerBody.WALK_SPEED * 1.4, "boost pad raises top speed", "%.2f" % top)

	var q := _body(map, Vector3(-5, 0.5, 31))
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

