class_name GameClient
extends Node
## 게임 클라이언트: 서버 접속, 맵/플레이어 생성, 스냅샷 적용, 로컬 예측 및 원격 보간 관리.
## offline=true 이면 서버 없이 연습 모드로 같은 맵/이동 코드를 사용한다.

signal status_changed(text: String)
signal session_ended(reason: String)

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const MAX_CONNECT_ATTEMPTS := 8

var address := "127.0.0.1"
var port := NetConfig.DEFAULT_PORT
var nickname := "Player"
var appearance := Appearance.default_appearance()
var platform := "pc"
var bot_mode := ""
var offline := false
## 오프라인 시작 모드 (--offline=obstacle_race 처럼 바로 미니게임 연습)
var offline_start_mode := "lobby"
## 오프라인에서 게임 규칙을 로컬 실행하는 호스트
var offline_host: OfflineHost
var token := "dev-guest"
## objective 봇이 로비에서 찾아갈 포털 모드 (--bot-portal=obstacle_race)
var bot_portal := ""
## 터치 조작 강제 표시 (PC에서 모바일 조작 테스트: --touch)
var force_touch := false
var touch_controls: TouchControls

var my_id := 0
var map: GameMap
var players_root: Node3D
var local_player: PlayerBody
var controller: LocalPlayerController
var camera: ThirdPersonCamera
var remotes := {}          # peer_id -> PlayerBody
var interpolators := {}    # peer_id -> RemoteInterpolator
var remote_names := {}     # peer_id -> nickname

var welcomed := false
var reject_reason := ""
var latest_tick := 0
var server_tick_est := 0.0
var snapshots_received := 0
var remote_ids_seen := {}
## 게임 모드 상태 (서버가 보냄)
var mode_state := {}
var mode_id := ""
var transfers: Array = []
var last_results: Array = []
var phases_seen := {}
var max_frame_ms := 0.0

var _attempts := 0
var _is_headless := DisplayServer.get_name() == "headless"


func start() -> void:
	if offline:
		_start_offline(offline_start_mode)
		return
	Net.client_handler = self
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_connect()


## 오프라인 연습: 서버 없이 맵 + GameMode 규칙을 로컬에서 실행 (로비 포털 → 미니게임 → 결과 → 로비)
func _start_offline(p_mode_id: String) -> void:
	if not ModeRegistry.has_mode(p_mode_id):
		p_mode_id = "lobby"
	my_id = OfflineHost.PEER_ID
	mode_id = p_mode_id
	welcomed = false
	_load_map(ModeRegistry.map_for(p_mode_id))
	_spawn_local({"peer_id": my_id, "pos": map.get_spawn_point(0), "appearance": appearance})
	offline_host = OfflineHost.new()
	offline_host.name = "OfflineHost"
	add_child(offline_host)
	offline_host.setup(self, p_mode_id)
	offline_host.transfer_requested.connect(_on_offline_transfer)
	controller.fell_handler = offline_host.on_fell
	status_changed.emit("연습 모드 (오프라인) · %s" % map.display_name)


func _on_offline_transfer(target_mode: String) -> void:
	transfers.append(target_mode)
	print("[CLIENT offline] transfer -> %s" % target_mode)
	_reset_world()
	_start_offline(target_mode)


func _connect() -> void:
	_attempts += 1
	var err := Net.start_client(address, port)
	if err != OK:
		status_changed.emit("접속 실패: %s" % error_string(err))
		session_ended.emit("connect_error")
		return
	var shown := address if Net.is_ws_url(address) else "%s:%d" % [address, port]
	status_changed.emit("서버 접속 중... %s (%d/%d)" % [shown, _attempts, MAX_CONNECT_ATTEMPTS])


func _on_connected() -> void:
	my_id = multiplayer.get_unique_id()
	Net.disable_throttle(1)
	if Auth.is_signed_in():
		token = await Auth.get_valid_id_token()
		if token == "":
			status_changed.emit("로그인이 만료되었습니다. 다시 로그인해 주세요.")
			reject_reason = "token_refresh_failed"
			Net.stop()
			session_ended.emit(reject_reason)
			return
	if bot_mode == "forged":
		token = _forged_token()
	var hello := {
		"protocol": NetConfig.PROTOCOL_VERSION,
		"token": token,
		"nickname": nickname,
		"appearance": appearance,
		"platform": platform,
	}
	if bot_mode == "badversion":
		hello["protocol"] = 9999
	if bot_mode == "silent":
		return  # hello를 보내지 않음 → 서버 타임아웃 검증용
	Net.c_hello.rpc_id(1, hello)
	status_changed.emit("입장 요청 중...")


