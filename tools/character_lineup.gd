extends SceneTree
## 캐릭터 외형 미리보기: 모든 모자 × 색 몇 가지를 한 줄로 세워 PNG로 저장.
## godot --path . -s res://tools/character_lineup.gd -- --out=lineup.png [--closeup]

func _initialize() -> void:
	var out := "user://lineup.png"
	var closeup := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--closeup":
			closeup = true
	var root3d := Node3D.new()
	root.add_child(root3d)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.82, 1.0)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	root3d.add_child(sun)
	var n := Appearance.HATS.size()
	for i in n:
		var v := CharacterVisual.new()
		root3d.add_child(v)
		v.build({"color": (i * 3 + 1) % Appearance.BODY_COLORS.size() if not closeup else [0, 8, 9, 10, 11, 4, 3, 2][i % 8], "hat": i})
		v.position = Vector3((i - (n - 1) / 2.0) * 1.25, 0, 0)
	var cam := Camera3D.new()
	root3d.add_child(cam)
	await process_frame
	cam.fov = 30 if not closeup else 22
	if closeup:
		# 확대: 뒤쪽 4명 (새로 추가된 모자들)
		var cx := ((n - 2.5) - (n - 1) / 2.0) * 1.25
		cam.look_at_from_position(Vector3(cx, 1.2, 7.0), Vector3(cx, 1.0, 0))
	else:
		cam.look_at_from_position(Vector3(0, 1.3, 12.0), Vector3(0, 0.85, 0))
	for f in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
