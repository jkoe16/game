class_name GameClient
extends Node
## 게임 클라이언트: 서버 접속, 맵/플레이어 생성, 스냅샷 적용, 로컬 예측 및 원격 보간 관리.
## offline=true 이면 서버 없이 연습 모드로 같은 맵/이동 코드를 사용한다.
##
## 재접속: 입장 때 받은 세션 토큰을 보관해 두었다가, 연결이 갑자기 끊기면(서버 연결 끊김 이벤트 또는
## 스냅샷이 SNAPSHOT_SILENCE_MS 동안 안 옴) 같은 주소로 다시 접속해 hello에 "resume"으로 보낸다.
## 서버가 자리를 남겨 두었으면 같은 캐릭터·점수로 이어서 플레이한다. 추방·거절·스스로 나가기·서버 이동은 재접속하지 않는다.

signal status_changed(text: String)
signal session_ended(reason: String)

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const MAX_CONNECT_ATTEMPTS := 8
## 클라우드(ws/wss) 서버: 무료 호스팅은 잠들어 있다가 깨어나는 데 최대 1분 → 2초 간격으로 약 90초까지 재시도
const MAX_CONNECT_ATTEMPTS_CLOUD := 45
const CLOUD_RETRY_SEC := 2.0

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
## 접속한 서버의 버전 (git 커밋 앞 7자리). 업데이트가 반영됐는지 확인용
var server_version := ""
var transfers: Array = []
var last_results: Array = []
var phases_seen := {}
var max_frame_ms := 0.0

var _attempts := 0
## 재접속용 세션 토큰 (서버가 s_welcome에서 줌)
var session_token := ""
## 끊긴 뒤 다시 접속하는 중
var reconnecting := false
## 재접속 시작 횟수 / 자리를 그대로 이어받은 횟수 (테스트·모니터링)
var reconnects := 0
var resumed_count := 0
## 재접속 직전 내 위치와 다시 들어온 위치의 차 (m, 마지막 재접속 기준)
var resume_offset := -1.0
var _pos_before_drop := Vector3.INF
var _last_snapshot_ms := 0
var _left := false
## 다음 접속 시도가 예약돼 있음 (중복 예약·늦게 온 옛 연결 이벤트 무시용)
var _connect_pending := false
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


func _schedule_connect(delay: float) -> void:
	if _connect_pending:
		return
	_connect_pending = true
	get_tree().create_timer(delay).timeout.connect(_connect)


func _connect() -> void:
	_connect_pending = false
	if _left:
		return
	_attempts += 1
	var err := Net.start_client(address, port)
	if err != OK:
		status_changed.emit("접속 실패: %s" % error_string(err))
		session_ended.emit("connect_error")
		return
	var shown := address if Net.is_ws_url(address) else "%s:%d" % [address, port]
	if reconnecting:
		status_changed.emit("연결이 끊겼어요. 다시 접속하는 중... (%d/%d)" % [_attempts, _max_attempts()])
	elif Net.is_ws_url(address) and _attempts > 3:
		status_changed.emit("서버를 깨우는 중이에요... 무료 서버는 최대 1분 걸려요 (%d초)" % int(_attempts * CLOUD_RETRY_SEC))
	else:
		status_changed.emit("서버 접속 중... %s (%d/%d)" % [shown, _attempts, _max_attempts()])


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
	if session_token != "":
		hello["resume"] = session_token
	if bot_mode == "silent":
		return  # hello를 보내지 않음 → 서버 타임아웃 검증용
	Net.c_hello.rpc_id(1, hello)
	status_changed.emit("다시 들어가는 중..." if reconnecting else "입장 요청 중...")


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


func _max_attempts() -> int:
	if reconnecting:
		return NetConfig.RECONNECT_MAX_ATTEMPTS
	return MAX_CONNECT_ATTEMPTS_CLOUD if Net.is_ws_url(address) else MAX_CONNECT_ATTEMPTS


func _retry_delay() -> float:
	if reconnecting:
		return NetConfig.RECONNECT_RETRY_SEC
	return CLOUD_RETRY_SEC if Net.is_ws_url(address) else 0.5


func _on_connection_failed() -> void:
	if _left or _connect_pending:
		return
	if _attempts < _max_attempts() and not welcomed:
		_schedule_connect(_retry_delay())
		return
	if reconnecting:
		reconnecting = false
		status_changed.emit("다시 접속하지 못했어요.")
		session_ended.emit("reconnect_failed")
		return
	status_changed.emit("서버에 연결할 수 없습니다.")
	session_ended.emit("connection_failed")


