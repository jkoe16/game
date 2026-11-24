class_name PlayerBody
extends CharacterBody3D
## 플레이어 물리 몸체. 서버(권한 시뮬레이션)와 클라이언트(예측)가 "같은 코드"로 이동을 계산한다.
## simulate()는 입력 하나 = 물리 틱 하나. 이 함수의 결과가 곧 게임 규칙이다.
## 미니게임 요소(회전 막대 넉백, 이동 발판, 부스트/점프 패드)는 world(GameMap)가 틱 번호로
## 결정론적으로 계산하므로 서버와 클라이언트 예측 결과가 같다.

const WALK_SPEED := 6.5
const ACCEL_GROUND := 50.0
const DECEL_GROUND := 60.0
const ACCEL_AIR := 18.0
const STUN_FRICTION := 4.0
const GRAVITY := 26.0
const MAX_FALL_SPEED := 40.0
const JUMP_VELOCITY := 10.0
const COYOTE_TIME := 0.1
## 착지 직전에 누른 점프도 인정 (0.12초): 처음 하는 사람도 점프 타이밍이 덜 억울하다
const JUMP_BUFFER := 0.12
const TURN_SPEED := 14.0
const STEP_HEIGHT := 0.35
const BOOST_MULT := 1.6

var peer_id := 0
var air_time := 0.0
var jump_buffer := 0.0
var facing_yaw := 0.0
## 넘어짐(넉백) 남은 시간: 이 동안 조작 불가
var stun_time := 0.0
## 부스트 남은 시간: 최고 속도 BOOST_MULT배
var boost_time := 0.0
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
	if input.jump:
		jump_buffer = JUMP_BUFFER
	var want_jump := jump_buffer > 0.0
	jump_buffer = maxf(jump_buffer - delta, 0.0)
	if frozen or stun_time > 0.0:
		move = Vector2.ZERO
		want_jump = false
		jump_buffer = 0.0
	stun_time = maxf(stun_time - delta, 0.0)
	boost_time = maxf(boost_time - delta, 0.0)
	var on_floor := is_on_floor()

	var horiz := Vector2(velocity.x, velocity.z)
	var accel: float
	if stun_time > 0.0:
		accel = STUN_FRICTION
	elif on_floor:
		accel = ACCEL_GROUND if move.length_squared() > 0.0001 else DECEL_GROUND
	else:
		accel = ACCEL_AIR
	var top_speed := WALK_SPEED * (BOOST_MULT if boost_time > 0.0 else 1.0)
	if horiz.length() > top_speed and stun_time <= 0.0 and on_floor:
		horiz = horiz.limit_length(maxf(top_speed, horiz.length() - DECEL_GROUND * delta))
	else:
		horiz = horiz.move_toward(move * top_speed, accel * delta)

	var vy := velocity.y
	if on_floor:
		air_time = 0.0
		if vy < 0.0:
			vy = 0.0
	else:
		air_time += delta
		vy = maxf(vy - GRAVITY * delta, -MAX_FALL_SPEED)

	if want_jump and air_time <= COYOTE_TIME:
		vy = JUMP_VELOCITY
		air_time = COYOTE_TIME + 0.001  # 코요테 구간 소진 → 공중 2단 점프 불가
		jump_buffer = 0.0

	if move.length_squared() > 0.0004:
		facing_yaw = lerp_angle(facing_yaw, atan2(move.x, move.y), 1.0 - exp(-TURN_SPEED * delta))

	velocity = Vector3(horiz.x, vy, horiz.y)
	var start := global_position
	var desired := Vector3(horiz.x, 0.0, horiz.y) * delta
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
	velocity = impulse
	stun_time = maxf(stun_time, stun)
	air_time = COYOTE_TIME + 0.001


func teleport(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	air_time = 0.0
	stun_time = 0.0
	boost_time = 0.0
	floor_mover = -1
	reset_physics_interpolation()
