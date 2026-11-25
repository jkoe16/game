extends SceneTree
# 임시: 봇이 장애물 코스를 어떻게 지나가는지 기록
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var map: RaceCourseMap = MapRegistry.instantiate("race_course")
	root.add_child(map)
	await process_frame
	var p: PlayerBody = load("res://scenes/player/player.tscn").instantiate()
	p.world = map
	map.add_child(p)
	p.teleport(map.get_start_point(0))
	var cp := 0
	var tk := int(OS.get_environment("TK0")) if OS.get_environment("TK0") != "" else 1000
	var seq := 0
	var stuck := 0
	var falls := {}
	var knocks := {}
	var was_stun := false
	for i in 150 * 60:
		await physics_frame
		tk += 1
		seq += 1
		map.update_world(tk)
		var pos := p.global_position
		var target := map.get_bot_target(pos, {}, 1)
		var inp := PlayerInput.new()
		var to := Vector2(target.x - pos.x, target.z - pos.z)
		if to.length() > 0.6:
			inp.set_move(to.normalized())
		var hs := Vector2(p.velocity.x, p.velocity.z).length()
		stuck = stuck + 1 if (to.length() > 0.6 and hs < 1.5 and p.stun_time <= 0.0) else 0
		inp.jump = stuck > 8 or target.y - pos.y > 0.8 or (seq % 40 == 0 and to.length() >= 1.5)
		var hint := map.bot_hint(pos, Vector3(to.x, 0, to.y).normalized(), tk + 1)
		if hint == 1:
			inp.jump = true
		elif hint == 2:
			inp.set_move(Vector2.ZERO)
			inp.jump = false
			stuck = 0
		p.simulate(inp, 1.0 / 60.0, tk)
		pos = p.global_position
		if p.stun_time > 0.0 and not was_stun:
			var k := int(pos.z / 10) * 10
			knocks[k] = knocks.get(k, 0) + 1
		was_stun = p.stun_time > 0.0
		cp = maxi(cp, map.checkpoint_index_at(pos))
		if pos.y < map.kill_height:
			var k := int(map.checkpoints[cp]["z"])
			falls[k] = falls.get(k, 0) + 1
			p.teleport(map.checkpoint_point(cp, 1))
		if map.is_finished(pos):
			print("FINISH %.1fs falls=%s knocks=%s" % [i / 60.0, falls, knocks])
			quit()
			return
	print("NOFINISH cp=%d z=%.1f falls=%s knocks=%s" % [cp, p.global_position.z, falls, knocks])
	quit()
