class_name SurvivalArenaMap
extends GameMap
## 최후의 생존자 "무너지는 섬": 가운데 원판(끝까지 남음) + 바깥 두 줄의 타일.
## 라운드가 시작되면 30초부터 바깥 타일이, 75초부터 안쪽 타일 절반이 하나씩 흔들리다(2.5초 경고) 떨어진다.
## 회전 막대 2개(낮은 막대는 점프, 높은 막대는 점프 금지).
## 타일 상태는 crumble_start(라운드 시작 틱) + 틱으로 결정 → 서버·클라이언트가 같은 계산.

const ARENA_RADIUS := 11.0
const CORE_RADIUS := 5.0
const WARN_SEC := 2.5
const TILE_A := Color(1.0, 0.78, 0.88)
const TILE_B := Color(0.86, 0.78, 1.0)

## 무너짐이 시작된 라운드 시작 틱 (0 = 무너지지 않음). 모드가 정하고 상태로 공유
var crumble_start := 0
var tiles: Array[Dictionary] = []   # {body, shape, mesh, base, fall_at, fallen}


func _ready() -> void:
	map_id = "survival_arena"
	display_name = "무너지는 섬"
	kill_height = -12.0
	setup_environment(Color(0.55, 0.45, 0.9), Color(1.0, 0.8, 0.85), Vector3(-60, -30, 0))
	add_cylinder(Vector3(0, -1, 0), CORE_RADIUS, 2.0, Color(1.0, 0.86, 0.92), true, 48)
	_build_ring(CORE_RADIUS, 8.0, 12, 75.0, 4.0, true)
	_build_ring(8.0, ARENA_RADIUS, 16, 30.0, 2.6, false)
	add_cylinder(Vector3(0, 1.5, 0), 0.9, 3.0, Color(0.95, 0.85, 0.3))  # 가운데 기둥 (서 있을 수 없음)
	add_sweeper(Vector3.ZERO, ARENA_RADIUS + 0.5, 0.5, 55.0, 0.0, 5.0, 2, 0.45, Color(1.0, 0.4, 0.4))
	add_sweeper(Vector3.ZERO, ARENA_RADIUS + 0.5, 2.4, -35.0, 90.0, -3.0, 1, 0.45, Color(0.4, 0.6, 1.0))

	# 관전석
	add_box(Vector3(0, 8, -20), Vector3(10, 1, 5), Color(0.8, 0.8, 0.9))
	add_box(Vector3(0, 9, -17.6), Vector3(10, 1.2, 0.3), Color(0.8, 0.8, 0.9))
	add_label(Vector3(0, 11, -20), "관전석", 64)

	for i in 8:
		var a := TAU * i / 8.0 + 0.2
		spawn_points.append(Vector3(sin(a) * 6.5, 0.5, cos(a) * 6.5))
	for i in 4:  # 가운데 원판 위 아이템 (보호막으로 막대 버티기, 점프 강화로 높은 막대 넘기)
		var a := TAU * (i + 0.5) / 4.0
		item_spawns.append(Vector3(sin(a) * 3.2, 1.2, cos(a) * 3.2))
	_decorate()
	_build_wind_fx()


## 링 하나를 count개 타일로. 정해진 순서로 first_sec부터 gap초 간격으로 떨어진다. half면 절반만 떨어짐
func _build_ring(r_in: float, r_out: float, count: int, first_sec: float, gap: float, half: bool) -> void:
	var mid := (r_in + r_out) * 0.5
	var width := TAU * r_out / count * 1.04
	var order := 0
	for k in count:
		var i := (k * 7) % count  # 고정된 섞인 순서 (매 판 같음 → 익히면 유리)
		var a := TAU * (i + 0.5) / count
		var pos := Vector3(sin(a) * mid, -1.0, cos(a) * mid)
		var falls := not half or k % 2 == 0
		var body := add_box(pos, Vector3(width, 2.0, r_out - r_in), TILE_A if i % 2 == 0 else TILE_B, Vector3(0, rad_to_deg(a), 0))
		body.set_meta("dynamic", true)
		var shape: CollisionShape3D = null
		var mesh: MeshInstance3D = null
		for c in body.get_children():
			if c is CollisionShape3D:
				shape = c
			elif c is MeshInstance3D:
				mesh = c
		tiles.append({"body": body, "shape": shape, "mesh": mesh, "base": pos,
			"fall_at": first_sec + gap * order if falls else INF, "fallen": false})
		if falls:
			order += 1


