class_name GameMap
extends Node3D
## 모든 맵의 공통 기반. 서버와 클라이언트가 같은 맵 씬을 로드하므로 충돌 판정이 동일하다.
## 헤드리스(서버)에서는 조명/환경/장식 같은 시각 요소를 만들지 않는다.

@export var map_id := ""
@export var display_name := ""
@export var kill_height := -25.0

var spawn_points: Array[Vector3] = []
var is_headless := DisplayServer.get_name() == "headless"

# ---- 동적 월드 (틱 번호로 결정론적으로 계산 → 서버/클라이언트 동기화 메시지 불필요)
var sweepers: Array[Dictionary] = []   # 회전 막대
var movers: Array[Dictionary] = []     # 왕복 이동 발판
var pads: Array[Dictionary] = []       # 부스트/점프 패드
var gates: Array[Node3D] = []          # 모드가 여닫는 벽
## 가속 회전 막대의 기준 틱 (생존 모드 라운드 시작 틱, 모드 상태로 동기화)
var round_start_tick := 0

const PLAYER_RADIUS := 0.45
const PLAYER_HEIGHT := 1.6

static var _material_cache := {}


func get_spawn_point(index: int) -> Vector3:
	if spawn_points.is_empty():
		return Vector3(0, 1, 0)
	return spawn_points[posmod(index, spawn_points.size())]


func add_box(pos: Vector3, size: Vector3, color: Color, rot_deg := Vector3.ZERO, collide := true) -> Node3D:
	var root := _make_root(collide)
	root.position = pos
	root.rotation_degrees = rot_deg
	if collide:
		var shape := BoxShape3D.new()
		shape.size = size
		_add_shape(root, shape)
	if not is_headless:
		var mesh := BoxMesh.new()
		mesh.size = size
		_add_mesh(root, mesh, color)
	add_child(root)
	return root


func add_cylinder(pos: Vector3, radius: float, height: float, color: Color, collide := true, segments := 48) -> Node3D:
	var root := _make_root(collide)
	root.position = pos
	if collide:
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		_add_shape(root, shape)
	if not is_headless:
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = height
		mesh.radial_segments = segments
		_add_mesh(root, mesh, color)
	add_child(root)
	return root


## 시각 전용 구 (충돌 없음): 나무 잎, 구름 등
func add_deco_sphere(pos: Vector3, radius: float, color: Color, scl := Vector3.ONE) -> void:
	if is_headless:
		return
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = toon_material(color)
	mi.position = pos
	mi.scale = scl
	add_child(mi)


func add_label(pos: Vector3, text: String, size := 96, color := Color.WHITE) -> void:
	if is_headless:
		return
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = size
	l.outline_size = 18
	l.modulate = color
	l.outline_modulate = Color(0.15, 0.12, 0.25)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = 0.01
	add_child(l)


func setup_environment(sky_top: Color, sky_horizon: Color, sun_rot_deg: Vector3) -> void:
	if is_headless:
		return
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = sky_top
	sky_mat.sky_horizon_color = sky_horizon
	sky_mat.ground_horizon_color = sky_horizon
	sky_mat.ground_bottom_color = sky_top.darkened(0.2)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.ambient_light_sky_contribution = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = sun_rot_deg
	sun.light_energy = 0.95
	# Compatibility 렌더러(웹·저사양 폴백)에서 그림자 켠 방향광 + 커스텀 light()가 과노출(전부 흰색)됨 → 그림자 끔
	sun.shadow_enabled = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)


static func toon_material(color: Color) -> ShaderMaterial:
	var key := color.to_html()
	if not _material_cache.has(key):
		_material_cache[key] = CharacterVisual._toon(color)
	return _material_cache[key]


func _make_root(collide: bool) -> Node3D:
	if collide:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		return sb
	return Node3D.new()


func _add_shape(root: Node3D, shape: Shape3D) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	root.add_child(cs)


