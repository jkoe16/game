class_name LobbyPlazaMap
extends GameMap
## 메인 로비 "하늘 위의 광장".
## 이동 검증용 요소 포함: 경사로(20°), 계단(0.2m), 분수대 턱(1.0m), 낙하/리스폰(가장자리 밖).
## 충돌 레이아웃(바닥·분수·경사로·계단·포털 기둥·나무 줄기·벤치)은 서버와 같아야 하므로 위치를 바꾸지 않는다.
## 장식은 모두 시각 전용(서버에서는 생성하지 않음).

const GRASS := Color(0.46, 0.79, 0.42)
const GRASS_EDGE := Color(0.36, 0.66, 0.38)
const STONE := Color(0.92, 0.85, 0.78)
const PATH := Color(0.97, 0.8, 0.64)
const ROCK := Color(0.72, 0.6, 0.58)
const WATER := Color(0.5, 0.82, 1.0)
const WOOD := Color(0.78, 0.55, 0.4)

const MODE_PORTALS := [
	["장애물 레이스", Color(1.0, 0.5, 0.45), "obstacle_race"],
	["최후의 생존자", Color(0.62, 0.52, 1.0), "survival"],
	["레이싱", Color(1.0, 0.78, 0.25), "racing"],
	["협동 미션", Color(0.3, 0.85, 0.72), "coop"],
	["보물 수집", Color(1.0, 0.52, 0.82), "party"],
]
const PORTAL_SHADER := preload("res://shaders/portal_swirl.gdshader")

## 포털 판정 영역 (서버 LobbyMode가 사용): [{mode, center, radius}]
var portals: Array[Dictionary] = []

var _bobbers: Array[Dictionary] = []   # 위아래로 둥실거리는 장식 {node, base, amp, speed, phase}
var _t := 0.0


