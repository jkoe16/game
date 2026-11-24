class_name GameMap
extends Node3D
## 모든 맵의 공통 기반. 서버와 클라이언트가 같은 맵 씬을 로드하므로 충돌 판정이 동일하다.
## 헤드리스(서버)에서는 조명/환경/장식 같은 시각 요소를 만들지 않는다.

@export var map_id := ""
@export var display_name := ""
@export var kill_height := -25.0

var spawn_points: Array[Vector3] = []
## 넓은 발판 아래에 바위층을 자동으로 붙인다 (시각 전용). 직접 꾸미는 맵은 false
var auto_underside := true
var is_headless := DisplayServer.get_name() == "headless"

# ---- 동적 월드 (틱 번호로 결정론적으로 계산 → 서버/클라이언트 동기화 메시지 불필요)
var sweepers: Array[Dictionary] = []   # 회전 막대
var movers: Array[Dictionary] = []     # 왕복 이동 발판
var pads: Array[Dictionary] = []       # 부스트/점프 패드
var gates: Array[Node3D] = []          # 모드가 여닫는 벽
## 가속 회전 막대의 기준 틱 (생존 모드 라운드 시작 틱, 모드 상태로 동기화)
var round_start_tick := 0

const PLAYER_RADIUS := 0.45
## 가속 회전 막대의 최고 각속도 (라디안/초 ≈ 160°/s). 이보다 빨라지지 않는다
const MAX_SWEEP_OMEGA := 2.8
const PLAYER_HEIGHT := 1.6

static var _material_cache := {}


func get_spawn_point(index: int) -> Vector3:
	if spawn_points.is_empty():
		return Vector3(0, 1, 0)
	return spawn_points[posmod(index, spawn_points.size())]


func add_box(pos: Vector3, size: Vector3, color: Color, rot_deg := Vector3.ZERO, collide := true, show := true) -> Node3D:
	var root := _make_root(collide)
	root.position = pos
	root.rotation_degrees = rot_deg
	if collide:
		var shape := BoxShape3D.new()
		shape.size = size
		_add_shape(root, shape)
	if not is_headless and show:
		var mesh := BoxMesh.new()
		mesh.size = size
		_add_mesh(root, mesh, color)
		if auto_underside and size.x >= 4.0 and size.z >= 4.0 and size.y <= 2.0 and rot_deg.length() < 0.1:
			_box_underside(root, size, color)
	add_child(root)
	return root


## 넓은 판 아래 층층이 좁아지는 바위 → 떠 있는 섬처럼
func _box_underside(root: Node3D, size: Vector3, color: Color) -> void:
	var rock := Color(0.74, 0.62, 0.6).lerp(color, 0.15)
	var y := -size.y * 0.5
	var k := 0.88
	for i in 3:
		var h := 0.9 + i * 0.5
		var bm := BoxMesh.new()
		bm.size = Vector3(size.x * k, h, size.z * k)
		add_mesh(bm, Vector3(0, y - h * 0.5, 0), rock.darkened(0.07 * i), Vector3.ZERO, Vector3.ONE, root)
		y -= h
		k *= 0.7


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
		if auto_underside and radius >= 4.0 and height <= 3.0:
			add_island_underside(pos + Vector3(0, -height * 0.5, 0), radius * 0.97, radius * 0.9)
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


# ================================================================== 시각 전용 장식 (서버에서는 만들지 않음)

## 메시 하나를 배치 (충돌 없음). mat가 Color면 카툰 재질
func add_mesh(mesh: Mesh, pos: Vector3, mat: Variant, rot_deg := Vector3.ZERO, scl := Vector3.ONE, parent: Node3D = null) -> MeshInstance3D:
	if is_headless:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = toon_material(mat) if mat is Color else mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	# 움직이지 않는 장식은 나중에 하나로 합친다 (_batch_static)
	if mat is Color:
		mi.set_meta("batch_color", mat)
	elif mat is StandardMaterial3D:
		mi.set_meta("batch_mat", mat)
	(parent if parent else self).add_child(mi)
	return mi


