class_name LocalPlayerController
extends Node
## 로컬 플레이어 제어: 입력 수집 → 즉시 예측 이동 → 서버 전송 → 서버 스냅샷으로 보정(재조정).
##
## 클라이언트 예측(Client-side prediction):
##   매 틱 입력을 만들어 바로 simulate()하고, (seq, 입력, 예측 위치)를 history에 저장한다.
## 서버 보정(Reconciliation):
##   스냅샷의 ack(서버가 마지막으로 처리한 seq)와 서버 위치를 받아, 같은 seq의 예측 위치와 비교한다.
##   오차가 크면 서버 상태로 되돌린 뒤 아직 서버가 처리하지 않은 입력을 다시 시뮬레이션한다.

const CORRECTION_EPSILON := 0.05
## 점프 입력 여유: PlayerBody.JUMP_HOLD_TICKS 동안 점프 입력을 유지 (입력에 담기므로 서버·예측 결과 동일)
const JUMP_HOLD_TICKS := PlayerBody.JUMP_HOLD_TICKS
const MAX_HISTORY := 240
const BOT_MODES: Array[String] = ["walker", "cheat", "flood", "objective"]

var body: PlayerBody
var camera: ThirdPersonCamera
var map: GameMap
var online := false
var bot_mode := ""
## 모바일 가상 조이스틱 등 외부 입력원 (Phase 3). 값이 있으면 키보드 입력과 합산.
var external_move := Vector2.ZERO
var external_jump := false
var _jump_hold := 0
## 보정 직후 모습(CharacterVisual)에 남겨 두는 오프셋 → 빠르게 0으로 줄어든다
var _smooth_offset := Vector3.ZERO
var _visual: Node3D

var seq := 0
var history: Array = []   # [{seq:int, input:PlayerInput, pos:Vector3, wt:int}]
## 서버가 입력 seq를 처리하는 서버 틱 = seq + tick_offset (스냅샷의 ack_tick으로 보정)
var tick_offset := 0
var _offset_valid := false
## 봇 목표 지점 제공 (objective 봇): func(pos) -> Vector3 (INF면 배회)
var bot_target_fn: Callable
## 오프라인 낙하 시 리스폰 위치 제공: func() -> Vector3
var fell_handler: Callable
var _stuck_ticks := 0
var _pending_snapshot := {}

# 검증/디버그 통계
var corrections := 0
## 5cm~3m 오차 (진짜 예측 오류). 3m 초과는 서버의 순간이동(출발선 정렬, 리스폰)으로 따로 센다
var small_corrections := 0
var teleports := 0
var max_small_correction := 0.0
var max_correction := 0.0
var distance_moved := 0.0

var _bot_time := 0.0


func _process(delta: float) -> void:
	if _smooth_offset == Vector3.ZERO or body == null:
		return
	if _visual == null:
		for c in body.get_children():
			if c is CharacterVisual:
				_visual = c
	_smooth_offset = _smooth_offset.lerp(Vector3.ZERO, 1.0 - exp(-28.0 * delta))
	if _smooth_offset.length() < 0.005:
		_smooth_offset = Vector3.ZERO
	if _visual:
		_visual.position = _smooth_offset


func _physics_process(delta: float) -> void:
	# 보정은 반드시 물리 프레임 안에서: move_and_slide()는 물리 프레임 밖에서 호출되면
	# 렌더 프레임 시간(예: 7ms)을 써서 재시뮬레이션 거리가 틀어진다 (통합 테스트로 발견한 버그).
	if not _pending_snapshot.is_empty():
		var e := _pending_snapshot
		_pending_snapshot = {}
		_reconcile_now(e)
	var input := _gather_input(delta)
	seq += 1
	input.seq = seq

	var wt := world_tick_for(seq)
	if map:
		map.update_world(wt)
	var before := body.global_position
	body.simulate(input, delta, wt)
	distance_moved += Vector2(body.global_position.x - before.x, body.global_position.z - before.z).length()

	if online:
		history.append({"seq": seq, "input": input, "pos": body.global_position, "wt": wt})
		if history.size() > MAX_HISTORY:
			history.pop_front()
		_send_inputs()
	elif map and body.global_position.y < map.kill_height:
		# 오프라인: 게임 모드 규칙으로 리스폰 위치 결정 (체크포인트 등), 없으면 스폰 지점
		body.teleport(fell_handler.call() if fell_handler.is_valid() else map.get_spawn_point(0))


func _gather_input(delta: float) -> PlayerInput:
	var inp := PlayerInput.new()
	if bot_mode == "objective":
		return _objective_input()
	if bot_mode != "":
		_bot_time += delta
		inp.set_move(Vector2(cos(_bot_time * 0.7), sin(_bot_time * 0.7)))
		inp.jump = (seq % 90) == 45
		if bot_mode == "cheat":
			inp.move_x = 127  # 길이 √2 짜리 위조 입력 — 서버/예측 모두 get_move()에서 1로 제한됨
			inp.move_z = 127
		return inp

	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	v = (v + external_move).limit_length(1.0)
	if Input.is_action_pressed("walk"):
		v *= 0.5
	var cam_yaw := camera.yaw if camera else 0.0
	inp.set_move(v.rotated(-cam_yaw))
	if Input.is_action_just_pressed("jump") or external_jump:
		_jump_hold = JUMP_HOLD_TICKS
	inp.jump = _jump_hold > 0
	_jump_hold = maxi(_jump_hold - 1, 0)
	if inp.jump and body and body.velocity.y > 2.0:
		_jump_hold = 0  # 이미 뛰어올랐으면 남은 유지 입력은 버린다
	inp.interact = Input.is_action_just_pressed("interact")
	external_jump = false
	return inp


