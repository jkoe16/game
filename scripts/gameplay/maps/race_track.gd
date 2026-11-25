class_name RaceTrackMap
extends GameMap
## 레이싱 트랙 "구름 서킷": 꺾이는 순환 코스 (폭 8m, 한 바퀴 약 176m).
##  서쪽 직선(출발) → 북쪽(낮은 벽 + 점프대) → 남쪽으로 꺾이는 좁은 골목 → 동쪽 → 동쪽 직선 → 남쪽 직선(망치) → 출발
## 북동쪽에 난간 없는 대각선 다리 = 지름길 (떨어지면 북쪽 체크포인트부터 다시).
## 시간이 지날수록 어려워진다: 30초부터 굴러오는 공, 60초부터 밀어내는 벽, 남쪽 망치는 점점 빨라짐.
## 체크포인트 4개를 순서대로 통과 (0 = 출발/결승선).

const TRACK := Color(0.45, 0.47, 0.55)
const EDGE := Color(1.0, 1.0, 1.0)
const BRIDGE := Color(0.95, 0.75, 0.45)
## 단계별 장애물 등장 시간 (초)
const STAGE2_SEC := 30.0
const STAGE3_SEC := 60.0

## 트랙 조각 [중심, 크기] (윗면 y = 0)
const PIECES := [
	[Vector3(-20, -0.5, 0), Vector3(8, 1, 56)],     # 서쪽 직선 x -24..-16, z -28..28
	[Vector3(-4, -0.5, 24), Vector3(24, 1, 8)],     # 북쪽 x -16..8
	[Vector3(4, -0.5, 12), Vector3(8, 1, 16)],      # 골목 (남쪽으로) x 0..8, z 4..20
	[Vector3(12, -0.5, 8), Vector3(8, 1, 8)],       # 골목 → 동쪽 x 8..16, z 4..12
	[Vector3(20, -0.5, -8), Vector3(8, 1, 40)],     # 동쪽 직선 x 16..24, z -28..12
	[Vector3(0, -0.5, -24), Vector3(32, 1, 8)],     # 남쪽 직선 x -16..16
]

var checkpoints: Array[Dictionary] = [
	{"center": Vector3(-20, 1, -12), "half": Vector3(4, 2.5, 1.0)},
	{"center": Vector3(-8, 1, 24), "half": Vector3(1.0, 2.5, 4)},
	{"center": Vector3(20, 1, 0), "half": Vector3(4, 2.5, 1.0)},
	{"center": Vector3(0, 1, -24), "half": Vector3(1.0, 2.5, 4)},
]
## 봇 경로 (트랙 중심선 모서리, 지름길은 안 씀)
var route: Array[Vector3] = [
	Vector3(-20, 0, -12), Vector3(-20, 0, 22), Vector3(-6, 0, 24), Vector3(4, 0, 23), Vector3(4, 0, 9),
	Vector3(19, 0, 8), Vector3(20, 0, -22), Vector3(5, 0, -24), Vector3(-19, 0, -24),
]
var _bot_idx := {}


