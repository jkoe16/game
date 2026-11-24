class_name CoinArenaMap
extends GameMap
## 코인 모으기 경기장: 30×30 바닥 + 울타리 + 높이가 다른 발판 2개(경사로로 연결). 코인은 서버가 배치.

const HALF := 15.0
## 바위 (x, 높이, z) — 낮은 발판 뒤 구석에 모여 동굴 입구처럼
const ROCKS := [Vector3(-12.6, 3.2, -12.6), Vector3(-12.6, 2.4, -9.4), Vector3(-9.4, 2.4, -12.6), Vector3(12.6, 2.0, -12.6)]
const PALMS := [Vector3(12.5, 0, 12.5), Vector3(-12.5, 0, 12.5), Vector3(12.8, 0, -9.0)]
var platforms: Array[Dictionary] = [
	{"center": Vector3(-7, 0, -7), "half": Vector3(3, 0, 3), "top": 1.6},
	{"center": Vector3(7, 0, 7), "half": Vector3(3, 0, 3), "top": 3.0},
]
var _coin_nodes: Array = []
var _coin_data: Array = []


func _ready() -> void:
	map_id = "coin_arena"
	display_name = "보물섬"
	kill_height = -10.0
	setup_environment(Color(0.4, 0.62, 0.95), Color(1.0, 0.92, 0.75), Vector3(-50, -20, 0))
	add_box(Vector3(0, -0.5, 0), Vector3(HALF * 2, 1, HALF * 2), Color(0.98, 0.87, 0.6))  # 모래사장
	# 동굴 바위 (충돌 있음, 코인은 이 근처에 생기지 않음)
	for r in ROCKS:
		add_cylinder(Vector3(r.x, r.y * 0.5, r.z), r.y * 0.5, r.y, Color(0.66, 0.58, 0.55), true, 14)
	for p in PALMS:
		add_box(p + Vector3(0, 2.5, 0), Vector3(0.6, 5.0, 0.6), Color.WHITE, Vector3.ZERO, true, false)  # 야자수 줄기 충돌 (모양은 _decorate)
	for side in [-1.0, 1.0]:
		add_box(Vector3(HALF * side, 0.5, 0), Vector3(0.6, 1, HALF * 2), Color(1, 0.95, 0.85))
		add_box(Vector3(0, 0.5, HALF * side), Vector3(HALF * 2, 1, 0.6), Color(1, 0.95, 0.85))
	for p in platforms:
		var top: float = p["top"]
		add_box(Vector3(p["center"].x, top * 0.5, p["center"].z), Vector3(6, top, 6), Color(0.95, 0.7, 0.5))
	add_box(Vector3(-7, 0.8, -1.9), Vector3(3, 0.3, 4.5), Color(0.9, 0.8, 0.6), Vector3(20, 0, 0))    # 경사로 1 (-Z 쪽이 높음)
	add_box(Vector3(7, 1.5, 0.0), Vector3(3, 0.3, 8.5), Color(0.9, 0.8, 0.6), Vector3(-20, 0, 0))     # 경사로 2 (+Z 쪽이 높음)
	for i in 8:
		var a := TAU * i / 8.0
		spawn_points.append(Vector3(sin(a) * 4.0, 0.5, cos(a) * 4.0))
	_decorate()


