extends SceneTree
## 단위/물리 테스트 러너.
## 실행: godot --headless --path . -s res://tests/run_tests.gd
## 실패가 하나라도 있으면 종료 코드 1.

var passed := 0
var failed := 0


func _initialize() -> void:
	_run.call_deferred()


func check(cond: bool, label: String, detail := "") -> void:
	if cond:
		passed += 1
		print("  PASS  " + label)
	else:
		failed += 1
		print("  FAIL  " + label + ("  -- " + detail if detail != "" else ""))


func _run() -> void:
	print("== unit tests ==")
	test_input_quantize()
	test_input_codec()
	test_snapshot_codec()
	test_nickname()
	test_appearance()
	test_args()
	test_matchmaking()
	print("== physics tests ==")
	await test_movement()
	await test_prediction_determinism()
	await test_lobby_map_and_respawn()
	print("== auth tests ==")
	await AuthTests.run(self)
	print("== minigame tests ==")
	await MinigameTests.run(self)
	print("== visual build test ==")
	test_visual_build()
	print("RESULT passed=%d failed=%d" % [passed, failed])
	quit(1 if failed > 0 else 0)


func test_input_quantize() -> void:
	var i := PlayerInput.new()
	i.set_move(Vector2(5, 5))
	check(i.get_move().length() <= 1.0001, "set_move clamps length to 1")
	i.move_x = 127
	i.move_z = 127
	check(i.get_move().length() <= 1.0001, "forged (127,127) clamped by get_move", str(i.get_move().length()))
	i.set_move(Vector2(0.3, -0.7))
	var j := PlayerInput.new()
	j.move_x = i.move_x
	j.move_z = i.move_z
	check(i.get_move() == j.get_move(), "quantized move identical on both ends")


func test_input_codec() -> void:
	var a := PlayerInput.new()
	a.seq = 41
	a.set_move(Vector2(1, 0))
	a.jump = true
	var b := PlayerInput.new()
	b.seq = 40
	b.set_move(Vector2(-0.5, 0.5))
	var out := InputCodec.decode(InputCodec.encode([a, b]))
	check(out.size() == 2, "input codec roundtrip count")
	check(out.size() == 2 and out[0].seq == 40 and out[1].seq == 41, "decoded inputs sorted by seq")
	check(out.size() == 2 and out[1].jump and not out[0].jump, "jump flag preserved")
	check(out.size() == 2 and out[1].move_x == a.move_x and out[0].move_z == b.move_z, "move preserved")
	check(InputCodec.decode(PackedByteArray()).is_empty(), "empty packet rejected")
	check(InputCodec.decode(PackedByteArray([255, 1, 2, 3])).is_empty(), "bad count rejected")
	var trunc := InputCodec.encode([a])
	trunc.resize(trunc.size() - 1)
	check(InputCodec.decode(trunc).is_empty(), "truncated packet rejected")
	var badflags := InputCodec.encode([a])
	badflags[7] = 0xF0
	check(InputCodec.decode(badflags).is_empty(), "unknown flags rejected")


func test_snapshot_codec() -> void:
	var e := {"id": 12345, "pos": Vector3(1.5, 2, -3), "vel": Vector3(0, -9.5, 4), "yaw": 1.25, "air": 0.5, "flags": 1, "ack": 777}
	var bytes := SnapshotCodec.encode(99, [e, e])
	check(bytes.size() == SnapshotCodec.HEADER_BYTES + 2 * SnapshotCodec.BYTES_PER_PLAYER, "snapshot size", str(bytes.size()))
	var d := SnapshotCodec.decode(bytes)
	check(not d.is_empty() and d["tick"] == 99 and d["players"].size() == 2, "snapshot roundtrip header")
	if not d.is_empty():
		var p: Dictionary = d["players"][0]
		check(p["id"] == 12345 and p["ack"] == 777 and p["flags"] == 1, "snapshot ints")
		check((p["pos"] as Vector3).is_equal_approx(e["pos"]) and is_equal_approx(p["yaw"], 1.25), "snapshot floats")
	bytes.resize(bytes.size() - 3)
	check(SnapshotCodec.decode(bytes).is_empty(), "truncated snapshot rejected")


func test_nickname() -> void:
	check(Validation.sanitize_nickname("파티왕_01") == "파티왕_01", "korean nickname accepted")
	check(Validation.sanitize_nickname("  Bob  ") == "Bob", "nickname trimmed")
	check(Validation.sanitize_nickname("a") == "", "too short rejected")
	check(Validation.sanitize_nickname("x".repeat(17)) == "", "too long rejected")
	check(Validation.sanitize_nickname("<script>") == "", "symbols rejected")
	check(Validation.sanitize_nickname("ㅋㅋㅋ") == "", "jamo-only rejected")
	check(Validation.sanitize_nickname(123) == "", "non-string rejected")