func update_world(tick: int) -> void:
	super.update_world(tick)
	if _wind_fx:
		var w := gust_at(tick)
		_wind_fx.emitting = w != Vector3.ZERO
		if w != Vector3.ZERO:
			_wind_fx.direction = w.normalized()
	var t := (tick - crumble_start) / 60.0 if crumble_start > 0 else -INF
	for tl in tiles:
		var fall_at: float = tl["fall_at"]
		var fallen := t >= fall_at
		if fallen != tl["fallen"]:
			tl["fallen"] = fallen
			var cs: CollisionShape3D = tl["shape"]
			cs.set_deferred("disabled", fallen)
			cs.disabled = fallen
		if is_headless:
			continue
		var body: Node3D = tl["body"]
		var base: Vector3 = tl["base"]
		var mi: MeshInstance3D = tl["mesh"]
		if fallen:
			var ft := t - fall_at
			body.position = base + Vector3(0, -6.0 * ft * ft, 0)
			body.visible = ft < 3.0
		elif t >= fall_at - WARN_SEC:
			# 경고: 흔들리며 빨갛게
			var w := (t - (fall_at - WARN_SEC)) / WARN_SEC
			body.position = base + Vector3(sin(t * 40.0) * 0.06 * w, 0, cos(t * 33.0) * 0.06 * w)
			body.visible = true
			mi.material_override = toon_material(Color(1.0, 0.45, 0.45) if int(t * 6.0) % 2 == 0 else Color(1.0, 0.8, 0.5))
		else:
			body.position = base
			body.visible = true
			mi.material_override = toon_material(TILE_A if tiles.find(tl) % 2 == 0 else TILE_B)


# ---------------------------------------------------------------- 밀어내는 바람
## 40초부터 18초마다 3초 동안 한 방향으로 돌풍 (초속 2.6m 밀림, 걸어서 버틸 수 있음). 방향은 매번 바뀐다
const GUST_FIRST := 40.0
const GUST_EVERY := 18.0
const GUST_LEN := 3.0
const GUST_SPEED := 2.6
var _wind_fx: CPUParticles3D


## 해당 틱의 바람 (초속 벡터, 없으면 ZERO). 서버·클라이언트 같은 계산
func gust_at(tick: int) -> Vector3:
	if crumble_start <= 0:
		return Vector3.ZERO
	var t := (tick - crumble_start) / 60.0 - GUST_FIRST
	if t < 0.0:
		return Vector3.ZERO
	var k := int(t / GUST_EVERY)
	if t - k * GUST_EVERY >= GUST_LEN:
		return Vector3.ZERO
	var a := k * 2.4 + 0.6
	return Vector3(cos(a), 0, sin(a)) * GUST_SPEED


## 다음 돌풍이 시작하는 틱 (안내용)
func next_gust_tick(tick: int) -> int:
	if crumble_start <= 0:
		return -1
	var t := (tick - crumble_start) / 60.0 - GUST_FIRST
	var k := 0 if t < 0.0 else int(t / GUST_EVERY) + 1
	return crumble_start + int((GUST_FIRST + k * GUST_EVERY) * 60.0)


func pre_move(body: PlayerBody, tick: int) -> void:
	super.pre_move(body, tick)
	var w := gust_at(tick)
	if w != Vector3.ZERO and not body.frozen:
		body.global_position += w / 60.0