func _add_mesh(root: Node3D, mesh: Mesh, color: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = toon_material(color)
	root.add_child(mi)


# ================================================================== 동적 월드 API

## 회전 막대. arms=2면 양쪽으로 뻗은 막대. omega/accel 단위: 도/초, 도/초²
func add_sweeper(center: Vector3, radius: float, bar_y: float, omega_deg: float, phase_deg := 0.0, accel_deg := 0.0, arms := 1, thickness := 0.4, color := Color(1.0, 0.45, 0.4)) -> void:
	var pivot := Node3D.new()
	pivot.position = Vector3(center.x, bar_y, center.z)
	add_child(pivot)
	if not is_headless:
		var bar := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(thickness, thickness, radius * (2.0 if arms == 2 else 1.0))
		bar.mesh = mesh
		bar.material_override = toon_material(color)
		bar.position = Vector3(0, 0, 0.0 if arms == 2 else radius * 0.5)
		pivot.add_child(bar)
		var hub := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.5
		hm.bottom_radius = 0.6
		hm.height = bar_y - center.y + 0.4
		hub.mesh = hm
		hub.material_override = toon_material(Color(0.95, 0.85, 0.3))
		hub.position = Vector3(0, -(bar_y - center.y) * 0.5 + 0.2, 0)
		pivot.add_child(hub)
	sweepers.append({
		"center": center, "radius": radius, "y": bar_y, "omega": deg_to_rad(omega_deg),
		"phase": deg_to_rad(phase_deg), "accel": deg_to_rad(accel_deg), "arms": arms,
		"half": thickness * 0.5, "pivot": pivot,
	})


func sweeper_angle(s: Dictionary, tick: int) -> float:
	if s["accel"] != 0.0:
		var t := maxf(0.0, float(tick - round_start_tick)) / 60.0
		return s["phase"] + s["omega"] * t + 0.5 * s["accel"] * t * t
	return s["phase"] + s["omega"] * float(tick) / 60.0


## 왕복 이동 발판 (a ↔ b, 코사인 감속). 반환: 발판 번호
func add_mover(a: Vector3, b: Vector3, size: Vector3, period_sec: float, phase := 0.0, color := Color(0.55, 0.75, 1.0)) -> int:
	var body := AnimatableBody3D.new()
	body.sync_to_physics = false
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	if not is_headless:
		var mesh := BoxMesh.new()
		mesh.size = size
		_add_mesh(body, mesh, color)
	body.set_meta("mover_index", movers.size())
	add_child(body)
	body.global_position = a
	movers.append({"node": body, "a": a, "b": b, "period": period_sec * 60.0, "phase": phase})
	return movers.size() - 1


func mover_pos(i: int, tick: int) -> Vector3:
	var m: Dictionary = movers[i]
	var u := 0.5 - 0.5 * cos(TAU * (float(tick) / m["period"] + m["phase"]))
	return (m["a"] as Vector3).lerp(m["b"], u)


## kind: "boost"(가속) | "jump"(높이 점프). half: 영역 반크기
func add_pad(kind: String, center: Vector3, half: Vector3, power := 15.0) -> void:
	pads.append({"kind": kind, "center": center, "half": half, "power": power})
	if not is_headless:
		var c := Color(1.0, 0.85, 0.2) if kind == "boost" else Color(0.4, 1.0, 0.6)
		add_box(center + Vector3(0, 0.03, 0), Vector3(half.x * 2.0, 0.06, half.z * 2.0), c, Vector3.ZERO, false)
		add_label(center + Vector3(0, 1.2, 0), "▲▲" if kind == "boost" else "⤒", 48, c)


func add_gate(pos: Vector3, size: Vector3, color := Color(0.75, 0.55, 0.95)) -> int:
	var g := add_box(pos, size, color)
	gates.append(g)
	return gates.size() - 1


func set_gate_open(i: int, open: bool) -> void:
	if i < 0 or i >= gates.size():
		return
	var g := gates[i]
	g.visible = not open
	for c in g.get_children():
		if c is CollisionShape3D:
			c.set_deferred("disabled", open)
			c.disabled = open


## 틱 번호에 맞춰 이동 발판/회전 막대 위치를 설정 (시뮬레이션 직전에 호출)
func update_world(tick: int) -> void:
	for i in movers.size():
		(movers[i]["node"] as Node3D).global_position = mover_pos(i, tick)
	for s in sweepers:
		(s["pivot"] as Node3D).rotation.y = sweeper_angle(s, tick)


## 이동 직전: 이동 발판 위에 서 있으면 발판 이동량만큼 함께 이동
func pre_move(body: PlayerBody, tick: int) -> void:
	if body.floor_mover >= 0 and body.floor_mover < movers.size():
		body.global_position += mover_pos(body.floor_mover, tick) - mover_pos(body.floor_mover, tick - 1)


## 이동 직후: 발판 탑승 판정, 패드, 회전 막대 넉백
func post_move(body: PlayerBody, tick: int) -> void:
	body.floor_mover = -1
	if body.is_on_floor() and not movers.is_empty():
		# 가만히 서 있으면 슬라이드 충돌이 보고되지 않으므로, 발밑을 짧게 검사해 발판을 찾는다
		var col := KinematicCollision3D.new()
		if body.test_move(body.global_transform, Vector3(0, -0.15, 0), col):
			var obj := col.get_collider()
			if obj and obj.has_meta("mover_index") and col.get_normal().y > 0.6:
				body.floor_mover = int(obj.get_meta("mover_index"))
	var p := body.global_position
	for pad in pads:
		var d: Vector3 = (p - pad["center"]).abs()
		var h: Vector3 = pad["half"]
		if d.x <= h.x and d.z <= h.z and d.y <= h.y + 0.3:
			if pad["kind"] == "boost":
				body.boost_time = 1.5
			elif body.velocity.y <= 1.0:
				body.velocity.y = pad["power"]
				body.air_time = PlayerBody.COYOTE_TIME + 0.001
	if body.stun_time > 0.0:
		return
	for s in sweepers:
		var hit := sweeper_hit(s, p, tick)
		if hit != Vector3.ZERO:
			body.knock(hit, 0.7)
			return


## 회전 막대 충돌 판정. 맞으면 넉백 벡터, 아니면 ZERO
func sweeper_hit(s: Dictionary, p: Vector3, tick: int) -> Vector3:
	var y: float = s["y"]
	var half: float = s["half"]
	if p.y > y + half or p.y + PLAYER_HEIGHT < y - half:
		return Vector3.ZERO
	var r := Vector2(p.x - s["center"].x, p.z - s["center"].z)
	if r.length() > s["radius"] + PLAYER_RADIUS:
		return Vector3.ZERO
	var base := sweeper_angle(s, tick)
	for k in int(s["arms"]):
		var a := base + TAU * k / float(s["arms"])
		var d := Vector2(sin(a), cos(a))
		var along := r.dot(d)
		var perp := absf(r.x * d.y - r.y * d.x)
		if along >= -PLAYER_RADIUS and along <= s["radius"] and perp <= half + PLAYER_RADIUS:
			var tangent := Vector2(cos(a), -sin(a)) * signf(s["omega"] if s["omega"] != 0.0 else 1.0)
			var away := d * 0.4 + tangent
			away = away.normalized()
			return Vector3(away.x * 9.0, 7.0, away.y * 9.0)
	return Vector3.ZERO


# ================================================================== 모드 연동 (하위 맵에서 재정의)

## 모드 시작 위치 (출발선)
func get_start_point(index: int) -> Vector3:
	return get_spawn_point(index)


## 클라이언트: 서버가 보낸 모드 상태를 화면에 반영 (문 열림, 코인 등)
func apply_mode_state(_state: Dictionary) -> void:
	pass


## 테스트/AI 봇이 향할 목표 지점 (INF = 목표 없음)
func get_bot_target(_pos: Vector3, _state: Dictionary, _my_id: int) -> Vector3:
	return Vector3.INF