## 테스트용 위조 토큰: 진짜처럼 보이는 클레임 + 임의 서명. 서버는 서명 검증에서 거절해야 한다.
## 로그인된 상태면 진짜 토큰의 payload만 바꿔치기(서명 불일치), 아니면 처음부터 위조(모르는 kid).
func _forged_token() -> String:
	if Auth.id_token != "":
		var parts := Auth.id_token.split(".")
		var p := Jwt.unsafe_payload(Auth.id_token)
		p["sub"] = "attacker"
		p["user_id"] = "attacker"
		return parts[0] + "." + Jwt.b64url_encode(JSON.stringify(p).to_utf8_buffer()) + "." + parts[2]
	var cfg := FirebaseConfig.load_default()
	var now := int(Time.get_unix_time_from_system())
	var header := {"alg": "RS256", "kid": "forged-kid", "typ": "JWT"}
	var payload := {
		"iss": "https://securetoken.google.com/" + cfg.project_id, "aud": cfg.project_id,
		"sub": "attacker", "user_id": "attacker", "iat": now, "exp": now + 3600, "auth_time": now,
		"firebase": {"sign_in_provider": "password"},
	}
	return "%s.%s.%s" % [
		Jwt.b64url_encode(JSON.stringify(header).to_utf8_buffer()),
		Jwt.b64url_encode(JSON.stringify(payload).to_utf8_buffer()),
		Jwt.b64url_encode(Crypto.new().generate_random_bytes(256)),
	]


func _on_connection_failed() -> void:
	if _attempts < MAX_CONNECT_ATTEMPTS and not welcomed:
		get_tree().create_timer(0.5).timeout.connect(_connect)
		return
	status_changed.emit("서버에 연결할 수 없습니다.")
	session_ended.emit("connection_failed")


func _on_server_disconnected() -> void:
	status_changed.emit("서버와 연결이 끊어졌습니다." + (" (%s)" % reject_reason if reject_reason != "" else ""))
	session_ended.emit(reject_reason if reject_reason != "" else "server_disconnected")


# ------------------------------------------------------------------ 서버 메시지

func on_welcome(data: Variant) -> void:
	if welcomed or typeof(data) != TYPE_DICTIONARY:
		return
	var d: Dictionary = data
	var map_id := str(d.get("map_id", ""))
	if not MapRegistry.has_map(map_id):
		status_changed.emit("알 수 없는 맵: %s" % map_id)
		return
	welcomed = true
	my_id = int(d.get("peer_id", my_id))
	latest_tick = int(d.get("tick", 0))
	server_tick_est = latest_tick
	mode_id = str(d.get("mode_id", ""))
	_load_map(map_id)
	for info in d.get("players", []):
		if int(info["peer_id"]) == my_id:
			_spawn_local(info)
		else:
			_spawn_remote(info)
	status_changed.emit("%s 입장 완료" % map.display_name)
	if typeof(d.get("mode_state")) == TYPE_DICTIONARY:
		on_mode_state(d["mode_state"])
	print("[CLIENT %d] welcomed into %s with %d players" % [my_id, map_id, remotes.size() + 1])


func on_reject(reason: Variant) -> void:
	reject_reason = str(reason)
	print("[CLIENT %d] rejected by server: %s" % [my_id, reject_reason])
	status_changed.emit("서버가 접속을 거절했습니다: %s" % reject_reason)


func on_player_joined(info: Variant) -> void:
	if welcomed and typeof(info) == TYPE_DICTIONARY:
		_spawn_remote(info)


func on_player_left(peer_id: Variant) -> void:
	var id := int(peer_id)
	if remotes.has(id):
		remotes[id].queue_free()
		remotes.erase(id)
		interpolators.erase(id)
		remote_names.erase(id)


func on_emote(peer_id: Variant, emote_id: Variant) -> void:
	var id := int(peer_id)
	var e := int(emote_id)
	if id == my_id or e < 0 or e >= Appearance.EMOTES.size():
		return
	var interp: RemoteInterpolator = interpolators.get(id)
	if interp and interp.visual:
		interp.visual.play_emote(Appearance.EMOTES[e])


