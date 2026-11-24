class_name RaceCourseMap
extends GameMap
## 장애물 레이스 코스 (+Z 방향으로 진행).
##  A 구멍 점프 → B 회전 막대 2개 → C 이동 발판(빠른 길) 또는 좁은 다리(쉬운 길) → D 점프 패드로 윗층 → E 막대 + 결승

const GROUND := Color(0.98, 0.78, 0.55)
const PATH := Color(0.55, 0.8, 1.0)
const UPPER := Color(0.75, 0.6, 1.0)

var finish_z := 114.0
## 체크포인트: z를 넘으면 도달 (윗층은 y 조건 포함)
var checkpoints: Array[Dictionary] = [
	{"z": -100.0, "min_y": -99.0, "point": Vector3(0, 0.5, -2)},
	{"z": 26.5, "min_y": -1.0, "point": Vector3(0, 0.5, 29)},
	{"z": 54.0, "min_y": -1.0, "point": Vector3(0, 0.5, 55)},
	{"z": 76.0, "min_y": -1.0, "point": Vector3(0, 0.5, 80)},
	{"z": 98.0, "min_y": 2.5, "point": Vector3(0, 4.0, 100)},
]
var waypoints: Array[Vector3] = [
	Vector3(0, 0, 8), Vector3(0, 0, 15.2), Vector3(0, 0, 20), Vector3(0, 0, 25.2), Vector3(0, 0, 31),
	Vector3(0, 0, 36), Vector3(0, 0, 44), Vector3(0, 0, 53), Vector3(6.5, 0, 57), Vector3(6.5, 0, 75),
	Vector3(0, 0, 80), Vector3(0, 0, 93), Vector3(0, 3.5, 102), Vector3(0, 3.5, 110), Vector3(0, 3.5, 118),
]


func _ready() -> void:
	map_id = "race_course"
	display_name = "하늘 놀이공원 코스"
	kill_height = -15.0
	setup_environment(Color(0.4, 0.65, 0.98), Color(0.9, 0.95, 1.0), Vector3(-55, 25, 0))

	# 출발 + A: 구멍 2개
	add_box(Vector3(0, -0.5, 0), Vector3(14, 1, 12), GROUND)
	add_box(Vector3(0, -0.5, 10), Vector3(10, 1, 8), PATH)
	add_box(Vector3(0, -0.5, 20.25), Vector3(10, 1, 7.5), PATH)
	add_box(Vector3(0, -0.5, 30.25), Vector3(10, 1, 7.5), GROUND)
	add_label(Vector3(0, 5.6, 5), "출발!", 96, Color(1, 0.9, 0.4))

	# B: 넓은 무대 + 낮은 회전 막대 2개 (점프로 넘기)
	add_box(Vector3(0, -0.5, 44), Vector3(14, 1, 20), PATH)
	add_sweeper(Vector3(-3.5, 0, 40), 4.5, 0.5, 100.0, 0.0, 0.0, 1, 0.4, Color(1.0, 0.45, 0.4), true)
	# 후반 패턴: 이 망치는 점점 느려지다 30초쯤 멈춘 뒤 반대 방향으로 빨라진다
	add_sweeper(Vector3(3.5, 0, 48), 4.5, 0.5, -120.0, 90.0, 4.0, 1, 0.4, Color(1.0, 0.6, 0.3), true)
	add_pad("boost", Vector3(-5.0, 0, 52.0), Vector3(1.6, 0.3, 1.4))

	# C: 빠른 길(이동 발판 3개) / 쉬운 길(오른쪽 좁은 다리)
	add_box(Vector3(0, -0.5, 55), Vector3(14, 1, 2), GROUND)
	for i in 3:
		var z := 60.0 + i * 6.0
		add_mover(Vector3(-5, -0.3, z), Vector3(2, -0.3, z), Vector3(4, 0.6, 4), 4.0, i * 0.33)
	add_box(Vector3(6.5, -0.5, 66), Vector3(1.6, 1, 20), Color(0.85, 0.7, 0.5))
	add_label(Vector3(6.5, 2.5, 58), "쉬운 길", 56)
	add_label(Vector3(-1.5, 2.5, 57), "빠른 길", 56)

	# D: 착지 무대 + 점프 패드 → 윗층
	add_box(Vector3(0, -0.5, 86), Vector3(14, 1, 20), GROUND)
	add_pad("jump", Vector3(0, 0, 93.5), Vector3(2.0, 0.3, 1.2), 15.0)
	add_pad("boost", Vector3(4.5, 0, 81.0), Vector3(1.6, 0.3, 1.4))
	add_box(Vector3(0, 1.75, 105), Vector3(14, 3.5, 14), UPPER.darkened(0.25))
	add_box(Vector3(0, 3.25, 105), Vector3(14, 0.5, 14), UPPER)

	# E: 윗층 막대(양쪽 팔) + 결승
	add_sweeper(Vector3(0, 3.5, 105), 6.0, 4.0, 75.0, 0.0, 1.5, 2)  # 시간이 지날수록 빨라짐 (최고 속도 제한)
	add_box(Vector3(0, 3.0, 117), Vector3(14, 1, 10), Color(1.0, 0.9, 0.5))
	add_checker(Vector3(0, 3.5, finish_z), 14, 1.4)
	add_label(Vector3(0, 9.0, finish_z), "결승선", 110, Color(1, 0.95, 0.5))

	for i in 8:
		spawn_points.append(Vector3(-5.25 + i * 1.5, 0.5, -3.0))
	item_spawns = [Vector3(-3, 1.2, 10), Vector3(3, 1.2, 36), Vector3(-4, 1.2, 80), Vector3(4, 4.7, 111)]
	_decorate()


