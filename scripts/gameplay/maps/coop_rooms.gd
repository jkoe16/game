class_name CoopRoomsMap
extends GameMap
## 협동 미션: 방 3개 + 목표 방이 +Z로 이어지고, 방 사이를 문(gate)이 막는다.
## 각 방에 발판 4개. 모드가 정한 필요 인원만큼 동시에 밟으면 다음 문이 열린다.

const PLATE_RADIUS := 1.2
const ROOM_LEN := 20.0
const PLATE_IDLE := Color(0.95, 0.55, 0.35)
const PLATE_ON := Color(0.45, 0.95, 0.5)

var stage_plates: Array = []      # [stage] -> Array[Vector3]
var _plate_meshes: Array = []     # [stage] -> Array[MeshInstance3D] (클라이언트)


func _ready() -> void:
	map_id = "coop_rooms"
	display_name = "협동 미션: 하늘 신전"
	kill_height = -10.0
	setup_environment(Color(0.45, 0.7, 0.9), Color(0.95, 0.95, 0.85), Vector3(-65, 20, 0))
	var floor_len := ROOM_LEN * 4.0
	add_box(Vector3(0, -0.5, floor_len * 0.5 - 10.0), Vector3(16, 1, floor_len), Color(0.9, 0.85, 0.7))
	for side in [-1.0, 1.0]:
		add_box(Vector3(8.5 * side, 2, floor_len * 0.5 - 10.0), Vector3(1, 4, floor_len), Color(0.9, 0.8, 0.65))
	add_box(Vector3(0, 2, -10.5), Vector3(18, 4, 1), Color(0.9, 0.8, 0.65))

	for s in 3:
		var cz := s * ROOM_LEN
		var plates: Array = []
		var meshes: Array = []
		for p in [Vector3(-4, 0, cz - 3), Vector3(4, 0, cz - 3), Vector3(-4, 0, cz + 4), Vector3(4, 0, cz + 4)]:
			plates.append(p)
			if not is_headless:
				var mi := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = PLATE_RADIUS
				cm.bottom_radius = PLATE_RADIUS
				cm.height = 0.08
				mi.mesh = cm
				mi.material_override = toon_material(PLATE_IDLE)
				mi.position = p + Vector3(0, 0.04, 0)
				add_child(mi)
				meshes.append(mi)
		stage_plates.append(plates)
		_plate_meshes.append(meshes)
		add_gate(Vector3(0, 2, cz + 9.5), Vector3(16, 4, 1))
		add_label(Vector3(0, 5.2, cz + 9.5), "%d번 문" % (s + 1), 64)
	add_label(Vector3(0, 3, 3 * ROOM_LEN), "목표 도착!", 96, Color(1, 0.95, 0.5))

	for i in 8:
		spawn_points.append(Vector3(-5.25 + i * 1.5, 0.5, -7.0))
	_decorate()


## 시각 장식: 방마다 다른 색 카펫, 벽 위 장식 띠와 벽등, 모서리 화분, 목표 방 보물
func _decorate() -> void:
	if is_headless:
		return
	var floor_len := ROOM_LEN * 4.0
	var rug_cols := [Color(0.75, 0.85, 1.0), Color(1.0, 0.82, 0.88), Color(0.82, 0.95, 0.78), Color(1.0, 0.92, 0.65)]
	for s in 4:
		var cz := s * ROOM_LEN
		var rug := BoxMesh.new()
		rug.size = Vector3(13.0, 0.03, 15.0)
		add_mesh(rug, Vector3(0, 0.015, cz + 0.5), rug_cols[s])
		var rim := BoxMesh.new()
		rim.size = Vector3(11.8, 0.035, 13.8)
		add_mesh(rim, Vector3(0, 0.02, cz + 0.5), rug_cols[s].lightened(0.35))
		for sx in [-1.0, 1.0]:
			for pz in [cz - 7.0, cz + 7.0]:
				add_mesh(cyl_mesh(0.42, 0.32, 0.6, 12), Vector3(6.9 * sx, 0.3, pz), Color(0.9, 0.6, 0.45))
				add_bush(Vector3(6.9 * sx, 0.5, pz), 0.55)
			# 벽 횃불 + 기둥
			add_mesh(cyl_mesh(0.08, 0.06, 0.7, 8), Vector3(7.75 * sx, 2.6, cz), Color(0.5, 0.35, 0.28), Vector3(0, 0, -20 * sx))
			add_mesh(sphere_mesh(0.22, 10), Vector3(7.62 * sx, 3.0, cz), glow_material(Color(1.0, 0.65, 0.3), 2.2), Vector3.ZERO, Vector3(1, 1.5, 1))
			for pz in [cz - 9.5, cz + 9.5]:
				add_mesh(cyl_mesh(0.42, 0.48, 4.0, 14), Vector3(7.6 * sx, 2.0, pz), Color(0.95, 0.88, 0.75))
				add_mesh(BoxMesh.new(), Vector3(7.6 * sx, 4.05, pz), Color(0.98, 0.92, 0.8), Vector3.ZERO, Vector3(1.1, 0.25, 1.1))
	var cap := BoxMesh.new()
	cap.size = Vector3(1.3, 0.25, floor_len)
	for sx in [-1.0, 1.0]:
		add_mesh(cap, Vector3(8.5 * sx, 4.1, floor_len * 0.5 - 10.0), Color(0.85, 0.88, 1.0))
	# 목표 방: 받침대 + 빛나는 보물 별
	var gz := 3 * ROOM_LEN
	add_mesh(cyl_mesh(1.3, 1.5, 0.6, 24), Vector3(0, 0.3, gz + 5.0), Color(0.95, 0.9, 0.85))
	add_mesh(sphere_mesh(0.7, 18), Vector3(0, 1.4, gz + 5.0), glow_material(Color(1.0, 0.85, 0.3), 1.8))
	add_flowers(Vector3(0, 0, gz + 5.0), 2.6, 30, 77)


func stage_start(stage: int) -> Vector3:
	return Vector3(0, 0.5, clampi(stage, 0, 3) * ROOM_LEN - 6.0)


func apply_mode_state(state: Dictionary) -> void:
	var extra: Dictionary = state.get("extra", {})
	var opened: Array = extra.get("opened", [])
	for i in gates.size():
		set_gate_open(i, opened.has(i))
	var stage := int(extra.get("stage", 0))
	var occ: Array = extra.get("occupied", [])
	for s in _plate_meshes.size():
		for k in _plate_meshes[s].size():
			var on: bool = s < stage or (s == stage and k < occ.size() and occ[k] == true)
			(_plate_meshes[s][k] as MeshInstance3D).material_override = toon_material(PLATE_ON if on else PLATE_IDLE)


func get_bot_target(pos: Vector3, state: Dictionary, my_id: int) -> Vector3:
	var extra: Dictionary = state.get("extra", {})
	var stage := int(extra.get("stage", 0))
	if stage >= stage_plates.size():
		return Vector3(0, 0, 3 * ROOM_LEN)
	# 봇마다 서로 다른 발판을 맡는다: 참가자 id를 정렬한 순번으로 배정 (사람끼리도 "각자 하나씩"이 핵심 규칙)
	var plates: Array = stage_plates[stage]
	var ids: Array = []
	for k in state.get("players", {}):
		ids.append(int(k))
	ids.sort()
	var idx := maxi(ids.find(my_id), 0)
	return plates[idx % plates.size()] if pos.z > -100 else plates[0]
