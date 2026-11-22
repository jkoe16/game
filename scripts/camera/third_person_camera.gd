class_name ThirdPersonCamera
extends Node3D
## 3인칭 카메라: 부드러운 추적, 마우스/터치 회전, 휠 줌, SpringArm3D 벽 충돌 방지,
## 점프 시 수직 추적 지연, 이동 중 조작이 없으면 캐릭터 뒤로 천천히 복귀.

const PIVOT_HEIGHT := 1.3
const MIN_DISTANCE := 2.5
const MAX_DISTANCE := 10.0
const PITCH_MIN := -1.25
const PITCH_MAX := 0.45

@export var mouse_sensitivity := 0.0028
@export var touch_sensitivity := 0.006
@export var auto_recenter_delay := 1.6

var target: PlayerBody
var yaw := 0.0
var pitch := -0.32
var distance := 6.0
var spring: SpringArm3D
var camera: Camera3D

var _target_distance := 6.0
var _follow := Vector3.ZERO
var _idle_input_time := 0.0
var _snapped := false


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	spring = SpringArm3D.new()
	spring.collision_mask = 1  # 월드만 (플레이어는 무시)
	spring.margin = 0.25
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	spring.shape = probe
	spring.spring_length = distance
	add_child(spring)
	camera = Camera3D.new()
	camera.fov = 68.0
	camera.far = 400.0
	spring.add_child(camera)
	camera.current = true


func _process(delta: float) -> void:
	if target == null:
		return
	var tp := target.get_global_transform_interpolated().origin + Vector3(0, PIVOT_HEIGHT, 0)
	if not _snapped or _follow.distance_to(tp) > 15.0:
		_follow = tp
		_snapped = true
	# 수평은 빠르게, 수직은 느리게 따라가 점프할 때 화면이 덜 흔들린다
	var kxz := 1.0 - exp(-20.0 * delta)
	var ky := 1.0 - exp(-7.0 * delta)
	_follow.x = lerpf(_follow.x, tp.x, kxz)
	_follow.z = lerpf(_follow.z, tp.z, kxz)
	_follow.y = lerpf(_follow.y, tp.y, ky)
	global_position = _follow

	_idle_input_time += delta
	var moving := Vector2(target.velocity.x, target.velocity.z).length() > 1.0
	if moving and _idle_input_time > auto_recenter_delay:
		yaw = lerp_angle(yaw, target.facing_yaw + PI, 1.0 - exp(-1.2 * delta))

	distance = lerpf(distance, _target_distance, 1.0 - exp(-10.0 * delta))
	spring.spring_length = distance
	spring.rotation = Vector3(pitch, yaw, 0.0)


func rotate_by(delta_px: Vector2, sensitivity: float) -> void:
	yaw -= delta_px.x * sensitivity
	pitch = clampf(pitch - delta_px.y * sensitivity, PITCH_MIN, PITCH_MAX)
	_idle_input_time = 0.0


func zoom(step: float) -> void:
	_target_distance = clampf(_target_distance + step, MIN_DISTANCE, MAX_DISTANCE)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_by(event.relative, mouse_sensitivity)
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				zoom(-0.6)
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom(0.6)
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				if not DisplayServer.is_touchscreen_available():
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
