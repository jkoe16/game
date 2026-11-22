class_name LobbyPlazaMap
extends GameMap
## 메인 로비 "하늘 위의 광장" — 그레이박스 버전.
## 이동 검증용 요소 포함: 경사로(20°), 계단(0.2m), 점프 발판, 낙하/리스폰(가장자리 밖).
## 최종 아트는 Blender GLB로 교체하되, 충돌 레이아웃은 이 파일 기준으로 유지한다.

const GRASS := Color(0.45, 0.78, 0.38)
const STONE := Color(0.86, 0.80, 0.72)
const ROCK := Color(0.62, 0.52, 0.48)
const WATER := Color(0.45, 0.75, 1.0)
const WOOD := Color(0.70, 0.48, 0.32)
const LEAF := Color(0.35, 0.72, 0.38)

const MODE_PORTALS := [
	["장애물 레이스", Color(1.0, 0.55, 0.45), "obstacle_race"],
	["생존 게임", Color(0.6, 0.55, 1.0), "survival"],
	["레이싱", Color(1.0, 0.8, 0.3), "racing"],
	["협동 미션", Color(0.45, 0.85, 0.75), "coop"],
	["파티 미니게임", Color(1.0, 0.6, 0.85), "party"],
]

## 포털 판정 영역 (서버 LobbyMode가 사용): [{mode, center, radius}]
var portals: Array[Dictionary] = []


func _ready() -> void:
	map_id = "lobby_plaza"
	display_name = "하늘 위의 광장"
	kill_height = -25.0
	setup_environment(Color(0.35, 0.6, 0.95), Color(0.85, 0.92, 1.0), Vector3(-50, 35, 0))

	# 섬 본체
	add_cylinder(Vector3(0, -1, 0), 28.0, 2.0, GRASS, true, 64)
	add_cylinder(Vector3(0, -4.5, 0), 25.0, 5.0, ROCK, true, 48)
	add_cylinder(Vector3(0, -8.5, 0), 16.0, 3.0, ROCK.darkened(0.15), false, 32)

	# 중앙 분수
	add_cylinder(Vector3(0, 0.5, 0), 3.2, 1.0, STONE)
	add_cylinder(Vector3(0, 1.02, 0), 2.7, 0.06, WATER, false)
	add_cylinder(Vector3(0, 1.8, 0), 0.45, 2.6, STONE)
	add_deco_sphere(Vector3(0, 3.3, 0), 0.7, WATER, Vector3(1, 0.6, 1))

	# 스폰 지점: 분수 주변 링
	for i in 12:
		var ang := TAU * i / 12.0
		spawn_points.append(Vector3(sin(ang) * 6.0, 0.5, cos(ang) * 6.0))

	# 경사로(20°) → 전망대
	add_box(Vector3(12, 1.6, -8), Vector3(4, 0.5, 10), STONE, Vector3(20, 0, 0))
	add_box(Vector3(12, 2.95, -15.7), Vector3(6, 1.0, 6), STONE)
	add_label(Vector3(12, 5.2, -15.7), "전망대", 72)

	# 계단 (단 높이 0.2m)
	for i in 8:
		var h := 0.2 * (i + 1)
		add_box(Vector3(-12, h * 0.5, -6 - 0.8 * i), Vector3(4, h, 0.8), STONE)
	add_box(Vector3(-12, 0.8, -14), Vector3(4, 1.6, 2.4), STONE)

	# 점프 발판 (단차 1.1m, 최대 점프 높이 ≈ 1.92m)
	var hops := [Vector3(-6, 0.6, 14), Vector3(-9, 1.7, 17), Vector3(-12.5, 2.8, 19), Vector3(-16, 3.9, 20)]
	for p in hops:
		add_box(p, Vector3(2.6, 0.6, 2.6), Color(1.0, 0.75, 0.55))
	add_label(Vector3(-16, 6.0, 20), "점프 도전!", 72)

	# 게임 모드 포털 (Phase 5~6에서 실제 입장 기능 연결)
	for i in MODE_PORTALS.size():
		var ang := deg_to_rad(-60.0 + 30.0 * i)
		var center := Vector3(sin(ang) * 19.0, 0, cos(ang) * 19.0)
		var c: Color = MODE_PORTALS[i][1]
		add_cylinder(center + Vector3(0, 0.05, 0), 2.0, 0.1, c, false)
		var side := Vector3(cos(ang), 0, -sin(ang)) * 2.2
		add_box(center + side + Vector3(0, 1.75, 0), Vector3(0.5, 3.5, 0.5), c.darkened(0.2), Vector3(0, rad_to_deg(ang), 0))
		add_box(center - side + Vector3(0, 1.75, 0), Vector3(0.5, 3.5, 0.5), c.darkened(0.2), Vector3(0, rad_to_deg(ang), 0))
		add_box(center + Vector3(0, 3.7, 0), Vector3(5.2, 0.5, 0.6), c, Vector3(0, rad_to_deg(ang), 0))
		add_label(center + Vector3(0, 4.6, 0), "%s\n(올라서면 입장)" % MODE_PORTALS[i][0], 64)
		portals.append({"mode": MODE_PORTALS[i][2], "center": center, "radius": 2.0})

	# 나무 & 벤치
	var trees := [Vector3(18, 0, 6), Vector3(-19, 0, 2), Vector3(5, 0, -21), Vector3(-5, 0, -22), Vector3(22, 0, -6)]
	for p in trees:
		add_cylinder(p + Vector3(0, 1.2, 0), 0.35, 2.4, WOOD, true, 12)
		add_deco_sphere(p + Vector3(0, 3.0, 0), 1.5, LEAF)
		add_deco_sphere(p + Vector3(0.6, 3.6, 0.3), 1.0, LEAF.lightened(0.1))
	for ang_deg in [45.0, 135.0, 225.0, 315.0]:
		var a := deg_to_rad(ang_deg)
		add_box(Vector3(sin(a) * 9.0, 0.25, cos(a) * 9.0), Vector3(2.4, 0.5, 0.7), WOOD, Vector3(0, ang_deg, 0))

	# 섬 밖 장식: 떠 있는 작은 섬과 구름
	if not is_headless:
		for i in 6:
			var a := TAU * i / 6.0 + 0.4
			var p := Vector3(sin(a) * 45.0, -6.0 + (i % 3) * 4.0, cos(a) * 45.0)
			add_cylinder(p, 4.0, 1.5, GRASS, false, 24)
			add_cylinder(p + Vector3(0, -1.8, 0), 3.0, 2.2, ROCK, false, 16)
		for i in 10:
			var a := TAU * i / 10.0
			var p := Vector3(sin(a) * 70.0, 8.0 + (i % 4) * 3.0, cos(a) * 70.0)
			add_deco_sphere(p, 4.0, Color(1, 1, 1), Vector3(2.0, 0.8, 1.2))