## 성능: 맵을 다 만든 뒤, 움직이지 않는 장식 메시를 재질별로 하나의 메시로 합친다.
## 카툰 색 메시들은 정점 색으로 묶어 1번, 발광 재질은 재질마다 1번 그리기로 줄어든다.
## (조상 중 meta "dynamic"이 있는 노드 = 움직이는 장식은 제외)
func _batch_static() -> void:
	var groups := {}   # key → {mat, color(bool), shadow, items: [[mesh, xform, color]]}
	var inv := global_transform.affine_inverse()
	for mi in find_children("*", "MeshInstance3D", true, false):
		if not (mi.has_meta("batch_color") or mi.has_meta("batch_mat")) or _is_dynamic(mi):
			continue
		var shadow: bool = mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var key: String
		var entry: Array
		if mi.has_meta("batch_color"):
			key = "toon/%s" % shadow
			entry = [mi.mesh, inv * mi.global_transform, mi.get_meta("batch_color")]
		else:
			var m: Material = mi.get_meta("batch_mat")
			key = "mat/%d/%s" % [m.get_instance_id(), shadow]
			entry = [mi.mesh, inv * mi.global_transform, Color.WHITE]
		if not groups.has(key):
			groups[key] = {"mat": mi.get_meta("batch_mat") if mi.has_meta("batch_mat") else null, "shadow": shadow, "items": []}
		groups[key]["items"].append(entry)
		mi.queue_free()
	for key in groups:
		var g: Dictionary = groups[key]
		var mesh := _merge_meshes(g["items"])
		if mesh == null:
			continue
		var out := MeshInstance3D.new()
		out.mesh = mesh
		if g["mat"] == null:
			var vm := ShaderMaterial.new()
			vm.shader = preload("res://shaders/toon_vertex_color.gdshader")
			out.material_override = vm
		else:
			out.material_override = g["mat"]
		if not g["shadow"]:
			out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(out)


func _is_dynamic(n: Node) -> bool:
	while n and n != self:
		if n.has_meta("dynamic"):
			return true
		n = n.get_parent()
	return false


static func _merge_meshes(items: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for it in items:
		var mesh: Mesh = it[0]
		var xf: Transform3D = it[1]
		var col: Color = it[2]
		var basis_n := xf.basis.inverse().transposed()
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var base := verts.size()
			for i in v.size():
				verts.append(xf * v[i])
				norms.append((basis_n * nn[i]).normalized() if nn.size() == v.size() else Vector3.UP)
				cols.append(col)
			var ii = arr[Mesh.ARRAY_INDEX]
			if ii == null or (ii as PackedInt32Array).is_empty():
				for i in v.size():
					idx.append(base + i)
			else:
				for i in (ii as PackedInt32Array):
					idx.append(base + i)
	if verts.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


static func cyl_mesh(top: float, bottom: float, h: float, seg := 20) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m


static func sphere_mesh(r: float, seg := 20) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = maxi(6, seg / 2)
	return m


## 통통한 나무. style 0 = 둥근 활엽수, 1 = 뾰족 침엽수, 2 = 꽃나무(분홍). collide면 줄기에 충돌
func add_tree(pos: Vector3, style := 0, size := 1.0, collide := true) -> void:
	var trunk_h := 2.2 * size
	if collide:
		var root := _make_root(true)
		root.position = pos + Vector3(0, trunk_h * 0.5, 0)
		var shape := CylinderShape3D.new()
		shape.radius = 0.35 * size
		shape.height = trunk_h
		_add_shape(root, shape)
		add_child(root)
	if is_headless:
		return
	var wood := Color(0.66, 0.45, 0.33)
	add_mesh(cyl_mesh(0.22 * size, 0.38 * size, trunk_h, 10), pos + Vector3(0, trunk_h * 0.5, 0), wood)
	match style:
		1:
			var g := Color(0.33, 0.68, 0.5)
			for i in 3:
				var r := (1.6 - i * 0.4) * size
				add_mesh(cyl_mesh(0.05, r, 1.5 * size, 14), pos + Vector3(0, trunk_h + (0.4 + i * 0.95) * size, 0), g.lightened(i * 0.07))
		_:
			var leaf := Color(0.42, 0.78, 0.42) if style == 0 else Color(1.0, 0.7, 0.82)
			var blobs := [[Vector3(0, 0.9, 0), 1.35], [Vector3(0.75, 0.55, 0.3), 0.95], [Vector3(-0.7, 0.6, -0.25), 0.9], [Vector3(0.1, 1.65, -0.1), 0.85], [Vector3(-0.2, 0.5, 0.8), 0.8]]
			for i in blobs.size():
				var b: Array = blobs[i]
				add_mesh(sphere_mesh(b[1] * size, 16), pos + Vector3(0, trunk_h, 0) + b[0] * size, leaf.lightened(0.06 * (i % 3)))


## 덤불 (구 3개 뭉치)
func add_bush(pos: Vector3, size := 1.0, color := Color(0.4, 0.74, 0.42)) -> void:
	if is_headless:
		return
	add_mesh(sphere_mesh(0.7 * size, 14), pos + Vector3(0, 0.35 * size, 0), color, Vector3.ZERO, Vector3(1.2, 0.8, 1.0))
	add_mesh(sphere_mesh(0.5 * size, 12), pos + Vector3(0.6 * size, 0.25 * size, 0.2 * size), color.lightened(0.08))
	add_mesh(sphere_mesh(0.45 * size, 12), pos + Vector3(-0.55 * size, 0.2 * size, -0.1 * size), color.darkened(0.05))


## 꽃밭: 작은 꽃 여러 개를 MultiMesh 하나로 (그리기 호출 1번)
func add_flowers(center: Vector3, radius: float, count: int, seed_val := 1) -> void:
	if is_headless:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var colors := [Color(1.0, 0.62, 0.72), Color(1.0, 0.9, 0.45), Color(0.78, 0.66, 1.0), Color(1, 1, 1), Color(1.0, 0.7, 0.45)]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = sphere_mesh(0.13, 8)
	mm.instance_count = count
	for i in count:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		var p := center + Vector3(cos(a) * r, 0.12, sin(a) * r)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(1, 0.7, 1)), p))
		mm.set_instance_color(i, colors[rng.randi() % colors.size()])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := CharacterVisual._toon(Color.WHITE)
	mat.shader = preload("res://shaders/toon_vertex_color.gdshader")
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## 푹신한 구름 (구 4개)
func add_cloud(pos: Vector3, size := 1.0) -> void:
	if is_headless:
		return
	var white := Color(1, 1, 1)
	for b in [[Vector3.ZERO, 3.0], [Vector3(2.6, -0.4, 0.4), 2.2], [Vector3(-2.5, -0.5, -0.2), 2.0], [Vector3(0.6, 1.2, -0.3), 2.0]]:
		var mi := add_mesh(sphere_mesh(b[1] * size, 14), pos + b[0] * size, white, Vector3.ZERO, Vector3(1, 0.75, 0.9))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## 가로등 (빛나는 등불, 실제 조명 없이 발광 재질만 → 성능 부담 없음)