func _ready() -> void:
	map_id = "lobby_plaza"
	display_name = "하늘 위의 광장"
	kill_height = -25.0
	auto_underside = false  # 섬 아래는 직접 꾸민다
	setup_environment(Color(0.38, 0.62, 0.98), Color(0.93, 0.9, 1.0), Vector3(-48, 35, 0))

	# ---------------------------------------------------------------- 섬 본체 (충돌)
	add_cylinder(Vector3(0, -1, 0), 28.0, 2.0, GRASS, true, 96)
	add_cylinder(Vector3(0, -4.5, 0), 25.0, 5.0, ROCK, true, 48)
	if not is_headless:
		# 잔디 가장자리 띠 + 아래로 좁아지는 바위층 → 떠 있는 섬 실루엣
		add_mesh(cyl_mesh(28.35, 28.1, 0.9, 96), Vector3(0, -1.55, 0), GRASS_EDGE)
		add_island_underside(Vector3(0, -7.0, 0), 25.0, 14.0, ROCK)

	# ---------------------------------------------------------------- 길 (시각 전용, 바닥 위 얇게)
	if not is_headless:
		add_mesh(cyl_mesh(9.0, 9.0, 0.04, 72), Vector3(0, 0.02, 0), PATH)
		add_mesh(cyl_mesh(7.6, 7.6, 0.05, 72), Vector3(0, 0.03, 0), GRASS)
		add_flowers(Vector3.ZERO, 7.2, 70, 3)
		for i in MODE_PORTALS.size():
			var ang := deg_to_rad(-60.0 + 30.0 * i)
			var mid := Vector3(sin(ang), 0, cos(ang)) * 13.5
			add_mesh(BoxMesh.new(), mid + Vector3(0, 0.025, 0), PATH, Vector3(0, rad_to_deg(ang), 0), Vector3(2.4, 0.04, 9.0))

	# ---------------------------------------------------------------- 중앙 분수
	add_cylinder(Vector3(0, 0.5, 0), 3.2, 1.0, STONE)
	add_cylinder(Vector3(0, 1.8, 0), 0.45, 2.6, STONE)
	if not is_headless:
		add_mesh(cyl_mesh(3.35, 3.35, 0.18, 48), Vector3(0, 1.0, 0), STONE.darkened(0.04))
		var water := StandardMaterial3D.new()
		water.albedo_color = Color(0.55, 0.85, 1.0, 0.85)
		water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		water.metallic_specular = 0.8
		water.roughness = 0.08
		water.rim_enabled = true
		water.rim = 0.5
		add_mesh(cyl_mesh(2.95, 2.95, 0.06, 48), Vector3(0, 1.04, 0), water)
		add_mesh(cyl_mesh(1.4, 0.6, 0.5, 32), Vector3(0, 3.1, 0), STONE)
		add_mesh(cyl_mesh(1.25, 1.25, 0.05, 32), Vector3(0, 3.33, 0), water)
		var spout := add_mesh(sphere_mesh(0.55, 18), Vector3(0, 3.75, 0), glow_material(Color(0.75, 0.93, 1.0), 0.9), Vector3.ZERO, Vector3(1, 0.75, 1))
		spout.set_meta("dynamic", true)
		_bobbers.append({"node": spout, "base": spout.position, "amp": 0.12, "speed": 2.2, "phase": 0.0})
		for i in 8:  # 물줄기 방울
			var a := TAU * i / 8.0
			var d := add_mesh(sphere_mesh(0.14, 8), Vector3(cos(a) * 1.9, 1.9, sin(a) * 1.9), glow_material(Color(0.8, 0.95, 1.0), 0.8))
			d.set_meta("dynamic", true)
			_bobbers.append({"node": d, "base": d.position, "amp": 0.35, "speed": 3.0, "phase": i * 0.8})

	# ---------------------------------------------------------------- 스폰 지점: 분수 주변 링
	for i in 12:
		var ang := TAU * i / 12.0
		spawn_points.append(Vector3(sin(ang) * 6.0, 0.5, cos(ang) * 6.0))

	# ---------------------------------------------------------------- 경사로(20°) → 전망대
	add_box(Vector3(12, 1.6, -8), Vector3(4, 0.5, 10), STONE, Vector3(20, 0, 0))
	add_box(Vector3(12, 2.95, -15.7), Vector3(6, 1.0, 6), STONE)
	add_label(Vector3(12, 5.6, -15.7), "전망대", 72, Color(1.0, 0.96, 0.8))
	if not is_headless:
		for x in [-2.8, 2.8]:  # 난간 기둥과 꽃화분
			for z in [-2.8, 2.8]:
				add_mesh(cyl_mesh(0.18, 0.22, 0.9, 10), Vector3(12 + x, 3.9, -15.7 + z), WOOD)
		add_flowers(Vector3(12, 3.45, -15.7), 1.6, 18, 7)
		add_lamp(Vector3(9.6, 0, -2.8))
		add_lamp(Vector3(14.4, 0, -2.8))

	# ---------------------------------------------------------------- 계단 (단 높이 0.2m)
	for i in 8:
		var h := 0.2 * (i + 1)
		add_box(Vector3(-12, h * 0.5, -6 - 0.8 * i), Vector3(4, h, 0.8), STONE.darkened(0.03 * (i % 2)))
	add_box(Vector3(-12, 0.8, -14), Vector3(4, 1.6, 2.4), STONE)
	if not is_headless:
		add_bush(Vector3(-14.8, 0, -9.0), 1.0)
		add_bush(Vector3(-9.2, 0, -9.5), 0.9, Color(0.5, 0.8, 0.45))
		add_tree(Vector3(-12, 1.6, -14.6), 2, 0.6, false)

	# ---------------------------------------------------------------- 게임 모드 포털
	for i in MODE_PORTALS.size():
		var ang := deg_to_rad(-60.0 + 30.0 * i)
		var center := Vector3(sin(ang) * 19.0, 0, cos(ang) * 19.0)
		var c: Color = MODE_PORTALS[i][1]
		var side := Vector3(cos(ang), 0, -sin(ang)) * 2.2
		# 충돌용 기둥 (위치·크기는 예전과 같음. 모습은 아래 둥근 아치가 대신함)
		add_box(center + side + Vector3(0, 1.75, 0), Vector3(0.5, 3.5, 0.5), c, Vector3(0, rad_to_deg(ang), 0), true, false)
		add_box(center - side + Vector3(0, 1.75, 0), Vector3(0.5, 3.5, 0.5), c, Vector3(0, rad_to_deg(ang), 0), true, false)
		_build_portal_visual(center, ang, c)
		add_label(center + Vector3(0, 5.6, 0), MODE_PORTALS[i][0], 84, c.lightened(0.55))
		add_label(center + Vector3(0, 4.85, 0), "올라서면 입장", 44, Color(1, 1, 1, 0.9))
		portals.append({"mode": MODE_PORTALS[i][2], "center": center, "radius": 2.0})

	# ---------------------------------------------------------------- 나무 (줄기 충돌 위치 유지) & 벤치
	var trees := [Vector3(18, 0, 6), Vector3(-19, 0, 2), Vector3(5, 0, -21), Vector3(-5, 0, -22), Vector3(22, 0, -6)]
	for i in trees.size():
		add_tree(trees[i], [0, 2, 1, 0, 2][i], 1.0, true)
	for ang_deg in [45.0, 135.0, 225.0, 315.0]:
		var a := deg_to_rad(ang_deg)
		var bp := Vector3(sin(a) * 9.0, 0.25, cos(a) * 9.0)
		add_box(bp, Vector3(2.4, 0.5, 0.7), WOOD, Vector3(0, ang_deg, 0), true, false)
		if not is_headless:
			var bench := Node3D.new()
			bench.position = bp
			bench.rotation_degrees.y = ang_deg
			add_child(bench)
			add_mesh(BoxMesh.new(), Vector3(0, 0.12, 0), WOOD, Vector3.ZERO, Vector3(2.4, 0.16, 0.7), bench)
			add_mesh(BoxMesh.new(), Vector3(0, 0.55, 0.3), WOOD.lightened(0.08), Vector3(-12, 0, 0), Vector3(2.4, 0.5, 0.12), bench)
			for lx in [-1.0, 1.0]:
				add_mesh(BoxMesh.new(), Vector3(lx, -0.12, 0), WOOD.darkened(0.2), Vector3.ZERO, Vector3(0.14, 0.3, 0.6), bench)
			add_bush(bp + Vector3(sin(a), 0, cos(a)) * 1.4 + Vector3(0, -0.25, 0), 0.75)

	# ---------------------------------------------------------------- 시각 장식: 꽃밭·덤불·가로등·나무 더
	if not is_headless:
		for p in [Vector3(20, 0, 10), Vector3(-21, 0, -3), Vector3(2, 0, -24), Vector3(24, 0, -11), Vector3(-22, 0, 8), Vector3(-8, 0, -18)]:
			add_flowers(p, 2.2, 26, int(p.x * 7 + p.z))
			add_bush(p + Vector3(1.6, 0, 1.0), 0.8)
		for p in [Vector3(-24, 0, -10), Vector3(25, 0, 3), Vector3(-10, 0, -24), Vector3(14, 0, -22)]:
			add_tree(p, 1, 0.85, false)
		for i in 4:  # 스폰 방향(30° 간격)을 피해 배치 → 카메라 앞을 가리지 않음
			var a := deg_to_rad(15.0 + 90.0 * i)
			add_lamp(Vector3(sin(a) * 13.0, 0, cos(a) * 13.0), Color(1.0, 0.9, 0.7))

	# ---------------------------------------------------------------- 섬 밖: 떠 있는 작은 섬, 구름, 풍선
	if not is_headless:
		for i in 6:
			var a := TAU * i / 6.0 + 0.4
			var p := Vector3(sin(a) * 45.0, -6.0 + (i % 3) * 4.0, cos(a) * 45.0)
			add_mesh(cyl_mesh(4.0, 4.0, 1.5, 32), p, GRASS)
			add_mesh(cyl_mesh(4.15, 3.9, 0.5, 32), p + Vector3(0, -0.85, 0), GRASS_EDGE)
			add_island_underside(p + Vector3(0, -1.0, 0), 3.9, 5.0, ROCK)
			add_tree(p + Vector3(0.8, 0.75, -0.5), i % 3, 0.75, false)
			add_flowers(p + Vector3(0, 0.75, 0), 3.0, 14, i + 20)
		for i in 12:
			var a := TAU * i / 12.0 + 0.2
			var r := 62.0 + (i % 3) * 10.0
			add_cloud(Vector3(sin(a) * r, 4.0 + (i % 4) * 4.0, cos(a) * r), 1.0 + (i % 3) * 0.3)
		for i in 6:  # 섬 아래 구름 → 아득한 높이감
			var a := TAU * i / 6.0
			add_cloud(Vector3(sin(a) * 34.0, -22.0 - (i % 2) * 4.0, cos(a) * 34.0), 1.8)
		var balloon_colors := [Color(1.0, 0.55, 0.65), Color(0.6, 0.8, 1.0), Color(1.0, 0.85, 0.4), Color(0.7, 0.95, 0.6), Color(0.82, 0.68, 1.0)]
		for i in 10:
			var a := TAU * i / 10.0 + 0.15
			var p := Vector3(sin(a) * (31.0 + (i % 3) * 3.0), 6.0 + (i % 4) * 1.6, cos(a) * (31.0 + (i % 3) * 3.0))
			var bal := Node3D.new()
			bal.position = p
			add_child(bal)
			add_mesh(sphere_mesh(0.8, 16), Vector3.ZERO, balloon_colors[i % 5], Vector3.ZERO, Vector3(1, 1.18, 1), bal)
			add_mesh(cyl_mesh(0.015, 0.015, 2.4, 4), Vector3(0, -2.1, 0), Color(1, 1, 1), Vector3.ZERO, Vector3.ONE, bal)
			bal.set_meta("dynamic", true)
			_bobbers.append({"node": bal, "base": p, "amp": 0.5, "speed": 0.8 + (i % 3) * 0.2, "phase": i * 1.3})


