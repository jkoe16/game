class_name GameServer
extends Node
## 전용 게임 서버 (프로세스 1개 = 방 1개). 헤드리스로 실행되며 그래픽을 렌더링하지 않는다.
##
## 서버 권한 원칙:
##  - 클라이언트는 입력(PlayerInput)만 보낸다. 위치/점수/승패는 받지 않는다.
##  - 서버가 매 틱 입력 1개만 소비해 시뮬레이션 → 입력을 많이 보내도 빨라지지 않는다 (스피드핵 방지).
##  - 모든 수신 데이터는 타입/범위/빈도를 검증하고, 위반이 누적되면 추방한다.
##
## 재접속:
##  - 입장하면 서버가 무작위 세션 토큰을 준다 (s_welcome의 "session").
##  - 연결이 갑자기 끊기면 플레이어를 바로 지우지 않고 RECONNECT_GRACE_MS 동안 자리를 남겨 둔다
##    (캐릭터는 그 자리에 멈춰 있고, 점수·진행도·순위는 그대로). 남은 자리도 정원에 포함된다.
##  - 그 안에 hello에 같은 세션 토큰("resume")을 넣어 다시 들어오면 새 연결(peer_id)로 자리를 넘겨받는다.
##    Firebase 모드에서는 토큰이 없어도 같은 계정이면 이어서 (새로고침 등), 토큰이 있어도 계정이 다르면 거부.
##  - 추방·서버 이동·스스로 나가기(c_leave)는 자리를 남기지 않고 바로 퇴장 처리.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")


class ServerPlayer:
	var peer_id := 0
	var nickname := ""
	var appearance := {}
	var platform := "pc"
	var spawn_index := 0
	var body: PlayerBody
	var input_queue: Array[PlayerInput] = []
	var last_move := PlayerInput.new()
	var last_seq := 0
	var ack := 0
	var rate_window_ms := 0
	var rate_count := 0
	var dropped_inputs := 0
	var starved_ticks := 0
	var violations := 0
	var next_emote_ms := 0
	var max_speed := 0.0
	var respawns := 0
	var kicked := false
	var credit := 0.0
	var uid := ""
	var auth_provider := ""
	var joined_ms := 0
	var lost_inputs := 0
	var ack_tick := 0
	## 입력 없이 연속으로 외삽한 틱 수 (MAX_EXTRAPOLATE_TICKS를 넘으면 제자리에 멈춤)
	var extrapolated_run := 0
	## 재접속용 비밀 토큰 (입장·재접속 때마다 새로 발급)
	var session_token := ""
	## > 0: 연결이 끊겨 재접속을 기다리는 중 (끊긴 시각 ms)
	var away_since_ms := 0
	## 서버 이동·스스로 나가기 → 끊겨도 자리를 남기지 않음
	var leaving := false
	var last_input_ms := 0
	## 끊긴 동안 놓친 서버 이동 [route, target] → 돌아오면 바로 이동시킨다
	var pending_transfer: Array = []
	var resumes := 0


var port := NetConfig.DEFAULT_PORT
## "enet" | "ws" (--transport=ws)
var transport := "enet"
var max_players := NetConfig.DEFAULT_MAX_PLAYERS
var map_id := "lobby_plaza"
## 게임 모드 (lobby / obstacle_race / survival / racing / coop / party)
var mode_id := "lobby"
var mode_cfg := {}
var mode: GameMode
var rounds_completed := 0
## "firebase": Firebase ID 토큰 서명/클레임 검증 (운영) / "dev": 토큰 형식만 확인 (로컬 개발·네트워크 테스트 전용)
var auth_mode := "dev"
## 끊긴 플레이어 자리 유지 시간 (ms). 0이면 재접속 기능 끔. --reconnect-grace=초
var reconnect_grace_ms := NetConfig.RECONNECT_GRACE_MS
var verifier: FirebaseTokenVerifier
var verifying := {}  # peer_id -> true (토큰 검증 진행 중)
## Firestore (서비스 계정이 있을 때만). 프로필 로드 / 플레이 기록 저장
var service_account_path := ""
var data_fs: FirestoreClient
var _sa: ServiceAccountAuth