func add_lamp(pos: Vector3, glow := Color(1.0, 0.92, 0.65)) -> void:
	if is_headless:
		return
	var metal := Color(0.45, 0.42, 0.6)
	add_mesh(cyl_mesh(0.07, 0.1, 2.6, 8), pos + Vector3(0, 1.3, 0), metal)
	add_mesh(cyl_mesh(0.22, 0.28, 0.18, 10), pos + Vector3(0, 0.09, 0), metal)
	add_mesh(sphere_mesh(0.3, 14), pos + Vector3(0, 2.85, 0), glow_material(glow, 2.2))
	add_mesh(cyl_mesh(0.02, 0.34, 0.22, 10), pos + Vector3(0, 3.22, 0), metal)


static var _glow_cache := {}


## 스스로 빛나는 재질 (unshaded). 글로우가 있는 렌더러에서는 은은하게 번진다
static func glow_material(color: Color, energy := 1.5) -> StandardMaterial3D:
	var key := "%s/%s" % [color.to_html(), energy]
	if not _glow_cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = color
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
		_glow_cache[key] = m
	return _glow_cache[key]


## 출발/결승 아치 (기둥 2개 + 위 현수막 + 구슬). 로컬 X 방향으로 폭 width. 시각 전용
func add_arch(pos: Vector3, width: float, height: float, color: Color, yaw_deg := 0.0) -> void:
	if is_headless:
		return
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = yaw_deg
	add_child(root)
	var half := width * 0.5
	for sx in [-1.0, 1.0]:
		add_mesh(cyl_mesh(0.32, 0.4, height, 14), Vector3(half * sx, height * 0.5, 0), color.darkened(0.12), Vector3.ZERO, Vector3.ONE, root)
		add_mesh(sphere_mesh(0.48, 14), Vector3(half * sx, height + 0.2, 0), color.lightened(0.4), Vector3.ZERO, Vector3.ONE, root)
		add_mesh(cyl_mesh(0.55, 0.6, 0.35, 14), Vector3(half * sx, 0.17, 0), Color(0.95, 0.9, 0.85), Vector3.ZERO, Vector3.ONE, root)
	var banner := BoxMesh.new()
	banner.size = Vector3(width, 1.1, 0.3)
	add_mesh(banner, Vector3(0, height - 0.45, 0), color, Vector3.ZERO, Vector3.ONE, root)
	var trim := BoxMesh.new()
	trim.size = Vector3(width, 0.18, 0.36)
	add_mesh(trim, Vector3(0, height + 0.12, 0), color.lightened(0.45), Vector3.ZERO, Vector3.ONE, root)
	add_mesh(trim, Vector3(0, height - 1.02, 0), color.lightened(0.45), Vector3.ZERO, Vector3.ONE, root)


