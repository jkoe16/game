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


func spectator_point() -> Vector3:
	return Vector3(0, 9, -20.5)


func get_bot_target(_pos: Vector3, _state: Dictionary, my_id: int) -> Vector3:
	var a := float(posmod(my_id, 8)) / 8.0 * TAU
	return Vector3(sin(a) * 5.0, 0, cos(a) * 5.0)


func apply_mode_state(state: Dictionary) -> void:
	round_start_tick = int(state.get("round_start_tick", 0))