## 시각 장식: 잔디 줄무늬, 울타리 기둥, 발판 테두리, 구석 꽃, 가운데 동전 문양
func _decorate() -> void:
	if is_headless:
		return
	# 바다 + 모래 물결 무늬
	var sea := StandardMaterial3D.new()
	sea.albedo_color = Color(0.35, 0.75, 0.95, 0.8)
	sea.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sea.roughness = 0.15
	add_mesh(cyl_mesh(40.0, 40.0, 0.2, 48), Vector3(0, -2.6, 0), sea)
	add_mesh(cyl_mesh(23.0, 24.0, 0.6, 48), Vector3(0, -2.3, 0), Color(0.98, 0.9, 0.68))
	var ripple := BoxMesh.new()
	ripple.size = Vector3(2.0, 0.02, HALF * 2 - 1.0)
	for i in 5:
		add_mesh(ripple, Vector3(-12.0 + i * 6.0, 0.01, 0), Color(0.99, 0.92, 0.72))
	for p in PALMS:
		_palm(p)
	for r in ROCKS:  # 바위 위 덩굴과 작은 돌
		add_mesh(sphere_mesh(r.y * 0.45, 12), Vector3(r.x, r.y, r.z), Color(0.72, 0.64, 0.6), Vector3.ZERO, Vector3(1, 0.6, 1))
		add_bush(Vector3(r.x + 0.6, r.y * 0.85, r.z + 0.4), 0.45, Color(0.35, 0.7, 0.45))
	# 동굴 아치 + 보물 상자 (낮은 발판 뒤)
	var arch := TorusMesh.new()
	arch.inner_radius = 1.9
	arch.outer_radius = 2.7
	arch.rings = 24
	arch.ring_segments = 10
	add_mesh(arch, Vector3(-11.0, 0.2, -11.0), Color(0.6, 0.52, 0.5), Vector3(90, 45, 0))
	_chest(Vector3(-11.6, 0, -11.6), 45.0)
	_chest(Vector3(9.5, 3.0, 9.5), -135.0)
	var post := BoxMesh.new()
	post.size = Vector3(0.8, 1.5, 0.8)
	var cols := [Color(1.0, 0.6, 0.7), Color(0.55, 0.75, 1.0), Color(1.0, 0.82, 0.35), Color(0.6, 0.88, 0.55)]
	var k := 0
	for t in range(-15, 16, 5):
		for side in [-1.0, 1.0]:
			add_mesh(post, Vector3(t, 0.75, HALF * side), cols[k % 4])
			add_mesh(post, Vector3(HALF * side, 0.75, t), cols[(k + 2) % 4])
			k += 1
	for p in platforms:
		var top: float = p["top"]
		add_edge_trim(Vector3(p["center"].x, top * 0.5, p["center"].z), Vector3(6, top, 6), Color(1, 1, 1))
	add_mesh(cyl_mesh(2.2, 2.2, 0.03, 32), Vector3(0, 0.02, 0), Color(1.0, 0.86, 0.35))
	add_mesh(cyl_mesh(1.6, 1.6, 0.035, 32), Vector3(0, 0.03, 0), Color(1.0, 0.95, 0.7))



func _palm(p: Vector3) -> void:
	var trunk := Color(0.72, 0.52, 0.36)
	for k in 5:  # 살짝 휜 줄기
		add_mesh(cyl_mesh(0.22, 0.28, 0.95, 10), p + Vector3(k * 0.12, 0.5 + k * 0.9, 0), trunk.lightened(0.05 * (k % 2)), Vector3(0, 0, -6.0 * k))
	var top := p + Vector3(0.6, 4.9, 0)
	for k in 6:
		var a := TAU * k / 6.0
		add_mesh(sphere_mesh(1.0, 10), top + Vector3(cos(a), -0.25, sin(a)) * 1.2, Color(0.35, 0.75, 0.4), Vector3(0, -rad_to_deg(a), -25), Vector3(1.6, 0.18, 0.55))
	add_mesh(sphere_mesh(0.22, 8), top + Vector3(0.2, -0.35, 0.2), Color(0.55, 0.4, 0.3))
	add_mesh(sphere_mesh(0.22, 8), top + Vector3(-0.2, -0.38, 0.1), Color(0.55, 0.4, 0.3))