## 체크무늬 띠 (결승선 등). 바닥 위 아주 얇게, X 방향 폭 width, Z 방향 깊이 depth
func add_checker(center: Vector3, width: float, depth: float, cell := 0.7, a := Color(1, 1, 1), b := Color(0.25, 0.22, 0.35)) -> void:
	if is_headless:
		return
	var nx := maxi(1, int(round(width / cell)))
	var nz := maxi(1, int(round(depth / cell)))
	var cw := width / nx
	var cd := depth / nz
	var bm := BoxMesh.new()
	bm.size = Vector3(cw, 0.04, cd)
	for i in nx:
		for k in nz:
			var p := center + Vector3(-width * 0.5 + cw * (i + 0.5), 0.02, -depth * 0.5 + cd * (k + 0.5))
			add_mesh(bm, p, a if (i + k) % 2 == 0 else b)


## 깃발 (기둥 + 삼각 깃발 모양의 납작한 상자)
func add_flag(pos: Vector3, color: Color, yaw_deg := 0.0, height := 3.2) -> void:
	if is_headless:
		return
	add_mesh(cyl_mesh(0.06, 0.08, height, 8), pos + Vector3(0, height * 0.5, 0), Color(0.95, 0.95, 1.0))
	add_mesh(sphere_mesh(0.12, 8), pos + Vector3(0, height + 0.08, 0), Color(1.0, 0.85, 0.35))
	var flag := cyl_mesh(0.0, 0.5, 0.9, 3)
	add_mesh(flag, pos + Vector3(0, height - 0.45, 0) + Vector3(0.45, 0, 0).rotated(Vector3.UP, deg_to_rad(yaw_deg)), color, Vector3(0, yaw_deg, -90), Vector3(1, 1, 0.25))


## 판 윗면 가장자리를 두르는 밝은 띠 (시각 전용)
func add_edge_trim(pos: Vector3, size: Vector3, color: Color, w := 0.35) -> void:
	if is_headless:
		return
	var top := pos.y + size.y * 0.5 + 0.015
	var bx := BoxMesh.new()
	bx.size = Vector3(size.x, 0.03, w)
	var bz := BoxMesh.new()
	bz.size = Vector3(w, 0.03, size.z)
	for s in [-1.0, 1.0]:
		add_mesh(bx, Vector3(pos.x, top, pos.z + s * (size.z * 0.5 - w * 0.5)), color)
		add_mesh(bz, Vector3(pos.x + s * (size.x * 0.5 - w * 0.5), top, pos.z), color)


## 떠 있는 섬의 아랫부분: 아래로 갈수록 좁아지는 바위층
func add_island_underside(center: Vector3, top_radius: float, depth: float, rock := Color(0.66, 0.55, 0.52)) -> void:
	if is_headless:
		return
	add_mesh(cyl_mesh(top_radius, top_radius * 0.72, depth * 0.35, 40), center + Vector3(0, -depth * 0.175, 0), rock)
	add_mesh(cyl_mesh(top_radius * 0.72, top_radius * 0.38, depth * 0.4, 32), center + Vector3(0, -depth * 0.55, 0), rock.darkened(0.08))
	add_mesh(cyl_mesh(top_radius * 0.38, 0.4, depth * 0.35, 24), center + Vector3(0, -depth * 0.925, 0), rock.darkened(0.16))


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
	sky_mat.sky_curve = 0.12
	sky_mat.sun_angle_max = 8.0
	sky_mat.energy_multiplier = 1.05
	var compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.4
	env.ambient_light_sky_contribution = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.2
	env.tonemap_exposure = 0.9
	# 공간감: 멀리 있는 것일수록 하늘색에 녹아드는 옅은 안개 (모든 렌더러 지원, 비용 거의 없음)
	env.fog_enabled = true
	env.fog_light_color = sky_horizon.lerp(sky_top, 0.25)
	# 거리 기반 안개: 가까운 곳(40m 이내)은 선명하게, 먼 섬·구름만 하늘빛으로
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 40.0
	env.fog_depth_end = 170.0
	env.fog_depth_curve = 1.6
	env.fog_density = 0.55
	env.fog_sky_affect = 0.0
	# 파스텔 색감: 채도 살짝 올리고 은은한 빛번짐
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.04
	env.glow_enabled = not compat
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = sun_rot_deg
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.97, 0.9)
	# Compatibility 렌더러(웹·저사양 폴백)에서 그림자 켠 방향광 + 커스텀 light()가 과노출(전부 흰색)됨 → 그림자 끔
	# (대신 캐릭터 발밑 원형 그림자가 모든 렌더러에서 위치감을 준다)
	sun.shadow_enabled = not compat
	sun.shadow_opacity = 0.55
	sun.shadow_blur = 2.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 50.0
	add_child(sun)
	# 반대편에서 오는 약한 하늘빛 보조광 → 그늘이 칙칙하지 않게
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, sun_rot_deg.y + 180.0, 0)
	fill.light_energy = 0.14
	fill.light_color = Color(0.75, 0.82, 1.0)
	fill.shadow_enabled = false
	add_child(fill)
	_add_backdrop()
	_batch_static.call_deferred()  # 맵 _ready가 끝난 뒤 장식 합치기