## 시각 장식 (충돌 없음): 출발·결승 아치, 깃발, 발판 테두리, 꽃
func _decorate() -> void:
	if is_headless:
		return
	add_arch(Vector3(0, 0, 5), 11.0, 4.4, Color(1.0, 0.55, 0.7))
	add_arch(Vector3(0, 3.5, finish_z), 14.6, 4.6, Color(1.0, 0.78, 0.3))
	var trim := Color(1, 1, 1)
	for b in [[Vector3(0, -0.5, 0), Vector3(14, 1, 12)], [Vector3(0, -0.5, 44), Vector3(14, 1, 20)], [Vector3(0, -0.5, 86), Vector3(14, 1, 20)],
			[Vector3(0, 3.25, 105), Vector3(14, 0.5, 14)], [Vector3(0, 3.0, 117), Vector3(14, 1, 10)], [Vector3(0, -0.5, 30.25), Vector3(10, 1, 7.5)]]:
		add_edge_trim(b[0], b[1], trim)
	var flag_cols := [Color(1.0, 0.5, 0.6), Color(1.0, 0.8, 0.3), Color(0.45, 0.75, 1.0), Color(0.6, 0.9, 0.5)]
	var fi := 0
	for z in [-4.0, 36.0, 52.0, 78.0, 94.0]:
		for sx in [-1.0, 1.0]:
			add_flag(Vector3(6.6 * sx, 0, z), flag_cols[fi % 4], 0.0 if sx < 0 else 180.0)
			fi += 1
	for sx in [-1.0, 1.0]:
		add_flag(Vector3(6.6 * sx, 3.5, 120.5), flag_cols[fi % 4], 0.0 if sx < 0 else 180.0)
		fi += 1
		add_flowers(Vector3(5.8 * sx, 0, -4.5), 0.9, 14, 40 + fi)
		add_bush(Vector3(6.0 * sx, 0, 3.5), 0.7)
		add_flowers(Vector3(5.8 * sx, 3.5, 120.0), 0.9, 12, 60 + fi)
	_build_ferris_wheel(Vector3(-30, -2, 62))
	_build_carousel(Vector3(22, -3, 30))
	# 코스 옆 떠 있는 작은 섬 위 줄무늬 천막
	var tent_cols := [Color(1.0, 0.5, 0.6), Color(0.5, 0.7, 1.0), Color(1.0, 0.8, 0.35), Color(0.65, 0.9, 0.55)]
	for i in 4:
		var p := Vector3(-17.0 if i % 2 == 0 else 17.0, -2.5, 12.0 + i * 26.0)
		add_mesh(cyl_mesh(3.2, 3.2, 1.0, 24), p, Color(0.55, 0.85, 0.5))
		add_island_underside(p + Vector3(0, -0.5, 0), 3.1, 4.0)
		_build_tent(p + Vector3(0, 0.5, 0), tent_cols[i])


