extends Node
## UI 미리보기 (자동 로드가 필요해서 씬으로 실행): godot --path . res://tools/ui_preview.tscn -- --what=menu|results --out=a.png [--server-url=wss://x]

func _ready() -> void:
	var root := get_tree().root
	await get_tree().process_frame
	UiStyle.apply()
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if a.get("what", "menu") == "menu":
		root.add_child(MainMenu.new())
	else:
		var map := MapRegistry.instantiate("race_course")
		root.add_child(map)
		var cam := Camera3D.new()
		root.add_child(cam)
		await get_tree().process_frame
		cam.look_at_from_position(Vector3(8, 6, -10), Vector3(0, 0, 10))
		var c := GameClient.new()
		c.address = "wss://example/r/K7QP"
		c.nickname = "딸기"
		c.my_id = 2
		c.local_player = PlayerBody.new()
		c.remote_names = {3: "바나나", 4: "민트"}
		c.mode_state = {"phase": "results", "title": "장애물 레이스", "board": ["1. 딸기  완주 0:42", "2. 바나나  완주 0:51", "3. 민트  진행 80%"],
			"results": [{"rank": 1, "peer_id": 2, "nickname": "딸기", "score": "0:42", "xp": 30, "win": true},
				{"rank": 2, "peer_id": 3, "nickname": "바나나", "score": "0:51", "xp": 20},
				{"rank": 3, "peer_id": 4, "nickname": "민트", "score": "80%", "xp": 10}]}
		var hud := Hud.new()
		hud.client = c
		root.add_child(hud)
		hud.set_status("장애물 레이스 코스 입장 완료")
	for f in 70:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(str(a.get("out", "user://ui.png")))
	get_tree().quit()