func _chest(p: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.position = p
	root.rotation_degrees.y = yaw
	add_child(root)
	add_mesh(BoxMesh.new(), Vector3(0, 0.35, 0), Color(0.72, 0.45, 0.3), Vector3.ZERO, Vector3(1.2, 0.7, 0.8), root)
	add_mesh(BoxMesh.new(), Vector3(0, 0.75, -0.3), Color(0.8, 0.52, 0.35), Vector3(-35, 0, 0), Vector3(1.25, 0.12, 0.85), root)
	add_mesh(BoxMesh.new(), Vector3(0, 0.36, 0.41), Color(1.0, 0.82, 0.3), Vector3.ZERO, Vector3(0.25, 0.3, 0.04), root)
	for k in 5:
		add_mesh(cyl_mesh(0.14, 0.14, 0.05, 10), Vector3(-0.35 + k * 0.17, 0.74, 0.05 * (k % 2)), glow_material(Color(1.0, 0.82, 0.3), 1.3), Vector3.ZERO, Vector3.ONE, root)


func random_coin_points(rng: RandomNumberGenerator, n: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in n:
		var p := Vector3(rng.randf_range(-HALF + 2, HALF - 2), 1.0, rng.randf_range(-HALF + 2, HALF - 2))
		for pl in platforms:
			var d: Vector3 = (p - pl["center"]).abs()
			if d.x <= 3.0 and d.z <= 3.0:
				p.y = float(pl["top"]) + 1.0
				# 발판 가운데는 보석 자리 → 금화는 가장자리 쪽으로
				var off := Vector2(p.x - pl["center"].x, p.z - pl["center"].z)
				if off.length() < 1.8:
					off = (off.normalized() if off.length() > 0.01 else Vector2(1, 1).normalized()) * 2.2
					p.x = pl["center"].x + off.x
					p.z = pl["center"].z + off.y
		# 가운데는 황금 별 자리
		if Vector2(p.x, p.z).length() < 1.8:
			p.x = 2.2
			p.z = 0.0
		# 바위·야자수 안에 생기지 않게 바깥으로 밀어낸다
		for r in ROCKS + PALMS:
			var flat: Vector2 = Vector2(p.x - r.x, p.z - r.z)
			var keep: float = (r.y * 0.5 if r.y > 0.0 else 0.4) + 1.2
			if flat.length() < keep:
				var dir: Vector2 = flat.normalized() if flat.length() > 0.01 else Vector2(1, 1).normalized()
				var q: Vector2 = Vector2(r.x, r.z) + dir * keep
				p.x = clampf(q.x, -HALF + 2, HALF - 2)
				p.z = clampf(q.y, -HALF + 2, HALF - 2)
		# 경사로 위/아래 애매한 곳은 바닥으로
		out.append(p)
	return out


func apply_mode_state(state: Dictionary) -> void:
	if is_headless:
		_coin_data = state.get("extra", {}).get("coins", [])
		return
	_coin_data = state.get("extra", {}).get("coins", [])
	while _coin_nodes.size() < _coin_data.size():
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.45
		cm.bottom_radius = 0.45
		cm.height = 0.12
		mi.mesh = cm
		mi.material_override = glow_material(Color(1.0, 0.8, 0.25), 1.15)
		mi.rotation_degrees.x = 90
		var face := MeshInstance3D.new()   # 가운데 밝은 원 (동전 무늬)
		face.mesh = cyl_mesh(0.28, 0.28, 0.14, 16)
		face.material_override = glow_material(Color(1.0, 0.95, 0.6), 1.3)
		mi.add_child(face)
		add_child(mi)
		_coin_nodes.append(mi)
	for i in _coin_nodes.size():
		var node: MeshInstance3D = _coin_nodes[i]
		if i < _coin_data.size():
			var c: Array = _coin_data[i]
			node.position = Vector3(c[0], c[1], c[2])
			node.visible = int(c[3]) == 1
			# 등급별 모양: 금화 1 · 보석 3(하늘색, 크게) · 황금 별 5(가장 크고 밝게)
			var v := int(c[4]) if c.size() > 4 else 1
			if node.get_meta("value", 0) != v:
				node.set_meta("value", v)
				node.scale = Vector3.ONE * (1.0 if v == 1 else (1.5 if v == 3 else 2.2))
				node.material_override = glow_material(Color(1.0, 0.8, 0.25) if v == 1 else (Color(0.45, 0.85, 1.0) if v == 3 else Color(1.0, 0.95, 0.4)), 1.15 if v == 1 else 1.8)
		else:
			node.visible = false


func _process(delta: float) -> void:
	for n in _coin_nodes:
		(n as Node3D).rotate_y(delta * 3.0)


func get_bot_target(pos: Vector3, state: Dictionary, _my_id: int) -> Vector3:
	var coins: Array = state.get("extra", {}).get("coins", [])
	var best := Vector3.INF
	var best_d := INF
	for c in coins:
		if int(c[3]) != 1:
			continue
		var p := Vector3(c[0], c[1] - 1.0, c[2])
		var d := pos.distance_to(p)
		if d < best_d:
			best_d = d
			best = p
	return best