var _spin: Array[Dictionary] = []   # 도는 놀이기구 {node, speed}


func _process(delta: float) -> void:
	for s in _spin:
		(s["node"] as Node3D).rotate_object_local(s["axis"], s["speed"] * delta)


## 대관람차 (천천히 돈다, 시각 전용)
func _build_ferris_wheel(pos: Vector3) -> void:
	add_mesh(cyl_mesh(5.0, 6.0, 1.5, 24), pos + Vector3(0, -0.75, 0), Color(0.55, 0.85, 0.5))
	add_island_underside(pos + Vector3(0, -1.5, 0), 5.8, 7.0)
	for sz in [-1.0, 1.0]:
		add_mesh(cyl_mesh(0.35, 0.5, 13.0, 10), pos + Vector3(-3.0, 6.0, sz * 1.0), Color(0.95, 0.95, 1.0), Vector3(0, 0, -14))
		add_mesh(cyl_mesh(0.35, 0.5, 13.0, 10), pos + Vector3(3.0, 6.0, sz * 1.0), Color(0.95, 0.95, 1.0), Vector3(0, 0, 14))
	var wheel := Node3D.new()
	wheel.position = pos + Vector3(0, 12.0, 0)
	wheel.set_meta("dynamic", true)
	add_child(wheel)
	var rim := TorusMesh.new()
	rim.inner_radius = 9.4
	rim.outer_radius = 10.0
	rim.rings = 48
	rim.ring_segments = 8
	add_mesh(rim, Vector3.ZERO, Color(1.0, 0.55, 0.7), Vector3(90, 0, 0), Vector3.ONE, wheel)
	add_mesh(sphere_mesh(1.0, 14), Vector3.ZERO, Color(1.0, 0.85, 0.35), Vector3.ZERO, Vector3.ONE, wheel)
	var cols := [Color(1.0, 0.55, 0.6), Color(0.5, 0.75, 1.0), Color(1.0, 0.82, 0.35), Color(0.6, 0.9, 0.55), Color(0.8, 0.65, 1.0)]
	for k in 10:
		var a := TAU * k / 10.0
		add_mesh(cyl_mesh(0.12, 0.12, 9.6, 6), Vector3(cos(a), sin(a), 0) * 4.8, Color(1, 1, 1), Vector3(0, 0, rad_to_deg(a) - 90.0), Vector3.ONE, wheel)
		add_mesh(BoxMesh.new(), Vector3(cos(a), sin(a), 0) * 9.7, cols[k % 5], Vector3.ZERO, Vector3(1.4, 1.2, 1.4), wheel)
	_spin.append({"node": wheel, "axis": Vector3.FORWARD, "speed": 0.15})