func test_appearance() -> void:
	check(Appearance.sanitize({"color": 3, "hat": 2}) == {"color": 3, "hat": 2}, "valid appearance kept")
	check(Appearance.sanitize({"color": 999, "hat": -1}) == Appearance.default_appearance(), "out of range reset")
	check(Appearance.sanitize({"color": "3"}) == Appearance.default_appearance(), "wrong type reset")
	check(Appearance.sanitize(null) == Appearance.default_appearance(), "null reset")


func test_matchmaking() -> void:
	check(Matchmaking.http_base("wss://game.example.com/r/K7QP/racing") == "https://game.example.com", "matchmaking: wss → https base")
	check(Matchmaking.http_base("ws://127.0.0.1:8080/") == "http://127.0.0.1:8080", "matchmaking: ws → http base keeps port")
	check(Matchmaking.http_base("192.168.0.5:7777") == "", "matchmaking: no API for direct (ENet) address")
	var srv := "wss://game.example.com"
	check(Matchmaking.quick_match_target(srv, {"ok": true, "path": "/p/2"}) == srv + "/p/2", "quick match → plaza 2 url")
	check(Matchmaking.quick_match_target(srv, {"ok": true, "path": "/"}) == srv, "quick match → main plaza url")
	check(Matchmaking.quick_match_target(srv, {"ok": false}) == srv, "quick match: no answer → main plaza")
	check(Matchmaking.quick_match_target(srv, {"ok": true, "path": "/r/HACK"}) == srv, "quick match: ignores non-plaza paths")
	check(Matchmaking.join_problem({"ok": true, "exists": false}, "K7QP").contains("찾을 수 없어요"), "join: missing room explained")
	check(Matchmaking.join_problem({"ok": true, "exists": true, "full": true, "max_players": 24}, "K7QP").contains("꽉 찼어요"), "join: full room explained")
	check(Matchmaking.join_problem({"ok": true, "exists": true, "full": false}, "K7QP") == "", "join: open room allowed")
	check(Matchmaking.join_problem({"ok": false}, "K7QP") == "", "join: server asleep → try connecting anyway")


func test_args() -> void:
	var main_script: GDScript = load("res://scripts/main/main.gd")
	var a: Dictionary = main_script.parse_args(PackedStringArray(["--server", "--port=9000", "x", "--connect=1.2.3.4:5"]))
	check(a.get("server") == true and a.get("port") == "9000" and a.get("connect") == "1.2.3.4:5", "cmdline parsing")


# ------------------------------------------------------------------ 물리

func _make_floor(parent: Node3D) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	cs.shape = shape
	sb.add_child(cs)
	sb.position = Vector3(0, -0.5, 0)
	parent.add_child(sb)


func _spawn_body(parent: Node3D, pos: Vector3) -> PlayerBody:
	var p: PlayerBody = load("res://scenes/player/player.tscn").instantiate()
	parent.add_child(p)
	p.global_position = pos
	return p


func _inp(x: float, z: float, jump := false) -> PlayerInput:
	var i := PlayerInput.new()
	i.set_move(Vector2(x, z))
	i.jump = jump
	return i


func _ticks(n: int, bodies: Array, input_fn: Callable) -> void:
	var dt := 1.0 / Engine.physics_ticks_per_second
	for t in n:
		await physics_frame
		for b in bodies:
			b.simulate(input_fn.call(t), dt)


func test_movement() -> void:
	var world := Node3D.new()
	root.add_child(world)
	_make_floor(world)
	var p := _spawn_body(world, Vector3(0, 2, 0))
	await physics_frame
	await _ticks(60, [p], func(_t: int) -> PlayerInput: return _inp(0, 0))
	check(p.is_on_floor() and absf(p.global_position.y) < 0.05, "falls and lands on floor", str(p.global_position))

	var start := p.global_position
	await _ticks(60, [p], func(_t: int) -> PlayerInput: return _inp(0, 1))
	var dist := p.global_position.distance_to(start)
	check(dist > 5.5 and dist < PlayerBody.WALK_SPEED + 0.01, "walks ~6m in 1s", str(dist))

	var max_h := 0.0
	var base_y := p.global_position.y
	var dt := 1.0 / Engine.physics_ticks_per_second
	for t in 90:
		await physics_frame
		p.simulate(_inp(0, 0, t == 0 or t == 20), dt)  # t=20: 공중에서 다시 점프 시도
		max_h = maxf(max_h, p.global_position.y - base_y)
	var expected := PlayerBody.JUMP_VELOCITY * PlayerBody.JUMP_VELOCITY / (2.0 * PlayerBody.GRAVITY)
	check(absf(max_h - expected) < 0.2, "jump height ≈ %.2f m (no double jump)" % expected, str(max_h))
	check(p.is_on_floor(), "lands after jump")

	var fastest := 0.0
	for t in 60:
		var before := p.global_position
		await physics_frame
		var forged := PlayerInput.new()
		forged.move_x = 127
		forged.move_z = 127
		p.simulate(forged, dt)
		fastest = maxf(fastest, Vector2(p.global_position.x - before.x, p.global_position.z - before.z).length() / dt)
	check(fastest <= PlayerBody.WALK_SPEED + 0.05, "forged diagonal input cannot exceed walk speed", str(fastest))
	world.queue_free()
	await process_frame


