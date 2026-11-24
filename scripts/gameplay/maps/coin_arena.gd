class_name CoinArenaMap
extends GameMap
## 코인 모으기 경기장: 30×30 바닥 + 울타리 + 높이가 다른 발판 2개(경사로로 연결). 코인은 서버가 배치.

const HALF := 15.0
var platforms: Array[Dictionary] = [
	{"center": Vector3(-7, 0, -7), "half": Vector3(3, 0, 3), "top": 1.6},
	{"center": Vector3(7, 0, 7), "half": Vector3(3, 0, 3), "top": 3.0},
]
var _coin_nodes: Array = []
var _coin_data: Array = []


func _ready() -> void:
	map_id = "coin_arena"
	display_name = "코인 광장"
	kill_height = -10.0
	setup_environment(Color(0.4, 0.62, 0.95), Color(1.0, 0.92, 0.75), Vector3(-50, -20, 0))
	add_box(Vector3(0, -0.5, 0), Vector3(HALF * 2, 1, HALF * 2), Color(0.6, 0.85, 0.55))
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
	var stripe := BoxMesh.new()
	stripe.size = Vector3(3.0, 0.02, HALF * 2 - 1.0)
	for i in 5:
		add_mesh(stripe, Vector3(-12.0 + i * 6.0, 0.01, 0), Color(0.68, 0.9, 0.6))
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
	# 발판 아래 꽃 (경기장 밖은 바닥이 없으므로 안쪽 구석에만)
	for c in [Vector3(-12.5, 0, 12.5), Vector3(12.5, 0, -12.5)]:
		add_flowers(c, 1.6, 18, int(c.x * 3 + 90))


func random_coin_points(rng: RandomNumberGenerator, n: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in n:
		var p := Vector3(rng.randf_range(-HALF + 2, HALF - 2), 1.0, rng.randf_range(-HALF + 2, HALF - 2))
		for pl in platforms:
			var d: Vector3 = (p - pl["center"]).abs()
			if d.x <= 3.0 and d.z <= 3.0:
				p.y = float(pl["top"]) + 1.0
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
