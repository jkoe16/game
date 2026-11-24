class_name RaceTrackMap
extends GameMap
## 레이싱 트랙: 직사각형 순환 (서쪽 직선 +Z → 북쪽 → 동쪽 -Z → 남쪽). 폭 8m, 바깥 40×70m.
## 체크포인트 4개를 순서대로 통과 (0 = 출발/결승선). 부스트 패드 2개, 북쪽 점프대 + 낮은 벽.

const TRACK := Color(0.45, 0.47, 0.55)
const EDGE := Color(1.0, 1.0, 1.0)

var checkpoints: Array[Dictionary] = [
	{"center": Vector3(-16, 1, -10), "half": Vector3(4, 2.5, 1.0)},
	{"center": Vector3(0, 1, 31), "half": Vector3(1.0, 2.5, 4)},
	{"center": Vector3(16, 1, 0), "half": Vector3(4, 2.5, 1.0)},
	{"center": Vector3(0, 1, -31), "half": Vector3(1.0, 2.5, 4)},
]
## 봇 경로 (트랙 중심선 모서리)
var route: Array[Vector3] = [
	Vector3(-16, 0, -10), Vector3(-16, 0, 30), Vector3(0, 0, 31), Vector3(15, 0, 31),
	Vector3(16, 0, 0), Vector3(16, 0, -30), Vector3(0, 0, -31), Vector3(-15, 0, -31),
]
var _bot_idx := {}


func _ready() -> void:
	map_id = "race_track"
	display_name = "구름 서킷"
	kill_height = -10.0
	setup_environment(Color(0.35, 0.6, 0.95), Color(0.85, 0.92, 1.0), Vector3(-50, 40, 0))
	add_box(Vector3(-16, -0.5, 0), Vector3(8, 1, 70), TRACK)
	add_box(Vector3(16, -0.5, 0), Vector3(8, 1, 70), TRACK)
	add_box(Vector3(0, -0.5, 31), Vector3(24, 1, 8), TRACK)
	add_box(Vector3(0, -0.5, -31), Vector3(24, 1, 8), TRACK)
	add_box(Vector3(0, -2, 0), Vector3(22, 1, 52), Color(0.5, 0.85, 0.5), Vector3.ZERO, false)  # 안쪽 잔디(장식, 낙하 구역)
	add_checker(Vector3(-16, 0, -10), 8, 1.2, 0.8)
	add_label(Vector3(-16, 6.2, -10), "출발 / 결승", 80, Color(1, 0.95, 0.5))
	add_pad("boost", Vector3(-16, 0, 8), Vector3(2.5, 0.3, 2))
	add_pad("boost", Vector3(16, 0, -8), Vector3(2.5, 0.3, 2))
	add_pad("jump", Vector3(-5, 0, 31), Vector3(1.2, 0.3, 3.5), 11.0)
	add_box(Vector3(0, 0.6, 31), Vector3(0.8, 1.2, 8), Color(1.0, 0.55, 0.45))  # 점프로 넘는 낮은 벽
	# 남쪽 직선: 회전 막대(점프로 넘기) → 바로 뒤 부스터 = 위험을 넘으면 보상
	add_sweeper(Vector3(4, 0, -31), 3.6, 0.5, 95.0, 0.0, 0.0, 1, 0.4, Color(0.45, 0.6, 1.0), true)
	add_pad("boost", Vector3(-8, 0, -31), Vector3(2.0, 0.3, 2.5))
	for i in 8:
		spawn_points.append(Vector3(-18.5 + (i % 4) * 1.7, 0.5, -7.5 + (i / 4) * 1.8))
	item_spawns = [Vector3(-16, 1.2, 20), Vector3(16, 1.2, -20), Vector3(10, 1.2, 31), Vector3(-16, 1.2, -24)]
	_decorate()