## 모든 맵 공통 원경: 멀리 떠 있는 구름과 작은 섬 → 빈 하늘 대신 깊이감 (충돌 없음, 안개에 녹아듦)
func _add_backdrop() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_id)
	var grass := Color(0.46, 0.79, 0.42)
	var rock := Color(0.72, 0.6, 0.58)
	for i in 14:
		var a := TAU * i / 14.0 + rng.randf() * 0.3
		var r := rng.randf_range(95.0, 135.0)
		add_cloud(Vector3(cos(a) * r, rng.randf_range(-6.0, 22.0), sin(a) * r), rng.randf_range(1.4, 2.4))
	for i in 6:
		var a := TAU * i / 6.0 + rng.randf() * 0.5
		var r := rng.randf_range(80.0, 110.0)
		var p := Vector3(cos(a) * r, rng.randf_range(-28.0, -12.0), sin(a) * r)
		var s := rng.randf_range(4.0, 8.0)
		add_mesh(cyl_mesh(s, s, 1.4, 20), p, grass)
		add_island_underside(p + Vector3(0, -0.7, 0), s, s * 1.4, rock)
		add_tree(p + Vector3(0, 0.7, 0), i % 3, s * 0.18, false)


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
		# 가속하다가 최고 속도(MAX_SWEEP_OMEGA)에서 멈춘다 → 끝없이 빨라져 피할 수 없게 되는 일 방지
		var t := maxf(0.0, float(tick - round_start_tick)) / 60.0
		var w0: float = s["omega"]
		var acc: float = s["accel"]
		var cap := MAX_SWEEP_OMEGA * signf(acc)
		var t_cap := maxf(0.0, (cap - w0) / acc)
		if t <= t_cap:
			return s["phase"] + w0 * t + 0.5 * acc * t * t
		return s["phase"] + w0 * t_cap + 0.5 * acc * t_cap * t_cap + cap * (t - t_cap)
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
		var c := Color(1.0, 0.82, 0.25) if kind == "boost" else Color(0.35, 0.95, 0.6)
		var base := BoxMesh.new()
		base.size = Vector3(half.x * 2.0 + 0.3, 0.08, half.z * 2.0 + 0.3)
		add_mesh(base, center + Vector3(0, 0.03, 0), Color(0.98, 0.96, 1.0))
		var glow := BoxMesh.new()
		glow.size = Vector3(half.x * 2.0, 0.1, half.z * 2.0)
		add_mesh(glow, center + Vector3(0, 0.05, 0), glow_material(c, 1.1))
		# 화살표 줄무늬 (밝은 막대 3개)
		var along_z := half.z >= half.x
		var stripe := BoxMesh.new()
		stripe.size = Vector3(half.x * 1.6, 0.04, 0.22) if along_z else Vector3(0.22, 0.04, half.z * 1.6)
		for k in 3:
			var o := (k - 1) * minf(half.z, half.x if not along_z else half.z) * 0.55
			add_mesh(stripe, center + (Vector3(0, 0.11, o) if along_z else Vector3(o, 0.11, 0)), glow_material(Color(1, 1, 1), 1.0))
		add_label(center + Vector3(0, 1.3, 0), "부스트" if kind == "boost" else "점프!", 44, c.lightened(0.3))


func add_gate(pos: Vector3, size: Vector3, color := Color(0.75, 0.55, 0.95)) -> int:
	var g := add_box(pos, size, color)
	g.set_meta("dynamic", true)  # 열고 닫히므로 장식 합치기에서 제외
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