func _ready() -> void:
	map_id = "race_track"
	display_name = "구름 서킷"
	kill_height = -10.0
	setup_environment(Color(0.35, 0.6, 0.95), Color(0.85, 0.92, 1.0), Vector3(-50, 40, 0))
	for pc in PIECES:
		add_box(pc[0], pc[1], TRACK)
	add_box(Vector3(0, -2, 0), Vector3(32, 1, 40), Color(0.5, 0.85, 0.5), Vector3.ZERO, false)  # 안쪽 잔디(장식, 낙하 구역)
	add_checker(Vector3(-20, 0, -12), 8, 1.2, 0.8)
	add_label(Vector3(-20, 6.2, -12), "출발 / 결승", 80, Color(1, 0.95, 0.5))

	# 서쪽 직선: 부스터
	add_pad("boost", Vector3(-20, 0, 8), Vector3(2.5, 0.3, 2))
	# 북쪽: 낮은 벽 (그냥 점프로도 넘지만 점프대가 더 빠름)
	add_pad("jump", Vector3(-3, 0, 24), Vector3(1.2, 0.3, 3.5), 11.0)
	add_box(Vector3(1, 0.6, 24), Vector3(0.8, 1.2, 8), Color(1.0, 0.55, 0.45))
	# 지름길: 북쪽 끝 → 동쪽 직선 위쪽으로 가는 난간 없는 좁은 대각선 다리 (가운데 아이템 상자)
	var a := Vector3(7.6, 0, 23.0)
	var b := Vector3(19.0, 0, 11.6)
	var mid := (a + b) * 0.5
	add_box(Vector3(mid.x, -0.3, mid.z), Vector3(1.4, 0.6, a.distance_to(b) + 1.0), BRIDGE, Vector3(0, rad_to_deg(atan2(b.x - a.x, b.z - a.z)), 0))
	add_label(Vector3(mid.x, 2.6, mid.z), "지름길!", 56, Color(1, 0.85, 0.4))
	# 골목: 30초부터 앞에서 공이 굴러온다
	add_roller(Vector3(2.2, 0.7, 5.0), Vector3(2.2, 0.7, 19.5), 0.7, 2.6, 0.0, STAGE2_SEC)
	add_roller(Vector3(5.8, 0.7, 5.0), Vector3(5.8, 0.7, 19.5), 0.7, 2.6, 0.5, STAGE2_SEC)
	add_pad("boost", Vector3(12, 0, 8), Vector3(2.0, 0.3, 2.0))
	# 동쪽 직선: 60초부터 양옆에서 벽이 튀어나온다 → 지나면 부스터
	add_pusher(Vector3(24.8, 0.6, -8), Vector3(1.6, 1.2, 2.4), Vector3(-1, 0, 0), 4.6, 2.4, 0.0, STAGE3_SEC)
	add_pusher(Vector3(15.2, 0.6, -14), Vector3(1.6, 1.2, 2.4), Vector3(1, 0, 0), 4.6, 2.4, 0.5, STAGE3_SEC)
	add_pad("boost", Vector3(20, 0, -20), Vector3(2.5, 0.3, 2))
	# 남쪽 직선: 회전 망치(점프로 넘기, 시간이 갈수록 빨라짐) → 바로 뒤 부스터 = 위험을 넘으면 보상
	add_sweeper(Vector3(6, 0, -24), 3.6, 0.5, 95.0, 0.0, 1.2, 1, 0.4, Color(0.45, 0.6, 1.0), true)
	add_sweeper(Vector3(-7, 0, -24), 3.6, 0.5, -80.0, 90.0, 0.0, 1, 0.4, Color(1.0, 0.6, 0.3), true)
	add_pad("boost", Vector3(-13, 0, -24), Vector3(1.6, 0.3, 2.5))
	for i in 8:
		spawn_points.append(Vector3(-22.5 + (i % 4) * 1.7, 0.5, -7.5 + (i / 4) * 1.8))
	item_spawns = [Vector3(-20, 1.2, 18), Vector3(-12, 1.2, 22), Vector3(-12, 1.2, 26), Vector3(mid.x, 1.2, mid.z),
		Vector3(20, 1.2, 4), Vector3(20, 1.2, -25), Vector3(0, 1.2, -21)]
	_decorate()


## 시각 장식: 흰 가장자리, 출발 아치, 안쪽 정원(나무·꽃), 모서리 깃발
func _decorate() -> void:
	if is_headless:
		return
	add_arch(Vector3(-20, 0, -12), 9.2, 4.6, Color(1.0, 0.55, 0.7))
	for pc in PIECES:
		add_edge_trim(pc[0], pc[1], Color(1.0, 0.5, 0.55))
	# 안쪽 정원 (잔디 윗면 y = -1.5) — 골목(x 0..16, z 4..20)과 겹치지 않게
	var g := -1.5
	for p in [Vector3(-10, g, -14), Vector3(6, g, -12), Vector3(-9, g, 4), Vector3(-4, g, 14), Vector3(-11, g, 16), Vector3(10, g, -4)]:
		add_tree(p, int(abs(p.z)) % 3, 1.0, false)
	for p in [Vector3(0, g, -12), Vector3(-6, g, 8), Vector3(-6, g, -4), Vector3(8, g, -16), Vector3(12, g, 20)]:
		add_flowers(p, 2.4, 26, int(p.z * 3 + 50))
		add_bush(p + Vector3(2.5, 0, 1.5), 0.9)
	var flag_cols := [Color(1.0, 0.5, 0.6), Color(1.0, 0.8, 0.3), Color(0.45, 0.75, 1.0), Color(0.6, 0.9, 0.5)]
	var k := 0
	for c in [Vector3(-24.5, 0, -28.5), Vector3(24.5, 0, -28.5), Vector3(-24.5, 0, 28.5), Vector3(8.5, 0, 28.5), Vector3(24.5, 0, 12.5)]:
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