func _build_wind_fx() -> void:
	if is_headless:
		return
	_wind_fx = CPUParticles3D.new()
	_wind_fx.amount = 60
	_wind_fx.lifetime = 1.2
	_wind_fx.emitting = false
	_wind_fx.mesh = cyl_mesh(0.03, 0.03, 1.4, 4)
	_wind_fx.material_override = glow_material(Color(1, 1, 1), 1.0)
	_wind_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_wind_fx.emission_box_extents = Vector3(12, 2, 12)
	_wind_fx.gravity = Vector3.ZERO
	_wind_fx.particle_flag_align_y = true
	_wind_fx.initial_velocity_min = 9.0
	_wind_fx.initial_velocity_max = 13.0
	_wind_fx.spread = 4.0
	_wind_fx.position = Vector3(0, 1.5, 0)
	add_child(_wind_fx)


## 지금 서 있을 수 있는지 (무너지지 않은 바닥 위인지)
func is_solid_at(p: Vector3) -> bool:
	var r := Vector2(p.x, p.z).length()
	if r <= CORE_RADIUS:
		return true
	if r > ARENA_RADIUS:
		return false
	var best: Dictionary = {}
	var best_d := INF
	for tl in tiles:
		var b: Vector3 = tl["base"]
		var d := Vector2(b.x - p.x, b.z - p.z).length()
		if d < best_d:
			best_d = d
			best = tl
	return not best.get("fallen", true)


func spectator_point() -> Vector3:
	return Vector3(0, 9, -20.5)


func get_bot_target(_pos: Vector3, _state: Dictionary, my_id: int) -> Vector3:
	var a := float(posmod(my_id, 8)) / 8.0 * TAU
	return Vector3(sin(a) * 3.5, 0, cos(a) * 3.5)


func apply_mode_state(state: Dictionary) -> void:
	round_start_tick = int(state.get("round_start_tick", 0))
	crumble_start = int(state.get("extra", {}).get("crumble", 0))


## 시각 장식: 가장자리 경고 띠, 기둥 줄무늬, 떠 있는 등불, 관전석 꾸밈
func _decorate() -> void:
	if is_headless:
		return
	var inner := TorusMesh.new()
	inner.inner_radius = CORE_RADIUS - 0.25
	inner.outer_radius = CORE_RADIUS + 0.05
	inner.rings = 48
	inner.ring_segments = 6
	add_mesh(inner, Vector3(0, 0.0, 0), Color(1.0, 0.95, 0.7), Vector3.ZERO, Vector3(1, 0.06, 1))
	for i in 3:  # 가운데 기둥 줄무늬
		var t := TorusMesh.new()
		t.inner_radius = 0.86
		t.outer_radius = 1.06
		t.rings = 24
		t.ring_segments = 8
		add_mesh(t, Vector3(0, 0.6 + i * 0.95, 0), Color(1.0, 0.45, 0.5) if i % 2 == 0 else Color(1, 1, 1))
	add_mesh(sphere_mesh(0.95, 18), Vector3(0, 3.0, 0), Color(1.0, 0.9, 0.4), Vector3.ZERO, Vector3(1, 0.5, 1))
	for i in 10:  # 무대 둘레에 떠 있는 등불
		var a := TAU * i / 10.0
		var p := Vector3(sin(a) * 15.0, 3.0 + (i % 2) * 1.5, cos(a) * 15.0)
		add_mesh(sphere_mesh(0.42, 12), p, glow_material(Color(1.0, 0.8, 0.55) if i % 2 == 0 else Color(0.85, 0.7, 1.0), 1.6))
		add_mesh(cyl_mesh(0.18, 0.28, 0.16, 10), p + Vector3(0, -0.45, 0), Color(0.6, 0.45, 0.7))
	add_edge_trim(Vector3(0, 8, -20), Vector3(10, 1, 5), Color(1.0, 0.6, 0.75))
	for x in [-4.0, -2.0, 0.0, 2.0, 4.0]:  # 관전석 의자
		add_mesh(BoxMesh.new(), Vector3(x, 8.75, -21.2), Color(0.55, 0.75, 1.0) if int(x) % 4 == 0 else Color(1.0, 0.7, 0.8), Vector3.ZERO, Vector3(1.4, 0.5, 1.2))
	add_flag(Vector3(-5.2, 8.5, -22.2), Color(1.0, 0.55, 0.7), 0.0, 2.6)
	add_flag(Vector3(5.2, 8.5, -22.2), Color(0.55, 0.75, 1.0), 180.0, 2.6)
