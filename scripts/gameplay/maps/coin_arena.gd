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
		mi.material_override = toon_material(Color(1.0, 0.85, 0.2))
		mi.rotation_degrees.x = 90
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