func on_snapshot(packet: Variant) -> void:
	if not welcomed or typeof(packet) != TYPE_PACKED_BYTE_ARRAY:
		return
	var snap := SnapshotCodec.decode(packet)
	if snap.is_empty():
		return
	var t: int = snap["tick"]
	if t <= latest_tick and snapshots_received > 0:
		return
	latest_tick = t
	snapshots_received += 1
	if absf(server_tick_est - t) > 8.0:
		server_tick_est = t
	for e in snap["players"]:
		var id: int = e["id"]
		if id == my_id:
			if controller:
				controller.reconcile(e)
		elif interpolators.has(id):
			interpolators[id].push(e)
			remote_ids_seen[id] = true


func get_render_tick() -> float:
	return server_tick_est - NetConfig.INTERP_DELAY_TICKS


func _process(delta: float) -> void:
	if welcomed and snapshots_received > 30:
		max_frame_ms = maxf(max_frame_ms, delta * 1000.0)
	if welcomed:
		server_tick_est += delta * NetConfig.TICK_RATE
		# 수신 틱보다 너무 앞서 나가지 않도록 완만하게 당김
		if server_tick_est > latest_tick + 3:
			server_tick_est = lerpf(server_tick_est, latest_tick + 3, 0.2)
	_handle_emote_keys()


func _handle_emote_keys() -> void:
	if controller == null or bot_mode != "":
		return
	for i in Appearance.EMOTES.size():
		if Input.is_action_just_pressed("emote_%d" % (i + 1)):
			request_emote(i)


func request_emote(i: int) -> void:
	if local_player == null:
		return
	var visual := local_player.get_node_or_null("Visual") as CharacterVisual
	if visual:
		visual.play_emote(Appearance.EMOTES[i])
	if not offline:
		Net.c_emote.rpc_id(1, i)


# ------------------------------------------------------------------ 월드 구성

func _load_map(map_id: String) -> void:
	map = MapRegistry.instantiate(map_id)
	add_child(map)
	players_root = Node3D.new()
	players_root.name = "Players"
	add_child(players_root)


func _spawn_local(info: Dictionary) -> void:
	local_player = PLAYER_SCENE.instantiate()
	local_player.name = "LocalPlayer"
	local_player.peer_id = my_id
	local_player.world = map
	players_root.add_child(local_player)
	local_player.teleport(info.get("pos", Vector3.ZERO))

	if not _is_headless:
		var visual := _make_visual(info.get("appearance", appearance))
		visual.source_body = local_player
		local_player.add_child(visual)
		camera = ThirdPersonCamera.new()
		camera.name = "Camera"
		camera.target = local_player
		add_child(camera)

	controller = LocalPlayerController.new()
	controller.name = "Controller"
	controller.body = local_player
	controller.camera = camera
	controller.map = map
	controller.online = not offline
	controller.bot_mode = bot_mode if LocalPlayerController.BOT_MODES.has(bot_mode) else ""
	controller.bot_target_fn = _bot_target
	local_player.add_child(controller)
	if not _is_headless and bot_mode == "" and (force_touch or OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()):
		if is_instance_valid(touch_controls):
			touch_controls.queue_free()
		touch_controls = TouchControls.new()
		touch_controls.controller = controller
		touch_controls.camera = camera
		touch_controls.client = self
		add_child(touch_controls)


func _spawn_remote(info: Dictionary) -> void:
	var id := int(info.get("peer_id", 0))
	if id == 0 or id == my_id or remotes.has(id):
		return
	var body: PlayerBody = PLAYER_SCENE.instantiate()
	body.name = "Remote%d" % id
	body.peer_id = id
	body.collision_layer = 0
	body.collision_mask = 0
	body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	players_root.add_child(body)
	body.global_position = info.get("pos", Vector3.ZERO)

	var interp := RemoteInterpolator.new()
	interp.body = body
	interp.client = self
	if not _is_headless:
		interp.visual = _make_visual(info.get("appearance", {}))
		body.add_child(interp.visual)
		_add_name_tag(body, str(info.get("nickname", "?")))
	body.add_child(interp)
	remotes[id] = body
	interpolators[id] = interp
	remote_names[id] = str(info.get("nickname", "?"))


func _make_visual(app: Variant) -> CharacterVisual:
	var v := CharacterVisual.new()
	v.name = "Visual"
	v.build(Appearance.sanitize(app))
	return v


