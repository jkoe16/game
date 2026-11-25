class_name PlayerBody
extends CharacterBody3D
## 플레이어 물리 몸체. 서버(권한 시뮬레이션)와 클라이언트(예측)가 "같은 코드"로 이동을 계산한다.
## simulate()는 입력 하나 = 물리 틱 하나. 이 함수의 결과가 곧 게임 규칙이다.
## 미니게임 요소(회전 막대 넉백, 이동 발판, 부스트/점프 패드)는 world(GameMap)가 틱 번호로
## 결정론적으로 계산하므로 서버와 클라이언트 예측 결과가 같다.

const WALK_SPEED := 6.5
const ACCEL_GROUND := 60.0
## 멈출 때·반대로 돌 때 감속 (높을수록 얼음 위처럼 미끄러지지 않고 딱 선다)
const DECEL_GROUND := 120.0
## 키를 뗐을 때 감속 (260이면 걷던 속도에서 약 0.08m, 0.025초 만에 선다)
const DECEL_STOP := 260.0
const ACCEL_AIR := 18.0
const STUN_FRICTION := 4.0
const GRAVITY := 26.0
const MAX_FALL_SPEED := 40.0
const JUMP_VELOCITY := 10.0
const COYOTE_TIME := 0.1
## 점프 입력 여유: 컨트롤러가 점프를 누른 뒤 이 틱 수(≈0.12초) 동안 점프 입력을 유지 → 착지 직전 입력도 인정
const JUMP_HOLD_TICKS := 7
const STEP_HEIGHT := 0.35
const BOOST_MULT := 1.6

var peer_id := 0
var air_time := 0.0
var facing_yaw := 0.0
## 넘어짐(넉백) 남은 시간: 이 동안 조작 불가
var stun_time := 0.0
## 부스트 남은 시간: 최고 속도 BOOST_MULT배
var boost_time := 0.0
## 아이템: 점프 강화 / 보호막(넘어지지 않음) 남은 시간 (서버 스냅샷으로 동기화)
var jump_boost_time := 0.0
var shield_time := 0.0
const JUMP_BOOST_MULT := 1.3
## 카운트다운 등에서 이동 금지 (모드가 설정)
var frozen := false
## 서 있는 이동 발판 번호 (-1 = 없음). 다음 틱에 발판 이동량만큼 함께 움직인다.
var floor_mover := -1
## 미니게임 월드 (없으면 기본 이동만)
var world: GameMap


func _ready() -> void:
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(46.0)
	floor_constant_speed = true
	# 엔진 내장 "움직이는 발판 따라가기"는 끈다 → GameMap.pre_move의 틱 기반(결정론적) 탑승만 사용
	platform_floor_layers = 0
	platform_wall_layers = 0