func _on_server_disconnected() -> void:
	if _connect_pending:
		return  # 이미 다시 접속하려고 기다리는 중 (스스로 닫은 옛 연결의 늦은 이벤트)
	if _can_reconnect():
		if welcomed:
			_begin_reconnect("server_disconnected", NetConfig.RECONNECT_RETRY_SEC * 0.5)
		elif _attempts < _max_attempts():
			# 재접속 도중 입장 전에 다시 끊김 → 조금 뒤 다시 시도
			Net.stop()
			_schedule_connect(_retry_delay())
		else:
			_on_connection_failed()
		return
	if _left:
		return
	status_changed.emit("서버와 연결이 끊어졌습니다." + (" (%s)" % reject_reason if reject_reason != "" else ""))
	session_ended.emit(reject_reason if reject_reason != "" else "server_disconnected")


## 갑작스러운 끊김만 재접속 (서버가 거절·추방했거나 스스로 나간 경우는 아님)
func _can_reconnect() -> bool:
	return not offline and not _left and reject_reason == "" and session_token != "" and (welcomed or reconnecting)


## 지금 연결을 버리고 같은 서버에 다시 접속한다. 화면은 다시 입장할 때 새로 만든다.
func _begin_reconnect(why: String, delay: float) -> void:
	print("[CLIENT %d] connection lost (%s) — reconnecting" % [my_id, why])
	_pos_before_drop = local_player.global_position if local_player else Vector3.INF
	reconnecting = true
	reconnects += 1
	_reset_world()
	Net.stop()
	_attempts = 0
	status_changed.emit("연결이 끊겼어요. 다시 접속하는 중...")
	_schedule_connect(delay)


## 테스트용: 연결을 갑자기 끊고(나가기 알림 없이) hold_sec 뒤 재접속
func simulate_drop(hold_sec: float) -> void:
	if offline or not welcomed:
		return
	_begin_reconnect("simulated drop %.1fs" % hold_sec, hold_sec)


## 스스로 나가기: 서버에 알려 재접속용 자리를 남기지 않게 한 뒤 연결을 닫는다
func leave() -> void:
	if _left:
		return
	_left = true
	reconnecting = false
	var peer := multiplayer.multiplayer_peer
	if offline or not welcomed or peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	Net.c_leave.rpc_id(1)
	print("[CLIENT %d] leaving" % my_id)
	# 신뢰성 메시지가 실제로 나갈 시간을 잠깐 준다 (연결을 바로 닫으면 버려질 수 있음)
	await get_tree().create_timer(0.15).timeout
	Net.stop()


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
	session_token = str(d.get("session", ""))
	var resumed: bool = d.get("resumed", false) == true
	latest_tick = int(d.get("tick", 0))
	server_tick_est = latest_tick
	mode_id = str(d.get("mode_id", ""))
	server_version = str(d.get("server_version", "?"))
	_load_map(map_id)
	for info in d.get("players", []):
		if int(info["peer_id"]) == my_id:
			_spawn_local(info)
		else:
			_spawn_remote(info)
	_last_snapshot_ms = Time.get_ticks_msec()
	if resumed:
		resumed_count += 1
		if local_player and _pos_before_drop != Vector3.INF:
			resume_offset = local_player.global_position.distance_to(_pos_before_drop)
		status_changed.emit("다시 연결됐어요! 이어서 플레이해요")
	elif reconnecting:
		status_changed.emit("다시 연결됐어요 (기다리는 시간이 지나 새로 입장했어요)")
	else:
		status_changed.emit("%s 입장 완료" % map.display_name)
	reconnecting = false
	if typeof(d.get("mode_state")) == TYPE_DICTIONARY:
		on_mode_state(d["mode_state"])
	print("[CLIENT %d] %s %s with %d players" % [my_id, "resumed session in" if resumed else "welcomed into", map_id, remotes.size() + 1])


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
	_last_snapshot_ms = Time.get_ticks_msec()
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
	if welcomed and not offline and _last_snapshot_ms > 0 and Time.get_ticks_msec() - _last_snapshot_ms > NetConfig.SNAPSHOT_SILENCE_MS:
		# 서버가 조용함 (회선이 끊겼는데 아직 연결 끊김 이벤트가 안 옴) → 기다리지 않고 재접속
		_last_snapshot_ms = 0
		if _can_reconnect():
			_begin_reconnect("no snapshots for %dms" % NetConfig.SNAPSHOT_SILENCE_MS, 0.1)
			return
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
		"reconnects": reconnects,
		"resumed": resumed_count,
		"resume_offset": snappedf(resume_offset, 0.01),
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
		map.render_items(state.get("extra", {}).get("items", []))
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
	session_token = ""  # 세션 토큰은 서버마다 따로
	reconnecting = false
	address = new_addr
	port = new_port
	_attempts = 0
	_schedule_connect(0.2)


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