func _add_name_tag(body: Node3D, text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = Vector3(0, 2.0, 0)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 40
	l.outline_size = 12
	l.pixel_size = 0.008
	l.no_depth_test = false
	body.add_child(l)


# ------------------------------------------------------------------ 테스트/모니터링

func report() -> Dictionary:
	var seen_positions := {}
	for id in interpolators.keys():
		var p: Vector3 = interpolators[id].last_position
		seen_positions[str(id)] = [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]
	var pos := local_player.global_position if local_player else Vector3.ZERO
	return {
		"id": my_id,
		"nickname": nickname,
		"bot": bot_mode,
		"welcomed": welcomed,
		"rejected": reject_reason,
		"snapshots": snapshots_received,
		"remote_ids_seen": remote_ids_seen.keys(),
		"remote_positions": seen_positions,
		"pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)],
		"corrections": controller.corrections if controller else 0,
		"max_correction": snappedf(controller.max_correction, 0.001) if controller else 0.0,
		"distance_moved": snappedf(controller.distance_moved, 0.01) if controller else 0.0,
		"rtt_ms": Net.get_rtt_ms(),
		"small_corrections": controller.small_corrections if controller else 0,
		"max_small_correction": snappedf(controller.max_small_correction, 0.001) if controller else 0.0,
		"teleports": controller.teleports if controller else 0,
		"mode": mode_id,
		"phases_seen": phases_seen.keys(),
		"transfers": transfers,
		"my_result": _my_result(),
		"my_entry": mode_state.get("players", {}).get(str(my_id), {}),
		"max_frame_ms": snappedf(max_frame_ms, 0.1),
	}


# ------------------------------------------------------------------ 게임 모드 (클라이언트 표시용)

signal mode_state_changed

func on_mode_state(state: Variant) -> void:
	if typeof(state) != TYPE_DICTIONARY:
		return
	mode_state = state
	phases_seen[str(state.get("phase", ""))] = true
	if map:
		map.round_start_tick = int(state.get("round_start_tick", 0))
		map.apply_mode_state(state)
	var me: Dictionary = state.get("players", {}).get(str(my_id), {})
	if local_player:
		# 서버와 같은 규칙으로 이동 금지 예측 (카운트다운 / 완주 후)
		local_player.frozen = state.get("phase") == "countdown" or me.get("status") == "finished"
	var results: Array = state.get("results", [])
	if not results.is_empty():
		last_results = results
	mode_state_changed.emit()


func on_notice(text: Variant) -> void:
	status_changed.emit(str(text))


## 서버가 다른 서버로 보냄 (로비 → 미니게임 → 로비). 같은 로그인 토큰으로 새 서버에 다시 접속.
func on_transfer(route: Variant, target: Variant) -> void:
	var r := str(route)
	var new_addr := ""
	var new_port := 0
	if r.begins_with("/") and Net.is_ws_url(address):
		new_addr = Net.ws_base(address) + r  # 같은 게이트웨이의 다른 경로
	elif Net.is_ws_url(r):
		new_addr = r
	else:
		var parts := r.split(":")
		if parts.size() != 2 or not parts[1].is_valid_int():
			return
		new_addr = parts[0] if parts[0] != "" else address  # ":7781" → 같은 서버 주소, 다른 포트
		new_port = int(parts[1])
	transfers.append(str(target))
	print("[CLIENT %d] transfer -> %s (%s)" % [my_id, route, target])
	status_changed.emit("이동 중... (%s)" % target)
	_reset_world()
	Net.stop()
	address = new_addr
	port = new_port
	_attempts = 0
	get_tree().create_timer(0.2).timeout.connect(_connect)


func _reset_world() -> void:
	welcomed = false
	for n in [map, players_root, camera, offline_host]:
		if is_instance_valid(n):
			n.queue_free()
	offline_host = null
	map = null
	players_root = null
	camera = null
	local_player = null
	controller = null
	remotes.clear()
	interpolators.clear()
	remote_names.clear()
	mode_state = {}
	latest_tick = 0
	snapshots_received = 0


func _bot_target(pos: Vector3) -> Vector3:
	if map == null:
		return Vector3.INF
	# 로비에서 "portal:<모드>" 봇은 해당 포털로 이동
	if bot_portal != "" and map is LobbyPlazaMap:
		for p in (map as LobbyPlazaMap).portals:
			if p["mode"] == bot_portal:
				return p["center"]
	if mode_state.get("phase") != "playing":
		return Vector3.INF
	return map.get_bot_target(pos, mode_state, my_id)


func _my_result() -> Dictionary:
	for r in last_results:
		if int(r.get("peer_id", 0)) == my_id:
			return r
	return {}