func simulate(input: PlayerInput, delta: float, world_tick := 0) -> void:
	if world:
		world.pre_move(self, world_tick)

	var move := input.get_move()
	# 점프 입력 여유(착지 직전 입력 인정)는 입력 쪽(LocalPlayerController)에서 처리한다.
	# 여기에 숨은 상태를 두면 서버 보정 후 다시 계산할 때 결과가 달라져 캐릭터가 미끄러진다.
	var want_jump := input.jump
	if frozen or stun_time > 0.0:
		move = Vector2.ZERO
		want_jump = false
	stun_time = maxf(stun_time - delta, 0.0)
	boost_time = maxf(boost_time - delta, 0.0)
	jump_boost_time = maxf(jump_boost_time - delta, 0.0)
	shield_time = maxf(shield_time - delta, 0.0)
	var on_floor := is_on_floor()

	var horiz := Vector2(velocity.x, velocity.z)
	var moving := move.length_squared() > 0.0001
	var top_speed := WALK_SPEED * (BOOST_MULT if boost_time > 0.0 else 1.0)
	# 최고 속도를 넘은 경우(부스트 끝 등)에만 최고 속도까지 감속. 0.05 여유를 두지 않으면 6.5000001 같은
	# 부동소수 오차로 이 분기에 걸려 속도가 6.5에 묶인 채 키를 떼도 영원히 미끄러졌다(대각선 방향에서 자주).
	# 키를 뗐으면 이 분기 대신 아래 정지 감속을 쓴다.
	if horiz.length() > top_speed + 0.05 and stun_time <= 0.0 and on_floor and moving:
		horiz = horiz.limit_length(maxf(top_speed, horiz.length() - DECEL_GROUND * delta))
	elif stun_time > 0.0:
		horiz = horiz.move_toward(move * top_speed, STUN_FRICTION * delta)
	elif on_floor and moving:
		# 입력 방향 성분과 옆 성분을 따로 처리: 옆으로 흐르는 속도는 브레이크처럼 빠르게 없애고
		# 입력 방향으로는 가속 → 90° 꺾을 때도 비스듬히 미끄러지거나 속도가 푹 꺼지지 않는다.
		var dir := move.normalized()
		var along := horiz.dot(dir)
		var side := (horiz - dir * along).move_toward(Vector2.ZERO, DECEL_GROUND * delta)
		# 반대쪽으로 움직이던 중이면 0이 될 때까지 브레이크 감속
		along = move_toward(along, move.length() * top_speed, (ACCEL_GROUND if along >= 0.0 else DECEL_GROUND) * delta)
		horiz = dir * along + side
	else:
		horiz = horiz.move_toward(move * top_speed, (DECEL_STOP if on_floor else ACCEL_AIR) * delta)

	var vy := velocity.y
	if on_floor:
		air_time = 0.0
		if vy < 0.0:
			vy = 0.0
	else:
		air_time += delta
		vy = maxf(vy - GRAVITY * delta, -MAX_FALL_SPEED)

	if want_jump and air_time <= COYOTE_TIME:
		vy = JUMP_VELOCITY * (JUMP_BOOST_MULT if jump_boost_time > 0.0 else 1.0)
		air_time = COYOTE_TIME + 0.001  # 코요테 구간 소진 → 공중 2단 점프 불가

	# 바라보는 방향은 입력 방향 그대로. 부드럽게 도는 건 CharacterVisual이 한 번만 처리한다
	# (여기서도 보간하면 두 번 늦어져 몸이 굼뜨게 돈다).
	if move.length_squared() > 0.0004:
		facing_yaw = atan2(move.x, move.y)

	velocity = Vector3(horiz.x, vy, horiz.y)
	var start := global_position
	var desired := Vector3(horiz.x, 0.0, horiz.y) * delta
	# 경사에서 같은 속도(floor_constant_speed)는 이미 바닥에 있을 때만. 착지하는 틱에 켜 두면
	# 떨어지던 세로 이동량이 바닥을 따라 가로 이동으로 바뀌어 착지 순간 앞으로 툭 밀린다(최고 속도 초과).
	floor_constant_speed = on_floor
	move_and_slide()
	if on_floor and vy <= 0.0 and is_on_wall():
		var moved := global_position - start
		moved.y = 0.0
		var remaining := desired.length() - moved.length()
		if remaining > 0.001 and _try_step_up(desired.normalized() * remaining):
			# 턱에 막혀 잃은 수평 속도를 복원해 계단에서 속도가 줄지 않게 함
			velocity.x = horiz.x
			velocity.z = horiz.y

	if world:
		world.post_move(self, world_tick)


## CharacterBody3D에는 계단 오르기가 없으므로 직접 처리: 위로 → 앞으로 → 아래로 테스트 이동.
## 바닥에 서 있을 때만 동작 (공중에서 턱을 붙잡는 동작은 허용하지 않음).
## 캡슐이 턱 모서리에 걸쳐 착지해도(경사진 법선) 높이만 올라가면 허용 → 다음 틱에 자연스럽게 넘어간다.
func _try_step_up(motion: Vector3) -> bool:
	var t := global_transform
	var lift := Vector3(0, STEP_HEIGHT, 0)
	if test_move(t, lift):
		return false
	var raised := t.translated(lift)
	if test_move(raised, motion):
		return false  # 턱보다 높은 벽
	var ahead := raised.translated(motion)
	var col := KinematicCollision3D.new()
	if not test_move(ahead, -lift, col):
		return false  # 아래에 디딜 곳이 없음 (절벽)
	var landing := ahead.origin + col.get_travel()
	var rise := landing.y - t.origin.y
	if rise < 0.005 or rise > STEP_HEIGHT:
		return false
	global_position = landing
	return true


## 넉백: 서버·클라이언트가 같은 조건에서 호출 (GameMap.post_move)
func knock(impulse: Vector3, stun: float) -> void:
	if shield_time > 0.0 and stun > 0.0:
		return  # 보호막: 장애물에 맞아도 넘어지지 않음 (점프 패드 같은 stun 0 은 그대로)
	velocity = impulse
	stun_time = maxf(stun_time, stun)
	air_time = COYOTE_TIME + 0.001


func teleport(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	air_time = 0.0
	stun_time = 0.0
	boost_time = 0.0
	jump_boost_time = 0.0
	shield_time = 0.0
	floor_mover = -1
	reset_physics_interpolation()