## 회전목마 (시각 전용)
func _build_carousel(pos: Vector3) -> void:
	add_mesh(cyl_mesh(5.5, 5.5, 1.2, 32), pos, Color(0.55, 0.85, 0.5))
	add_island_underside(pos + Vector3(0, -0.6, 0), 5.4, 6.0)
	var spin := Node3D.new()
	spin.position = pos + Vector3(0, 0.6, 0)
	spin.set_meta("dynamic", true)
	add_child(spin)
	add_mesh(cyl_mesh(4.0, 4.2, 0.5, 32), Vector3(0, 0.25, 0), Color(1.0, 0.92, 0.75), Vector3.ZERO, Vector3.ONE, spin)
	add_mesh(cyl_mesh(0.4, 0.4, 4.5, 12), Vector3(0, 2.5, 0), Color(1.0, 0.85, 0.4), Vector3.ZERO, Vector3.ONE, spin)
	for k in 8:  # 줄무늬 지붕
		var a := TAU * k / 8.0
		add_mesh(cyl_mesh(0.0, 2.2, 1.6, 3), Vector3(sin(a) * 2.2, 5.3, cos(a) * 2.2), Color(1.0, 0.5, 0.65) if k % 2 == 0 else Color(1, 1, 1), Vector3(0, rad_to_deg(a), 0), Vector3(1, 1, 0.9), spin)
	add_mesh(cyl_mesh(0.05, 4.3, 1.8, 24), Vector3(0, 5.4, 0), Color(1.0, 0.6, 0.75), Vector3.ZERO, Vector3.ONE, spin)
	var cols := [Color(1.0, 0.7, 0.8), Color(0.7, 0.85, 1.0), Color(1.0, 0.9, 0.6), Color(0.75, 0.95, 0.7)]
	for k in 6:
		var a := TAU * k / 6.0
		var p := Vector3(sin(a) * 3.0, 0, cos(a) * 3.0)
		add_mesh(cyl_mesh(0.06, 0.06, 3.8, 6), p + Vector3(0, 2.4, 0), Color(1.0, 0.85, 0.4), Vector3.ZERO, Vector3.ONE, spin)
		add_mesh(sphere_mesh(0.55, 12), p + Vector3(0, 1.4, 0), cols[k % 4], Vector3.ZERO, Vector3(0.7, 0.8, 1.4), spin)
	_spin.append({"node": spin, "axis": Vector3.UP, "speed": 0.5})


## 줄무늬 천막
func _build_tent(pos: Vector3, c: Color) -> void:
	add_mesh(cyl_mesh(1.8, 1.8, 1.8, 16), pos + Vector3(0, 0.9, 0), Color(1, 1, 1))
	for k in 8:
		var a := TAU * k / 8.0
		add_mesh(cyl_mesh(0.0, 1.35, 1.7, 3), pos + Vector3(sin(a) * 0.95, 2.6, cos(a) * 0.95), c if k % 2 == 0 else Color(1, 1, 1), Vector3(0, rad_to_deg(a), 0))
	add_mesh(sphere_mesh(0.2, 8), pos + Vector3(0, 3.55, 0), Color(1.0, 0.85, 0.35))
	add_flag(pos + Vector3(0, 3.5, 0), c, 0.0, 1.0)


func get_start_point(index: int) -> Vector3:
	return get_spawn_point(index)


func checkpoint_index_at(pos: Vector3) -> int:
	var best := 0
	for i in checkpoints.size():
		if pos.z >= checkpoints[i]["z"] and pos.y >= checkpoints[i]["min_y"]:
			best = i
	return best


func checkpoint_point(i: int, peer_id := 0) -> Vector3:
	var p: Vector3 = checkpoints[clampi(i, 0, checkpoints.size() - 1)]["point"]
	return p + Vector3(float(posmod(peer_id, 5) - 2) * 1.2, 0, 0)


func is_finished(pos: Vector3) -> bool:
	return pos.z >= finish_z and pos.y > 2.5


func get_bot_target(pos: Vector3, _state: Dictionary, _my_id: int) -> Vector3:
	for w in waypoints:
		if w.z > pos.z + 1.0:
			if w.y - pos.y > 2.0:
				return Vector3(0, 0, 93.5)  # 윗층은 점프 패드로
			return w
	return waypoints.back()
