extends SceneTree
## 맵 미리보기 스크린샷: godot --path . -s res://tools/map_shot.gd -- --map=lobby_plaza --cam=0,8,30 --look=0,2,15 --out=a.png [--chars]

func _initialize() -> void:
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var map := MapRegistry.instantiate(str(a.get("map", "lobby_plaza")))
	root.add_child(map)
	await process_frame
	if a.has("chars"):
		for i in 6:
			var v := CharacterVisual.new()
			map.add_child(v)
			v.build({"color": (i * 5) % Appearance.BODY_COLORS.size(), "hat": i % Appearance.HATS.size()})
			v.position = map.get_spawn_point(i) + Vector3(0, -0.5, 0)
	var cam := Camera3D.new()
	cam.fov = float(a.get("fov", "60"))
	root.add_child(cam)
	var c := str(a.get("cam", "0,10,30")).split_floats(",")
	var l := str(a.get("look", "0,0,0")).split_floats(",")
	cam.look_at_from_position(Vector3(c[0], c[1], c[2]), Vector3(l[0], l[1], l[2]))
	cam.current = true
	for f in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	print("STATS draw_calls=%d objects=%d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	root.get_viewport().get_texture().get_image().save_png(str(a.get("out", "user://shot.png")))
	quit()