var tick := 0
var map: GameMap
var players := {}   # peer_id -> ServerPlayer
var pending := {}   # peer_id -> 접속 시각(ms). hello 전 상태
var players_root: Node3D
var stats := {"joined": 0, "left": 0, "rejected": {}, "kicked": {}, "invalid_packets": 0, "profile_loaded": 0, "stats_written": 0, "data_errors": 0, "away": 0, "resumed": 0, "away_expired": 0, "silent_dropped": 0}


func start() -> bool:
	if not ModeRegistry.has_mode(mode_id):
		push_error("[SERVER] unknown mode: %s" % mode_id)
		return false
	map_id = ModeRegistry.map_for(mode_id)
	map = MapRegistry.instantiate(map_id)
	if map == null:
		push_error("[SERVER] unknown map: %s" % map_id)
		return false
	add_child(map)
	mode = ModeRegistry.create(mode_id)
	mode.setup(self, map, mode_cfg)
	if mode is LobbyMode:
		(mode as LobbyMode).routes = mode_cfg.get("routes", {})
	add_child(mode)
	mode.round_finished.connect(_on_round_finished)
	players_root = Node3D.new()
	players_root.name = "Players"
	add_child(players_root)

	if auth_mode == "firebase":
		var cfg := FirebaseConfig.load_default()
		if not cfg.is_server_ready():
			push_error("[SERVER] --auth=firebase requires project_id in %s" % FirebaseConfig.DEFAULT_PATH)
			return false
		verifier = FirebaseTokenVerifier.new()
		verifier.name = "TokenVerifier"
		add_child(verifier)
		verifier.setup(cfg)
		verifier.fetch_keys()  # 미리 공개키를 받아 둔다 (결과는 verify 시 다시 확인)
		print("[SERVER] Firebase auth enabled (project=%s)" % cfg.project_id)
		_setup_data(cfg)
	else:
		push_warning("[SERVER] DEV AUTH MODE — tokens are NOT verified. Never use in production.")

	var err := Net.start_server(port, max_players + NetConfig.EXTRA_CONNECTION_SLOTS, transport)
	if err != OK:
		push_error("[SERVER] failed to listen on %d: %s" % [port, error_string(err)])
		return false
	Net.server_handler = self
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Engine.max_fps = 120  # 헤드리스에서 CPU 과점유 방지
	print("[SERVER] listening on port %d (%s) | mode=%s map=%s | max_players=%d | auth=%s | reconnect_grace=%ds" % [port, transport, mode_id, map_id, max_players, auth_mode, reconnect_grace_ms / 1000])
	return true


func _physics_process(delta: float) -> void:
	if map == null:
		return
	tick += 1
	_check_timeouts()
	map.round_start_tick = mode.round_start_tick
	map.update_world(tick)
	for sp: ServerPlayer in players.values():
		sp.body.frozen = sp.away_since_ms > 0 or mode.is_frozen(sp.peer_id)
		_step_player(sp, delta)
	mode.server_tick(tick)
	if tick % NetConfig.SNAPSHOT_EVERY_N_TICKS == 0:
		_send_snapshot()
	if mode.dirty or tick % 30 == 0:
		_broadcast_mode_state()


# ------------------------------------------------------------------ 접속 관리