func _send_inputs() -> void:
	var n := mini(NetConfig.INPUT_REDUNDANCY, history.size())
	var inputs: Array = []
	for i in range(history.size() - n, history.size()):
		inputs.append(history[i]["input"])
	var packet := InputCodec.encode(inputs)
	Net.c_input.rpc_id(1, packet)

	match bot_mode:
		"flood":
			for i in 6:
				Net.c_input.rpc_id(1, packet)
		"cheat":
			if seq % 10 == 0:
				Net.c_input.rpc_id(1, PackedByteArray([255, 1, 2, 3]))        # 형식 위반
				var forged := PlayerInput.new()
				forged.seq = seq + 100000                                      # seq 위조
				Net.c_input.rpc_id(1, InputCodec.encode([forged]))
				Net.c_input.rpc_id(1, "not a packet")                          # 타입 위반
				Net.c_emote.rpc_id(1, 999)                                     # 범위 위반


## 서버 스냅샷 중 내 항목: 다음 물리 프레임에서 처리하도록 보관 (최신 것만 의미 있음)
func reconcile(e: Dictionary) -> void:
	_pending_snapshot = e


## 예측 결과를 검증/보정한다 (물리 프레임 안에서만 호출).
func _reconcile_now(e: Dictionary) -> void:
	var ack: int = e["ack"]
	if ack == 0:
		return
	# 서버 처리 틱과 seq의 차이로 장애물 예측 틱을 보정 (±2틱 지터는 무시해 떨림 방지)
	var sample: int = int(e.get("ack_tick", 0)) - ack
	if e.get("ack_tick", 0) > 0 and (not _offset_valid or absi(sample - tick_offset) > 2):
		tick_offset = sample
		_offset_valid = true
		for h in history:
			h["wt"] = world_tick_for(h["seq"])
	while history.size() > 0 and history[0]["seq"] < ack:
		history.pop_front()
	var server_pos: Vector3 = e["pos"]
	var err := INF
	if history.size() > 0 and history[0]["seq"] == ack:
		err = (history[0]["pos"] as Vector3).distance_to(server_pos)
		history.pop_front()
	if err <= CORRECTION_EPSILON:
		return

	corrections += 1
	if err != INF:
		max_correction = maxf(max_correction, err)
	if err > 3.0:
		teleports += 1
	else:
		small_corrections += 1
		max_small_correction = maxf(max_small_correction, err)
	var shown_before := body.global_position
	body.global_position = server_pos
	body.velocity = e["vel"]
	body.air_time = e["air"]
	body.stun_time = e.get("stun", 0.0)
	body.boost_time = e.get("boost", 0.0)
	body.jump_boost_time = e.get("jumpb", 0.0)
	body.shield_time = e.get("shield", 0.0)
	body.floor_mover = e.get("mover", -1)
	var dt := 1.0 / Engine.physics_ticks_per_second
	for h in history:
		if map:
			map.update_world(h["wt"])
		body.simulate(h["input"], dt, h["wt"])
		h["pos"] = body.global_position
	if err > 2.0:
		body.reset_physics_interpolation()
	else:
		# 작은 보정은 순간이동처럼 튀지 않게: 모습만 이전 자리에서 0.1초 동안 따라오게 한다
		_smooth_offset += shown_before - body.global_position
		if _smooth_offset.length() > 1.5:
			_smooth_offset = Vector3.ZERO


## 이 입력이 서버에서 처리될 것으로 예상되는 서버 틱 (오프라인은 로컬 틱)
func world_tick_for(s: int) -> int:
	return s + tick_offset if online else s


## 테스트/AI 봇: 맵이 알려주는 목표(체크포인트·발판·코인·포털)로 이동. 막히면 점프.
func _objective_input() -> PlayerInput:
	var inp := PlayerInput.new()
	var target: Vector3 = bot_target_fn.call(body.global_position) if bot_target_fn.is_valid() else Vector3.INF
	if target == Vector3.INF:
		return inp
	var to := Vector2(target.x - body.global_position.x, target.z - body.global_position.z)
	if to.length() > 0.6:
		inp.set_move(to.normalized())
	var hs := Vector2(body.velocity.x, body.velocity.z).length()
	_stuck_ticks = _stuck_ticks + 1 if (to.length() > 0.6 and hs < 1.5 and body.stun_time <= 0.0) else 0
	# 목표가 높이 있거나, 막혔거나, 주기적으로 점프 (구멍/턱 넘기)
	var near := to.length() < 1.5
	inp.jump = _stuck_ticks > 8 or target.y - body.global_position.y > 0.8 or (seq % 40 == 0 and not near)
	# 장애물 피하기 (굴러오는 공은 점프, 튀어나올 벽 앞에서는 기다림)
	if map and to.length() > 0.6:
		var hint := map.bot_hint(body.global_position, Vector3(to.x, 0, to.y).normalized(), world_tick_for(seq + 1))
		if hint == 1:
			inp.jump = true
		elif hint == 2:
			inp.set_move(Vector2.ZERO)
			inp.jump = false
			_stuck_ticks = 0
	return inp