## 시각 장식: 빨강/흰 연석, 출발 아치, 안쪽 정원(나무·꽃), 모서리 깃발
func _decorate() -> void:
	if is_headless:
		return
	add_arch(Vector3(-16, 0, -10), 9.2, 4.6, Color(1.0, 0.55, 0.7))
	var red := Color(1.0, 0.45, 0.5)
	var white := Color(1, 1, 1)
	var seg := BoxMesh.new()
	seg.size = Vector3(0.5, 0.05, 2.0)
	var seg_x := BoxMesh.new()
	seg_x.size = Vector3(2.0, 0.05, 0.5)
	# 바깥쪽·안쪽 가장자리 (x 고정 줄은 z를 따라, z 고정 줄은 x를 따라)
	for line in [[-19.75, -35.0, 35.0], [19.75, -35.0, 35.0], [-12.25, -27.0, 27.0], [12.25, -27.0, 27.0]]:
		var n := int((line[2] - line[1]) / 2.0)
		for i in n:
			add_mesh(seg, Vector3(line[0], 0.025, line[1] + 1.0 + i * 2.0), red if i % 2 == 0 else white)
	for line in [[34.75, -20.0, 20.0], [-34.75, -20.0, 20.0], [27.25, -12.0, 12.0], [-27.25, -12.0, 12.0]]:
		var n := int((line[2] - line[1]) / 2.0)
		for i in n:
			add_mesh(seg_x, Vector3(line[1] + 1.0 + i * 2.0, 0.025, line[0]), red if i % 2 == 0 else white)
	# 안쪽 정원 (잔디 윗면 y = -1.5)
	var g := -1.5
	for p in [Vector3(-6, g, -18), Vector3(6, g, -8), Vector3(-5, g, 4), Vector3(5, g, 16), Vector3(-6, g, 21), Vector3(7, g, -21)]:
		add_tree(p, int(abs(p.z)) % 3, 1.0, false)
	for p in [Vector3(0, g, -12), Vector3(0, g, 10), Vector3(-6, g, -4), Vector3(6, g, 2), Vector3(0, g, 22)]:
		add_flowers(p, 2.4, 26, int(p.z * 3 + 50))
		add_bush(p + Vector3(2.5, 0, 1.5), 0.9)
	var flag_cols := [Color(1.0, 0.5, 0.6), Color(1.0, 0.8, 0.3), Color(0.45, 0.75, 1.0), Color(0.6, 0.9, 0.5)]
	var k := 0
	for c in [Vector3(-20.5, 0, -35.5), Vector3(20.5, 0, -35.5), Vector3(-20.5, 0, 35.5), Vector3(20.5, 0, 35.5)]:
		add_flag(c, flag_cols[k % 4], 45.0 * k)
		k += 1


func in_checkpoint(pos: Vector3, i: int) -> bool:
	var c: Dictionary = checkpoints[i]
	var d: Vector3 = (pos - c["center"]).abs()
	var h: Vector3 = c["half"]
	return d.x <= h.x and d.y <= h.y and d.z <= h.z


func checkpoint_point(i: int) -> Vector3:
	return (checkpoints[i]["center"] as Vector3) + Vector3(0, -0.5, 0)


func get_bot_target(pos: Vector3, _state: Dictionary, my_id: int) -> Vector3:
	var idx: int = _bot_idx.get(my_id, 1)
	var p := Vector2(pos.x, pos.z)
	if p.distance_to(Vector2(route[idx].x, route[idx].z)) < 2.5:
		idx = (idx + 1) % route.size()
	# 리스폰 등으로 경로에서 크게 벗어나면 가장 가까운 지점 다음으로 재설정
	if p.distance_to(Vector2(route[idx].x, route[idx].z)) > 45.0:
		var best := 0
		for i in route.size():
			if p.distance_to(Vector2(route[i].x, route[i].z)) < p.distance_to(Vector2(route[best].x, route[best].z)):
				best = i
		idx = (best + 1) % route.size()
	_bot_idx[my_id] = idx
	return route[idx]