func _on_peer_connected(peer_id: int) -> void:
	pending[peer_id] = Time.get_ticks_msec()
	Net.disable_throttle(peer_id)
	print("[SERVER] peer %d connected (awaiting hello)" % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	pending.erase(peer_id)
	if not players.has(peer_id):
		return  # 입장 전이었거나, 이미 다른 연결로 재접속해 자리를 넘겨받음
	var sp: ServerPlayer = players[peer_id]
	if sp.away_since_ms > 0:
		return  # 이미 끊김 처리됨 (입력 끊김 감지)
	if sp.kicked or sp.leaving or reconnect_grace_ms <= 0:
		_remove_player(sp)
	else:
		_hold_seat(sp)


## 갑자기 끊긴 플레이어: 자리를 남겨 두고 재접속을 기다린다
func _hold_seat(sp: ServerPlayer) -> void:
	sp.away_since_ms = Time.get_ticks_msec()
	sp.input_queue.clear()
	sp.last_move = PlayerInput.new()
	sp.credit = 0.0
	stats["away"] += 1
	print("[SERVER] player %d (%s) disconnected — holding seat for %ds" % [sp.peer_id, sp.nickname, reconnect_grace_ms / 1000])
	for id in _active_ids():
		Net.s_notice.rpc_id(id, "%s 님의 연결이 끊겼어요. 다시 들어오길 기다리는 중..." % sp.nickname)


func _remove_player(sp: ServerPlayer) -> void:
	var peer_id := sp.peer_id
	sp.body.queue_free()
	players.erase(peer_id)
	mode.on_player_left(peer_id)
	stats["left"] += 1
	_record_session(sp)
	print("[SERVER] player %d (%s) left" % [peer_id, sp.nickname])
	for id in _active_ids():
		Net.s_player_left.rpc_id(id, peer_id)


func _check_timeouts() -> void:
	if tick % 30 != 0:
		return
	var now := Time.get_ticks_msec()
	for peer_id in pending.keys():
		if now - int(pending[peer_id]) > NetConfig.HELLO_TIMEOUT_MS:
			_reject(peer_id, "hello_timeout")
	for sp: ServerPlayer in players.values():
		if sp.away_since_ms > 0:
			if now - sp.away_since_ms > reconnect_grace_ms:
				stats["away_expired"] += 1
				print("[SERVER] player %d (%s) did not come back in %ds — removing" % [sp.peer_id, sp.nickname, reconnect_grace_ms / 1000])
				_remove_player(sp)
		elif reconnect_grace_ms > 0 and not sp.kicked and not sp.leaving and now - sp.last_input_ms > NetConfig.INPUT_SILENCE_MS:
			# 연결은 열려 있다고 나오지만 입력이 끊김 (회선이 조용히 끊긴 경우) → 끊긴 것으로 처리
			stats["silent_dropped"] += 1
			print("[SERVER] player %d (%s) silent for %dms — treating as disconnected" % [sp.peer_id, sp.nickname, now - sp.last_input_ms])
			_hold_seat(sp)
			Net.kick(sp.peer_id)


## hello의 "resume" 토큰과 맞는 자리 (없으면 null). 서버가 아직 끊김을 모르는 연결도 포함 (새 연결이 넘겨받음)
func _find_resumable(token: Variant) -> ServerPlayer:
	if typeof(token) != TYPE_STRING or (token as String).length() != 32 or not (token as String).is_valid_hex_number():
		return null
	for sp: ServerPlayer in players.values():
		if sp.session_token == token and not sp.kicked and not sp.leaving:
			return sp
	return null


static func _new_session_token() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


func on_hello(peer_id: int, data: Variant) -> void:
	if not pending.has(peer_id):
		_violation(peer_id, "unexpected_hello")
		return
	if typeof(data) != TYPE_DICTIONARY:
		_reject(peer_id, "bad_request")
		return
	var d: Dictionary = data
	var protocol: Variant = d.get("protocol", -1)
	if typeof(protocol) != TYPE_INT or protocol != NetConfig.PROTOCOL_VERSION:
		_reject(peer_id, "version_mismatch")
		return
	var resume_sp := _find_resumable(d.get("resume"))
	if players.size() >= max_players and resume_sp == null:
		_reject(peer_id, "room_full")
		return
	var nickname := Validation.sanitize_nickname(d.get("nickname"))
	if nickname == "":
		_reject(peer_id, "bad_nickname")
		return

	# 토큰 검증 (Firebase 모드에서는 공개키 조회 때문에 비동기일 수 있음)
	if verifying.has(peer_id):
		_violation(peer_id, "duplicate_hello")
		return
	verifying[peer_id] = true
	var auth: Dictionary = await _verify_token(d.get("token"), peer_id)
	verifying.erase(peer_id)
	if not pending.has(peer_id):
		return  # 검증 중 연결이 끊겼거나 타임아웃
	if not auth["ok"]:
		print("[SERVER] auth failed for peer %d: %s" % [peer_id, auth.get("reason", "?")])
		_reject(peer_id, "auth_failed")
		return
	# 재접속: 검증 중 자리가 사라졌거나 (유예 만료), 다른 계정의 토큰이면 새 입장으로 처리
	if resume_sp != null and (not players.has(resume_sp.peer_id) or players[resume_sp.peer_id] != resume_sp or resume_sp.kicked or resume_sp.leaving \
			or (auth_mode != "dev" and resume_sp.uid != auth["uid"])):
		resume_sp = null
	if resume_sp == null and not str(auth["uid"]).begins_with("dev:"):
		# 토큰을 잃어버린 경우 (새로고침 등): 같은 계정의 끊긴 자리가 있으면 이어서
		for other: ServerPlayer in players.values():
			if other.uid == auth["uid"] and other.away_since_ms > 0 and not other.kicked and not other.leaving:
				resume_sp = other
				break
	if resume_sp != null:
		pending.erase(peer_id)
		_resume(resume_sp, peer_id)
		return
	if players.size() >= max_players:
		_reject(peer_id, "room_full")
		return
	# 같은 계정으로 중복 접속 → 기존 세션 추방 (계정당 1세션)
	for other: ServerPlayer in players.values():
		if other.uid == auth["uid"] and not other.kicked:
			_kick(other.peer_id, "logged_in_elsewhere")

	# Firestore에 저장된 프로필이 있으면 클라이언트가 보낸 값 대신 그것을 사용 (서버가 진실의 원천)
	var appearance_src: Variant = d.get("appearance")
	if data_fs:
		var prof: Dictionary = await data_fs.get_doc("profiles/" + str(auth["uid"]))
		if not pending.has(peer_id):
			return
		if prof["ok"]:
			var stored_nick := Validation.sanitize_nickname(prof["data"].get("nickname"))
			if stored_nick != "":
				nickname = stored_nick
			appearance_src = prof["data"].get("appearance")
			stats["profile_loaded"] += 1
		elif prof["status"] != 404:
			stats["data_errors"] += 1
			push_warning("[SERVER] profile load failed for %s: %s" % [auth["uid"], prof["error"]])
		if players.size() >= max_players:
			_reject(peer_id, "room_full")
			return

	pending.erase(peer_id)
	var sp := ServerPlayer.new()
	sp.joined_ms = Time.get_ticks_msec()
	sp.peer_id = peer_id
	sp.uid = auth["uid"]
	sp.auth_provider = auth["provider"]
	sp.nickname = nickname
	sp.appearance = Appearance.sanitize(appearance_src)
	sp.platform = "mobile" if d.get("platform") == "mobile" else "pc"
	sp.spawn_index = _free_spawn_index()
	sp.rate_window_ms = Time.get_ticks_msec()
	sp.last_input_ms = sp.rate_window_ms
	sp.session_token = _new_session_token()
	sp.body = PLAYER_SCENE.instantiate()
	sp.body.name = "P%d" % peer_id
	sp.body.peer_id = peer_id
	sp.body.world = map
	players_root.add_child(sp.body)
	sp.body.teleport(mode.on_player_joined(peer_id, nickname))
	players[peer_id] = sp
	stats["joined"] += 1

	_send_welcome(sp, false)
	for id in _active_ids():
		if id != peer_id:
			Net.s_player_joined.rpc_id(id, _player_info(sp))
	print("[SERVER] player %d joined as '%s' (%s) [%d/%d]" % [peer_id, nickname, sp.platform, players.size(), max_players])


func _send_welcome(sp: ServerPlayer, resumed: bool) -> void:
	var roster: Array = []
	for other: ServerPlayer in players.values():
		roster.append(_player_info(other))
	Net.s_welcome.rpc_id(sp.peer_id, {
		"peer_id": sp.peer_id,
		"map_id": map_id,
		"mode_id": mode_id,
		"server_version": BuildInfo.server_version(),
		"mode_state": mode.public_state(),
		"tick": tick,
		"players": roster,
		"session": sp.session_token,
		"resumed": resumed,
	})


## 끊겼던(또는 서버가 아직 끊김을 모르는) 자리를 새 연결 new_id가 넘겨받는다.
## 캐릭터 위치·속도, 모드 점수·진행도, 닉네임·외형, 플레이 시간은 그대로. 입력 번호(seq)만 새로 시작.
func _resume(sp: ServerPlayer, new_id: int) -> void:
	var old_id := sp.peer_id
	var now := Time.get_ticks_msec()
	var was_connected := sp.away_since_ms == 0
	var away_ms := 0 if was_connected else now - sp.away_since_ms
	players.erase(old_id)
	sp.peer_id = new_id
	sp.body.peer_id = new_id
	sp.body.name = "P%d" % new_id
	sp.away_since_ms = 0
	sp.input_queue.clear()
	sp.last_move = PlayerInput.new()
	sp.last_seq = 0
	sp.ack = 0
	sp.ack_tick = tick
	sp.credit = 0.0
	sp.rate_window_ms = now
	sp.rate_count = 0
	sp.last_input_ms = now
	sp.session_token = _new_session_token()
	sp.resumes += 1
	players[new_id] = sp
	mode.on_player_rekeyed(old_id, new_id)
	stats["resumed"] += 1
	if was_connected:
		Net.kick(old_id)  # 서버가 아직 끊김을 몰랐던 옛 연결 정리 (그 연결의 퇴장 이벤트는 무시됨)
	print("[SERVER] player %d resumed as %d ('%s') after %dms away [%d/%d]" % [old_id, new_id, sp.nickname, away_ms, players.size(), max_players])
	_send_welcome(sp, true)
	for id in _active_ids():
		if id != new_id:
			Net.s_player_left.rpc_id(id, old_id)
			Net.s_player_joined.rpc_id(id, _player_info(sp))
			Net.s_notice.rpc_id(id, "%s 님이 다시 들어왔어요" % sp.nickname)
	if not sp.pending_transfer.is_empty():
		var tr: Array = sp.pending_transfer
		sp.pending_transfer = []
		transfer_player(new_id, tr[0], tr[1])


## 클라이언트가 스스로 나감 → 끊겨도 자리를 남기지 않는다
func on_leave(peer_id: int) -> void:
	if players.has(peer_id):
		players[peer_id].leaving = true


## 반환 {ok, uid, provider, reason}
func _verify_token(token: Variant, peer_id: int) -> Dictionary:
	if not Validation.is_valid_token_shape(token):
		return {"ok": false, "reason": "token_shape"}
	if auth_mode == "dev":
		# 개발 모드: 토큰 형식만 확인. 피어마다 다른 가짜 uid (중복 접속 판정 안 함)
		return {"ok": true, "uid": "dev:%d" % peer_id, "provider": "dev"}
	return await verifier.verify(token)


func _player_info(sp: ServerPlayer) -> Dictionary:
	return {
		"peer_id": sp.peer_id,
		"nickname": sp.nickname,
		"appearance": sp.appearance,
		"platform": sp.platform,
		"pos": sp.body.global_position,
	}


func _free_spawn_index() -> int:
	var used := {}
	for sp: ServerPlayer in players.values():
		used[sp.spawn_index] = true
	var i := 0
	while used.has(i):
		i += 1
	return i


func _reject(peer_id: int, reason: String) -> void:
	pending.erase(peer_id)
	var bucket: Dictionary = stats["rejected"]
	bucket[reason] = int(bucket.get(reason, 0)) + 1
	print("[SERVER] rejecting peer %d: %s" % [peer_id, reason])
	Net.s_reject.rpc_id(peer_id, reason)
	# 거절 메시지가 전달될 시간을 준 뒤 연결 종료
	get_tree().create_timer(0.3).timeout.connect(Net.kick.bind(peer_id))


func _kick(peer_id: int, reason: String) -> void:
	if not players.has(peer_id):
		return
	var bucket: Dictionary = stats["kicked"]
	bucket[reason] = int(bucket.get(reason, 0)) + 1
	print("[SERVER] kicking player %d: %s" % [peer_id, reason])
	Net.s_reject.rpc_id(peer_id, reason)
	get_tree().create_timer(0.3).timeout.connect(Net.kick.bind(peer_id))
	# 추방 즉시 시뮬레이션 대상에서 제외
	var sp: ServerPlayer = players[peer_id]
	sp.input_queue.clear()
	sp.kicked = true


func _violation(peer_id: int, what: String) -> void:
	stats["invalid_packets"] += 1
	if not players.has(peer_id):
		return
	var sp: ServerPlayer = players[peer_id]
	if sp.kicked:
		return
	sp.violations += 1
	if sp.violations >= NetConfig.MAX_VIOLATIONS:
		_kick(peer_id, "too_many_violations")


# ------------------------------------------------------------------ 입력 & 시뮬레이션

func on_input(peer_id: int, packet: Variant) -> void:
	if not players.has(peer_id):
		return
	var sp: ServerPlayer = players[peer_id]
	if sp.kicked or sp.away_since_ms > 0:
		return

	var now := Time.get_ticks_msec()
	sp.last_input_ms = now
	if now - sp.rate_window_ms >= 1000:
		sp.rate_window_ms = now
		sp.rate_count = 0
	sp.rate_count += 1
	if sp.rate_count > NetConfig.FLOOD_KICK_PACKETS_PER_SEC:
		_kick(peer_id, "input_flood")
		return
	if sp.rate_count > NetConfig.MAX_INPUT_PACKETS_PER_SEC:
		sp.dropped_inputs += 1
		return

	if typeof(packet) != TYPE_PACKED_BYTE_ARRAY:
		_violation(peer_id, "input_type")
		return
	var inputs := InputCodec.decode(packet)
	if inputs.is_empty():
		_violation(peer_id, "input_format")
		return
	for inp in inputs:
		if inp.seq <= sp.last_seq:
			continue  # 중복 전송분 (정상)
		if inp.seq > sp.last_seq + NetConfig.MAX_SEQ_JUMP:
			_violation(peer_id, "seq_jump")
			continue
		if sp.last_seq > 0 and inp.seq > sp.last_seq + 1:
			sp.lost_inputs += inp.seq - sp.last_seq - 1
			if OS.has_environment("NET_DEBUG"): print("[GAP] %s tick=%d last=%d new=%d q=%d credit=%.1f" % [sp.nickname, tick, sp.last_seq, inp.seq, sp.input_queue.size(), sp.credit])
		sp.input_queue.append(inp)
		sp.last_seq = inp.seq
	# 대기열이 길면 오래된 입력을 버려 지연을 제한 (점프 입력은 다음 입력으로 이월)
	while sp.input_queue.size() > NetConfig.MAX_INPUT_QUEUE:
		var dropped: PlayerInput = sp.input_queue.pop_front()
		sp.ack = dropped.seq
		sp.dropped_inputs += 1
		if dropped.jump:
			sp.input_queue[0].jump = true


## 시간 예산 방식 입력 소비:
##  - 매 틱 credit +1 (최대 INPUT_CREDIT_MAX). 입력 1개 처리에 credit 1 소모.
##  - 네트워크 지터로 늦게 온 입력은 다음 틱에 몰아서 처리 → 클라이언트 예측과 정확히 일치.
##  - 평균 처리량은 틱레이트를 넘을 수 없으므로 입력을 많이 보내도 빨라지지 않는다.
##  - credit이 가득 찰 때까지(약 333ms) 입력이 없으면 직전 이동으로 외삽해 공중 정지(랙 스위치)를 막는다.
##    외삽은 최대 MAX_EXTRAPOLATE_TICKS까지만 (그 뒤로는 제자리, 중력만).
func _step_player(sp: ServerPlayer, delta: float) -> void:
	if sp.away_since_ms > 0:
		_simulate_one(sp, sp.last_move, delta)  # 끊긴 동안: 제자리에 멈춤 (중력·발판·낙하 판정만)
		return
	sp.credit = minf(sp.credit + 1.0, NetConfig.INPUT_CREDIT_MAX)
	var processed := 0
	while sp.input_queue.size() > 0 and sp.credit >= 1.0 and processed < NetConfig.MAX_INPUTS_PER_TICK:
		var input: PlayerInput = sp.input_queue.pop_front()
		sp.ack = input.seq
		sp.ack_tick = tick
		sp.last_move = input
		sp.credit -= 1.0
		processed += 1
		_simulate_one(sp, input, delta)
	if processed > 0:
		sp.extrapolated_run = 0
	elif sp.credit >= NetConfig.INPUT_CREDIT_MAX:
		# 입력이 계속 안 오면 (회선이 끊기는 중) 직전 이동을 무한히 이어 가지 않고 멈춘다 → 낭떠러지로 걸어가지 않게
		var extrapolated := sp.last_move.copy() if sp.extrapolated_run < NetConfig.MAX_EXTRAPOLATE_TICKS else PlayerInput.new()
		extrapolated.jump = false
		extrapolated.interact = false
		sp.credit -= 1.0
		sp.starved_ticks += 1
		sp.extrapolated_run += 1
		_simulate_one(sp, extrapolated, delta)


func _simulate_one(sp: ServerPlayer, input: PlayerInput, delta: float) -> void:
	var before := sp.body.global_position
	sp.body.simulate(input, delta, tick)
	var after := sp.body.global_position
	if sp.body.stun_time <= 0.0 and sp.body.boost_time <= 0.0 and sp.body.floor_mover < 0 and sp.body.shield_time <= 0.0:
		sp.max_speed = maxf(sp.max_speed, Vector2(after.x - before.x, after.z - before.z).length() / delta)
	if after.y < map.kill_height:
		var p := mode.on_fell(sp.peer_id)
		sp.body.teleport(mode.spectator_point() if p == Vector3.INF else p)
		sp.respawns += 1


func _send_snapshot() -> void:
	if players.is_empty():
		return
	var entries: Array = []
	for sp: ServerPlayer in players.values():
		entries.append({
			"id": sp.peer_id,
			"pos": sp.body.global_position,
			"vel": sp.body.velocity,
			"yaw": sp.body.facing_yaw,
			"air": sp.body.air_time,
			"stun": sp.body.stun_time,
			"boost": sp.body.boost_time,
			"jumpb": sp.body.jump_boost_time,
			"shield": sp.body.shield_time,
			"mover": sp.body.floor_mover,
			"flags": (SnapshotCodec.FLAG_GROUNDED if sp.body.is_on_floor() else 0) | (SnapshotCodec.FLAG_FROZEN if sp.body.frozen else 0) | (SnapshotCodec.FLAG_OUT if mode.is_out(sp.peer_id) else 0),
			"ack": sp.ack,
			"ack_tick": sp.ack_tick,
		})
	var packet := SnapshotCodec.encode(tick, entries)
	for sp: ServerPlayer in players.values():
		if not sp.kicked and sp.away_since_ms == 0 and Net.is_peer_active(sp.peer_id):
			Net.s_snapshot.rpc_id(sp.peer_id, packet)


func on_emote(peer_id: int, emote_id: Variant) -> void:
	if not players.has(peer_id):
		return
	if typeof(emote_id) != TYPE_INT or emote_id < 0 or emote_id >= Appearance.EMOTES.size():
		_violation(peer_id, "emote_id")
		return
	var sp: ServerPlayer = players[peer_id]
	if sp.away_since_ms > 0:
		return
	var now := Time.get_ticks_msec()
	if now < sp.next_emote_ms:
		return  # 쿨다운 중 (스팸 방지, 위반으로 치지는 않음)
	sp.next_emote_ms = now + NetConfig.EMOTE_COOLDOWN_MS
	for id in _active_ids():
		Net.s_emote.rpc_id(id, peer_id, emote_id)


# ------------------------------------------------------------------ 테스트/모니터링

func report() -> Dictionary:
	var plist: Array = []
	for sp: ServerPlayer in players.values():
		plist.append({
			"id": sp.peer_id,
			"nickname": sp.nickname,
			"auth_provider": sp.auth_provider,
			"appearance": sp.appearance,
			"kicked": sp.kicked,
			"pos": [snappedf(sp.body.global_position.x, 0.01), snappedf(sp.body.global_position.y, 0.01), snappedf(sp.body.global_position.z, 0.01)],
			"max_speed": snappedf(sp.max_speed, 0.001),
			"violations": sp.violations,
			"dropped_inputs": sp.dropped_inputs,
			"starved_ticks": sp.starved_ticks,
			"lost_inputs": sp.lost_inputs,
			"respawns": sp.respawns,
			"away": sp.away_since_ms > 0,
			"resumes": sp.resumes,
		})
	return {"tick": tick, "mode": mode_id, "phase": mode.phase, "rounds": rounds_completed, "last_results": mode.last_results, "players": plist, "stats": stats}


## 메시지를 받을 수 있는 (추방 처리 중이 아니고 연결이 살아 있는) 플레이어 목록
func _active_ids() -> Array[int]:
	var out: Array[int] = []
	for sp: ServerPlayer in players.values():
		if not sp.kicked and sp.away_since_ms == 0 and Net.is_peer_active(sp.peer_id):
			out.append(sp.peer_id)
	return out


# ------------------------------------------------------------------ Firestore (서버 전용 기록)

func _setup_data(cfg: FirebaseConfig) -> void:
	if service_account_path == "":
		push_warning("[SERVER] no service account (--service-account / GOOGLE_APPLICATION_CREDENTIALS) → Firestore disabled (profiles not loaded, stats not saved)")
		return
	_sa = ServiceAccountAuth.new()
	_sa.name = "ServiceAccount"
	add_child(_sa)
	var err := _sa.load_key_file(service_account_path)
	if err != "":
		push_error("[SERVER] " + err + " → Firestore disabled")
		_sa.queue_free()
		_sa = null
		return
	if _sa.project_id != "" and _sa.project_id != cfg.project_id:
		push_error("[SERVER] service account project (%s) != firebase project (%s) → Firestore disabled" % [_sa.project_id, cfg.project_id])
		return
	data_fs = FirestoreClient.new()
	data_fs.name = "Firestore"
	add_child(data_fs)
	data_fs.setup(cfg.project_id, _sa.get_access_token, cfg.firestore_base_url)
	print("[SERVER] Firestore enabled (service account %s)" % _sa.client_email)


## 퇴장 시 플레이 기록 누적 (원자적 증가). 실패해도 게임 진행에는 영향 없음.
func _record_session(sp: ServerPlayer) -> void:
	if data_fs == null or sp.uid == "" or sp.uid.begins_with("dev:"):
		return
	var secs := maxi(0, int((Time.get_ticks_msec() - sp.joined_ms) / 1000))
	var r: Dictionary = await data_fs.increment("stats/" + sp.uid, {"sessions": 1, "playSeconds": secs}, ["lastSeen"])
	if r["ok"]:
		stats["stats_written"] += 1
	else:
		stats["data_errors"] += 1
		push_warning("[SERVER] stats write failed for %s: %s" % [sp.uid, r["error"]])


# ------------------------------------------------------------------ 게임 모드 연동 (GameMode가 호출)

func get_player_pos(peer_id: int) -> Vector3:
	var sp: ServerPlayer = players.get(peer_id)
	return sp.body.global_position if sp else Vector3.ZERO


func teleport_player(peer_id: int, pos: Vector3) -> void:
	var sp: ServerPlayer = players.get(peer_id)
	if sp:
		sp.body.teleport(pos)


## 다른 서버(로비/미니게임)로 이동시킨다. 클라이언트가 스스로 접속을 끊고 새 주소로 다시 접속.
func transfer_player(peer_id: int, route: String, target: String) -> void:
	if not players.has(peer_id) or players[peer_id].away_since_ms > 0 or not Net.is_peer_active(peer_id):
		return
	players[peer_id].leaving = true  # 클라이언트가 곧 끊고 다른 서버로 감 → 자리를 남기지 않음
	print("[SERVER] transfer %d (%s) -> %s [%s]" % [peer_id, players[peer_id].nickname, route, target])
	Net.s_transfer.rpc_id(peer_id, route, target)


func transfer_all(route: String, target: String) -> void:
	for sp: ServerPlayer in players.values():
		if sp.away_since_ms > 0 and not sp.kicked:
			sp.pending_transfer = [route, target]  # 끊긴 사람은 돌아오면 바로 이동
	for id in _active_ids():
		transfer_player(id, route, target)


## 아이템 효과 적용 (모드가 획득을 판정한 뒤 호출). kind: speed / jump / shield, secs: 지속 시간
func give_item(peer_id: int, kind: String, secs: float) -> void:
	if not players.has(peer_id):
		return
	_apply_item(players[peer_id].body, kind, secs)


static func _apply_item(body: PlayerBody, kind: String, secs: float) -> void:
	match kind:
		"speed":
			body.boost_time = maxf(body.boost_time, secs)
		"jump":
			body.jump_boost_time = maxf(body.jump_boost_time, secs)
		"shield":
			body.shield_time = maxf(body.shield_time, secs)


func notify_player(peer_id: int, text: String) -> void:
	var sp: ServerPlayer = players.get(peer_id)
	if sp and sp.away_since_ms > 0:
		return
	if Net.is_peer_active(peer_id):
		Net.s_notice.rpc_id(peer_id, text)


func _broadcast_mode_state() -> void:
	var state := mode.public_state()
	mode.dirty = false
	for id in _active_ids():
		Net.s_mode_state.rpc_id(id, state)


## 라운드 종료: 결과 로그 + Firestore 기록 (경기 수, 승리, 경험치, 모드별 플레이 수)
func _on_round_finished(results: Array) -> void:
	rounds_completed += 1
	print("[SERVER] ROUND_RESULTS " + JSON.stringify(results))
	_broadcast_mode_state()
	if data_fs == null:
		return
	for r in results:
		var sp: ServerPlayer = players.get(int(r["peer_id"]))
		if sp == null or sp.uid.begins_with("dev:"):
			continue
		var inc := {"matches": 1, "xp": int(r["xp"]), "plays_" + mode_id: 1}
		if r["win"]:
			inc["wins"] = 1
		var w: Dictionary = await data_fs.increment("stats/" + sp.uid, inc, ["lastMatch"])
		stats["stats_written" if w["ok"] else "data_errors"] += 1