func test_prediction_determinism() -> void:
	var world := Node3D.new()
	root.add_child(world)
	_make_floor(world)
	var a := _spawn_body(world, Vector3(-20, 0.5, 0))
	var b := _spawn_body(world, Vector3(20, 0.5, 0))
	await physics_frame
	var script_fn := func(t: int) -> PlayerInput:
		return _inp(sin(t * 0.05), cos(t * 0.03), t % 40 == 5)
	await _ticks(240, [a, b], script_fn)
	var da := a.global_position - Vector3(-20, 0, 0)
	var db := b.global_position - Vector3(20, 0, 0)
	check(da.distance_to(db) < 0.001, "same inputs → same result (prediction == server)", str(da.distance_to(db)))
	world.queue_free()
	await process_frame


func test_lobby_map_and_respawn() -> void:
	var map := MapRegistry.instantiate("lobby_plaza")
	check(map != null, "lobby map instantiates")
	if map == null:
		return
	root.add_child(map)
	check(map.spawn_points.size() >= 8, "lobby has >= 8 spawn points")
	var p := _spawn_body(map, map.get_spawn_point(0))
	await physics_frame
	await _ticks(60, [p], func(_t: int) -> PlayerInput: return _inp(0, 0))
	check(p.is_on_floor(), "player stands on lobby ground", str(p.global_position))

	# 경사로 오르기: 경사로 앞에서 -Z 방향으로 이동
	p.teleport(Vector3(12, 0.5, -1.5))
	await _ticks(130, [p], func(_t: int) -> PlayerInput: return _inp(0, -1))
	check(p.global_position.y > 3.0, "climbs 20° ramp onto lookout", str(p.global_position))

	# 계단 오르기
	p.teleport(Vector3(-12, 0.5, -4.5))
	await _ticks(92, [p], func(_t: int) -> PlayerInput: return _inp(0, -1))
	check(p.global_position.y > 1.4, "climbs 0.2m stairs", str(p.global_position))

	# 높은 턱(분수대 가장자리 1.0m)은 자동으로 오르면 안 됨 (점프 필요)
	p.teleport(Vector3(0, 0.5, 6))
	await _ticks(60, [p], func(_t: int) -> PlayerInput: return _inp(0, -1))
	check(p.global_position.y < 0.3, "1.0m ledge is not auto-stepped", str(p.global_position))
	await _ticks(40, [p], func(t: int) -> PlayerInput: return _inp(0, -1, t == 0))
	check(p.global_position.y > 0.9, "1.0m ledge reachable by jumping", str(p.global_position))

	# 섬 밖으로 걸어나가 낙하 → kill_height 아래로 떨어지는지
	p.teleport(Vector3(0, 0.5, 20))
	var fell := false
	for t in 300:
		await physics_frame
		p.simulate(_inp(0, 1), 1.0 / 60.0)
		if p.global_position.y < map.kill_height:
			fell = true
			break
	check(fell, "walking off the island falls below kill height")
	p.teleport(map.get_spawn_point(0))
	check(p.global_position.distance_to(map.get_spawn_point(0)) < 0.01, "respawn teleport")
	map.queue_free()
	await process_frame


func test_visual_build() -> void:
	for hat in Appearance.HATS.size():
		var v := CharacterVisual.new()
		v.build({"color": hat % Appearance.BODY_COLORS.size(), "hat": hat})
		root.add_child(v)
		check(v.anim_tree != null and v.anim_tree.tree_root != null, "visual builds with hat '%s'" % Appearance.HATS[hat])
		var lib := v.anim_player.get_animation_library("")
		var ok := true
		for n in ["idle", "walk", "run", "jump", "fall", "land", "wave", "dance", "victory", "defeat", "knockdown"]:
			ok = ok and lib.has_animation(n)
		check(ok, "all 11 animations present")
		v.update_motion(Vector3(6, 0, 0), true, 0.016)
		v.update_motion(Vector3(0, 5, 0), false, 0.2)
		v.play_emote("dance")
		v.queue_free()