## 포털 모습: 둥근 아치 링 + 소용돌이 + 빛나는 바닥 + 떠오르는 반짝이
func _build_portal_visual(center: Vector3, ang: float, c: Color) -> void:
	if is_headless:
		return
	var root := Node3D.new()
	root.position = center
	root.rotation.y = ang   # 로컬 +Z = 섬 바깥쪽, +X = 기둥 방향
	add_child(root)
	# 바닥: 받침 + 빛나는 원판 + 테두리
	add_mesh(cyl_mesh(2.6, 2.8, 0.25, 40), Vector3(0, 0.1, 0), STONE, Vector3.ZERO, Vector3.ONE, root)
	add_mesh(cyl_mesh(2.05, 2.05, 0.06, 40), Vector3(0, 0.25, 0), glow_material(c.lightened(0.25), 1.3), Vector3.ZERO, Vector3.ONE, root)
	# 기둥 (충돌 상자 위치) + 아치 링
	for sx in [-1.0, 1.0]:
		add_mesh(cyl_mesh(0.34, 0.42, 3.4, 16), Vector3(2.2 * sx, 1.8, 0), c.darkened(0.15), Vector3.ZERO, Vector3.ONE, root)
		add_mesh(sphere_mesh(0.42, 14), Vector3(2.2 * sx, 3.55, 0), c.lightened(0.35), Vector3.ZERO, Vector3.ONE, root)
		add_mesh(cyl_mesh(0.5, 0.55, 0.3, 16), Vector3(2.2 * sx, 0.3, 0), STONE.darkened(0.05), Vector3.ZERO, Vector3.ONE, root)
	var torus := TorusMesh.new()
	torus.inner_radius = 2.0
	torus.outer_radius = 2.55
	torus.rings = 40
	torus.ring_segments = 12
	add_mesh(torus, Vector3(0, 2.1, 0), c, Vector3(90, 0, 0), Vector3.ONE, root)
	# 링 위 장식 구슬
	for k in 7:
		var t := PI * (0.15 + 0.7 * k / 6.0)
		add_mesh(sphere_mesh(0.16, 10), Vector3(cos(t) * 2.28, 2.1 + sin(t) * 2.28, 0.32), glow_material(c.lightened(0.6), 1.4), Vector3.ZERO, Vector3.ONE, root)
	# 소용돌이 (셰이더 애니메이션)
	var swirl_mat := ShaderMaterial.new()
	swirl_mat.shader = PORTAL_SHADER
	swirl_mat.set_shader_parameter("color", c)
	var quad := QuadMesh.new()
	quad.size = Vector2(4.1, 4.1)
	var sw := add_mesh(quad, Vector3(0, 2.1, 0), swirl_mat, Vector3.ZERO, Vector3.ONE, root)
	sw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 떠오르는 반짝이 (CPU 파티클: 웹·모바일 모두 동작, 16개)
	var pt := CPUParticles3D.new()
	pt.amount = 16
	pt.lifetime = 2.2
	pt.mesh = sphere_mesh(0.07, 6)
	pt.material_override = glow_material(c.lightened(0.5), 2.0)
	pt.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	pt.emission_ring_axis = Vector3.UP
	pt.emission_ring_radius = 1.9
	pt.emission_ring_inner_radius = 0.3
	pt.emission_ring_height = 0.1
	pt.direction = Vector3.UP
	pt.spread = 12.0
	pt.gravity = Vector3(0, 0.6, 0)
	pt.initial_velocity_min = 0.6
	pt.initial_velocity_max = 1.2
	pt.scale_amount_min = 0.6
	pt.scale_amount_max = 1.3
	pt.position = Vector3(0, 0.3, 0)
	root.add_child(pt)


func _process(delta: float) -> void:
	if is_headless:
		return
	_t += delta
	for b in _bobbers:
		var n: Node3D = b["node"]
		n.position = b["base"] + Vector3(0, sin(_t * b["speed"] + b["phase"]) * b["amp"], 0)
