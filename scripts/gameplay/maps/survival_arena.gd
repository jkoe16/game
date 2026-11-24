class_name SurvivalArenaMap
extends GameMap
## 생존 무대: 원형 섬 + 가운데 기둥 + 점점 빨라지는 낮은 막대(점프로 넘기)와 높은 막대(점프하면 맞음).
## 막대 각도는 round_start_tick 기준 가속 → 모드 상태로 시작 틱을 받아 클라이언트도 같은 위치 계산.

const ARENA_RADIUS := 11.0


func _ready() -> void:
	map_id = "survival_arena"
	display_name = "회전 막대 생존"
	kill_height = -12.0
	setup_environment(Color(0.55, 0.45, 0.9), Color(1.0, 0.8, 0.85), Vector3(-60, -30, 0))
	add_cylinder(Vector3(0, -1, 0), ARENA_RADIUS, 2.0, Color(0.95, 0.75, 0.85), true, 64)
	add_cylinder(Vector3(0, -3.5, 0), ARENA_RADIUS - 1.5, 3.0, Color(0.6, 0.5, 0.7), false, 32)
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
	_decorate()


## 시각 장식: 가장자리 경고 띠, 바닥 원형 무늬, 기둥 줄무늬, 떠 있는 등불, 관전석 꾸밈
func _decorate() -> void:
	if is_headless:
		return
	var ring := TorusMesh.new()
	ring.inner_radius = ARENA_RADIUS - 0.75
	ring.outer_radius = ARENA_RADIUS - 0.05
	ring.rings = 64
	ring.ring_segments = 6
	add_mesh(ring, Vector3(0, 0.0, 0), Color(1.0, 0.45, 0.6), Vector3.ZERO, Vector3(1, 0.06, 1))
	var inner := TorusMesh.new()
	inner.inner_radius = 5.6
	inner.outer_radius = 6.0
	inner.rings = 48
	inner.ring_segments = 6
	add_mesh(inner, Vector3(0, 0.0, 0), Color(1.0, 0.88, 0.94), Vector3.ZERO, Vector3(1, 0.05, 1))
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


func spectator_point() -> Vector3:
	return Vector3(0, 9, -20.5)


func get_bot_target(_pos: Vector3, _state: Dictionary, my_id: int) -> Vector3:
	var a := float(posmod(my_id, 8)) / 8.0 * TAU
	return Vector3(sin(a) * 5.0, 0, cos(a) * 5.0)


func apply_mode_state(state: Dictionary) -> void:
	round_start_tick = int(state.get("round_start_tick", 0))
