class_name CharacterVisual
extends Node3D
## 플레이어 외형 + 애니메이션 (클라이언트 전용, 헤드리스 서버에서는 생성하지 않음).
##
## 현재는 Blender 모델이 준비되기 전 단계의 "절차적 프로토타입 캐릭터"이다.
## 리그 노드 이름(Rig/Body/Head/HandL/HandR/FootL/FootR)과 애니메이션 이름을 고정해 두었으므로,
## 추후 GLB 모델로 교체할 때 AnimationTree 구조와 게임 코드는 그대로 재사용한다.

const TOON_SHADER := preload("res://shaders/toon.gdshader")
const EMOTE_INPUTS: Array[String] = ["wave", "dance", "victory", "defeat", "knockdown"]

const REST := {
	"Rig": Vector3(0, 0, 0),
	"Rig/Body": Vector3(0, 0.52, 0),
	"Rig/Head": Vector3(0, 1.12, 0),
	"Rig/HandL": Vector3(0.50, 0.55, 0.05),
	"Rig/HandR": Vector3(-0.50, 0.55, 0.05),
	"Rig/FootL": Vector3(0.20, 0.10, 0.02),
	"Rig/FootR": Vector3(-0.20, 0.10, 0.02),
}

## 로컬 플레이어처럼 몸체 상태를 직접 읽어올 대상 (원격 플레이어는 null, 보간기가 update_motion 호출)
var source_body: PlayerBody
var anim_player: AnimationPlayer
var anim_tree: AnimationTree

var _rig: Node3D
var _parts := {}
var _target_yaw := 0.0
var _grounded := true
var _air_timer := 0.0
var _min_air_vy := 0.0
var _eyes: Array[Node3D] = []
var _blink_in := 2.5
var _blink_t := -1.0
var _shadow: MeshInstance3D
var _shadow_mat: StandardMaterial3D
static var _shadow_tex: GradientTexture2D


func build(appearance: Dictionary) -> void:
	var a := Appearance.sanitize(appearance)
	var color: Color = Appearance.BODY_COLORS[a["color"]]
	_build_model(color, Appearance.HATS[a["hat"]])
	_build_animations()
	_build_shadow()
	_blink_in = randf_range(1.0, 4.0)


## 발밑 원형 그림자: 모든 렌더러(웹 포함)에서 캐릭터가 땅에 붙어 있는 느낌과 점프 높이를 알려 준다
func _build_shadow() -> void:
	if _shadow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.18, 0.14, 0.32, 0.55))
		g.set_color(1, Color(0.18, 0.14, 0.32, 0.0))
		g.add_point(0.55, Color(0.18, 0.14, 0.32, 0.38))
		_shadow_tex = GradientTexture2D.new()
		_shadow_tex.gradient = g
		_shadow_tex.fill = GradientTexture2D.FILL_RADIAL
		_shadow_tex.fill_from = Vector2(0.5, 0.5)
		_shadow_tex.fill_to = Vector2(1.0, 0.5)
		_shadow_tex.width = 64
		_shadow_tex.height = 64
	_shadow_mat = StandardMaterial3D.new()
	_shadow_mat.albedo_texture = _shadow_tex
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shadow_mat.render_priority = -1
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.3, 1.3)
	_shadow = MeshInstance3D.new()
	_shadow.mesh = pm
	_shadow.material_override = _shadow_mat
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.top_level = true
	add_child(_shadow)


func _update_shadow() -> void:
	if _shadow == null or not is_inside_tree():
		return
	var from := global_position + Vector3(0, 0.4, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -30, 0), 1)
	var body := get_parent() as CollisionObject3D
	if body:
		q.exclude = [body.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_shadow.visible = false
		return
	var h: float = from.y - 0.4 - hit["position"].y
	_shadow.visible = true
	_shadow.global_position = hit["position"] + Vector3(0, 0.03, 0)
	var k := clampf(1.0 - h / 6.0, 0.35, 1.0)
	_shadow.scale = Vector3(k, 1, k)
	_shadow_mat.albedo_color = Color(1, 1, 1, k)


## 2~5초마다 눈을 깜빡인다 (시각 전용)
func _update_blink(delta: float) -> void:
	if _eyes.is_empty():
		return
	if _blink_t >= 0.0:
		_blink_t += delta
		var k := absf(_blink_t / 0.07 - 1.0)  # 1 → 0 → 1
		for e in _eyes:
			e.scale.y = 1.35 * maxf(k, 0.08)
		if _blink_t >= 0.14:
			_blink_t = -1.0
			for e in _eyes:
				e.scale.y = 1.35
	else:
		_blink_in -= delta
		if _blink_in <= 0.0:
			_blink_t = 0.0
			_blink_in = randf_range(2.0, 5.0)


func _process(delta: float) -> void:
	if source_body:
		_target_yaw = source_body.facing_yaw
		update_motion(source_body.velocity, source_body.is_on_floor(), delta)
	rotation.y = lerp_angle(rotation.y, _target_yaw, 1.0 - exp(-18.0 * delta))
	_update_blink(delta)
	_update_shadow()


func set_target_yaw(yaw: float) -> void:
	_target_yaw = yaw


func update_motion(vel: Vector3, grounded: bool, delta: float) -> void:
	if anim_tree == null:
		return
	var hs := Vector2(vel.x, vel.z).length() / PlayerBody.WALK_SPEED
	anim_tree.set("parameters/loco/blend_position", clampf(hs, 0.0, 1.0))
	anim_tree.set("parameters/air/blend_position", clampf(vel.y / 8.0, -1.0, 1.0))

	if grounded:
		if not _grounded:
			anim_tree.set("parameters/state/transition_request", "ground")
			if _min_air_vy < -5.0:
				anim_tree.set("parameters/land/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		_grounded = true
		_air_timer = 0.0
		_min_air_vy = 0.0
	else:
		_air_timer += delta
		_min_air_vy = minf(_min_air_vy, vel.y)
		# 작은 턱에서 깜빡이지 않도록 짧은 공중 상태는 무시 (점프로 위로 뜰 때는 즉시 전환)
		if _grounded and (_air_timer > 0.08 or vel.y > 2.0):
			anim_tree.set("parameters/state/transition_request", "air")
			_grounded = false


func play_emote(emote_name: String) -> void:
	if anim_tree == null or not EMOTE_INPUTS.has(emote_name):
		return
	anim_tree.set("parameters/emote_type/transition_request", emote_name)
	anim_tree.set("parameters/emote/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


# ------------------------------------------------------------------ 모델

func _build_model(color: Color, hat: String) -> void:
	var body_mat := _toon(color)
	var belly_mat := _toon(color.lightened(0.45))
	var limb_mat := _toon(color.darkened(0.12))
	var eye_mat := _flat(Color(0.12, 0.1, 0.16))
	var shine_mat := _flat(Color(1, 1, 1))
	var cheek_mat := _flat(Color(1.0, 0.6, 0.66))
	var mouth_mat := _flat(Color(0.35, 0.16, 0.2))

	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)

	var body := _part("Body")
	_sphere(body, 0.42, Vector3.ZERO, Vector3(1, 1, 0.92), body_mat)
	_sphere(body, 0.28, Vector3(0, -0.05, 0.25), Vector3(1, 1, 0.45), belly_mat)

	var head := _part("Head")
	_sphere(head, 0.46, Vector3.ZERO, Vector3(1, 0.92, 0.95), body_mat)
	for side in [-1.0, 1.0]:
		# 큰 눈 + 반짝임 두 개 (눈 로컬 좌표)
		var eye := _sphere(head, 0.075, Vector3(0.155 * side, 0.03, 0.39), Vector3(1, 1.35, 0.6), eye_mat)
		_eyes.append(eye)
		_sphere(eye, 0.028, Vector3(0.025, 0.032, 0.06), Vector3(1, 0.85, 1), shine_mat)
		_sphere(eye, 0.012, Vector3(-0.02, -0.035, 0.065), Vector3.ONE, shine_mat)
		# 볼터치: 눈 바로 아래 바깥쪽, 납작한 타원
		_sphere(head, 0.07, Vector3(0.255 * side, -0.075, 0.345), Vector3(1.2, 0.65, 0.35), cheek_mat)
	# 웃는 입: 작은 구슬을 호 모양으로
	for i in 5:
		var t := (i - 2) / 2.0
		_sphere(head, 0.017, Vector3(t * 0.045, -0.09 - 0.022 * (1.0 - t * t), 0.43 - 0.01 * t * t), Vector3.ONE, mouth_mat)
	_build_hat(head, hat, color)

	for n in ["HandL", "HandR"]:
		_sphere(_part(n), 0.13, Vector3.ZERO, Vector3.ONE, body_mat)
	for n in ["FootL", "FootR"]:
		_sphere(_part(n), 0.16, Vector3.ZERO, Vector3(1, 0.6, 1.3), limb_mat)


func _build_hat(head: Node3D, hat: String, color: Color) -> void:
	match hat:
		"cat":
			var ear := _toon(color.darkened(0.05))
			var inner := _toon(Color(1.0, 0.7, 0.76))
			for side in [-1.0, 1.0]:
				var e := _cylinder(head, 0.0, 0.16, 0.28, Vector3(0.25 * side, 0.4, 0.0), ear)
				e.rotation_degrees = Vector3(-5, 0, -22 * side)
				e.scale = Vector3(1, 1, 0.6)
				var ie := _cylinder(e, 0.0, 0.1, 0.18, Vector3(0, -0.03, 0.09), inner)
				ie.scale = Vector3(1, 1, 0.4)
		"bunny":
			var ear := _toon(color.lightened(0.1))
			var inner := _toon(Color(1.0, 0.7, 0.76))
			for side in [-1.0, 1.0]:
				var e := _sphere(head, 0.09, Vector3(0.13 * side, 0.56, -0.02), Vector3(0.8, 2.4, 0.5), ear)
				e.rotation_degrees.z = -10.0 * side
				_sphere(e, 0.06, Vector3(0, 0, 0.04), Vector3(0.7, 0.9, 0.4), inner)
		"flower":
			var petal := _toon(Color(1.0, 0.95, 0.98))
			var center := _toon(Color(1.0, 0.8, 0.3))
			var pin := Node3D.new()
			pin.position = Vector3(0.28, 0.3, 0.2)
			pin.rotation_degrees = Vector3(-25, 35, -20)
			pin.scale = Vector3.ONE * 1.35
			head.add_child(pin)
			for i in 5:
				var ang := TAU * i / 5.0
				_sphere(pin, 0.06, Vector3(sin(ang) * 0.07, cos(ang) * 0.07, 0), Vector3(1, 1, 0.45), petal)
			_sphere(pin, 0.045, Vector3(0, 0, 0.02), Vector3(1, 1, 0.6), center)
		"sprout":
			var green := _toon(Color(0.4, 0.8, 0.35))
			_cylinder(head, 0.02, 0.02, 0.16, Vector3(0, 0.48, 0), green)
			for side in [-1.0, 1.0]:
				var leaf := _sphere(head, 0.09, Vector3(0.08 * side, 0.57, 0), Vector3(1, 0.25, 0.55), green)
				leaf.rotation_degrees.z = -25.0 * side
		"cap":
			var red := _toon(Color(0.9, 0.3, 0.3))
			_cylinder(head, 0.33, 0.38, 0.16, Vector3(0, 0.36, 0), red)
			var brim := _cylinder(head, 0.26, 0.26, 0.03, Vector3(0, 0.3, 0.25), red)
			brim.scale = Vector3(1, 1, 0.8)
		"crown":
			var gold := _toon(Color(1.0, 0.82, 0.25))
			_cylinder(head, 0.24, 0.2, 0.18, Vector3(0, 0.46, 0), gold)
			for i in 5:
				var ang := TAU * i / 5.0
				_sphere(head, 0.045, Vector3(sin(ang) * 0.22, 0.57, cos(ang) * 0.22), Vector3.ONE, gold)
		"bow":
			var pink := _toon(Color(1.0, 0.45, 0.65))
			for side in [-1.0, 1.0]:
				_sphere(head, 0.11, Vector3(0.12 * side, 0.4, 0.08), Vector3(1, 0.7, 0.45), pink)
			_sphere(head, 0.05, Vector3(0, 0.4, 0.1), Vector3.ONE, pink)


func _part(part_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = part_name
	n.position = REST["Rig/" + part_name]
	_rig.add_child(n)
	_parts[part_name] = n
	return n


func _sphere(parent: Node3D, radius: float, pos: Vector3, scl: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _cylinder(parent: Node3D, top: float, bottom: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 20
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _toon(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON_SHADER
	m.set_shader_parameter("albedo", color)
	return m


static func _flat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


# ------------------------------------------------------------------ 애니메이션

func _build_animations() -> void:
	var lib := AnimationLibrary.new()
	# RESET = 기본 자세. 어떤 동작에 없는 부위(예: idle의 발)는 이 값으로 돌아간다.
	# 없으면 Godot가 빠진 위치를 (0,0,0)으로 채워서 두 발·두 손이 몸 한가운데 겹쳐 보였다.
	lib.add_animation("RESET", _anim_reset())
	lib.add_animation("idle", _anim_idle())
	# 발걸음 폭을 이동 속도에 맞춰 크게 (작으면 몸이 스케이트 타듯 미끄러져 보임)
	lib.add_animation("walk", _anim_gait(0.44, 0.2, 0.1, 0.06, 0.14, 4.0, 3.0))
	lib.add_animation("run", _anim_gait(0.32, 0.3, 0.16, 0.10, 0.22, 12.0, 4.0))
	lib.add_animation("jump", _anim_jump())
	lib.add_animation("fall", _anim_fall())
	lib.add_animation("land", _anim_land())
	lib.add_animation("wave", _anim_wave())
	lib.add_animation("dance", _anim_dance())
	lib.add_animation("victory", _anim_victory())
	lib.add_animation("defeat", _anim_defeat())
	lib.add_animation("knockdown", _anim_knockdown())

	anim_player = AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	add_child(anim_player)
	anim_player.root_node = NodePath("..")
	anim_player.add_animation_library("", lib)

	var tree := AnimationNodeBlendTree.new()

	var loco := AnimationNodeBlendSpace1D.new()
	loco.min_space = 0.0
	loco.max_space = 1.0
	loco.add_blend_point(_clip("idle"), 0.0, -1, "idle")
	loco.add_blend_point(_clip("walk"), 0.45, -1, "walk")
	loco.add_blend_point(_clip("run"), 1.0, -1, "run")
	tree.add_node("loco", loco)

	var air := AnimationNodeBlendSpace1D.new()
	air.add_blend_point(_clip("fall"), -1.0, -1, "fall")
	air.add_blend_point(_clip("jump"), 1.0, -1, "jump")
	tree.add_node("air", air)

	var state := AnimationNodeTransition.new()
	state.add_input("ground")
	state.add_input("air")
	state.xfade_time = 0.12
	tree.add_node("state", state)
	tree.connect_node("state", 0, "loco")
	tree.connect_node("state", 1, "air")

	var land := AnimationNodeOneShot.new()
	land.fadein_time = 0.02
	land.fadeout_time = 0.1
	tree.add_node("land", land)
	tree.add_node("land_clip", _clip("land"))
	tree.connect_node("land", 0, "state")
	tree.connect_node("land", 1, "land_clip")

	var emote_type := AnimationNodeTransition.new()
	for i in EMOTE_INPUTS.size():
		emote_type.add_input(EMOTE_INPUTS[i])
		tree.add_node("emote_" + EMOTE_INPUTS[i], _clip(EMOTE_INPUTS[i]))
	tree.add_node("emote_type", emote_type)
	for i in EMOTE_INPUTS.size():
		tree.connect_node("emote_type", i, "emote_" + EMOTE_INPUTS[i])

	var emote := AnimationNodeOneShot.new()
	emote.fadein_time = 0.15
	emote.fadeout_time = 0.2
	tree.add_node("emote", emote)
	tree.connect_node("emote", 0, "land")
	tree.connect_node("emote", 1, "emote_type")
	tree.connect_node("output", 0, "emote")

	anim_tree = AnimationTree.new()
	anim_tree.name = "AnimationTree"
	add_child(anim_tree)
	anim_tree.root_node = NodePath("..")
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)
	anim_tree.tree_root = tree
	anim_tree.active = true


func _clip(anim_name: String) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = anim_name
	return n


func _new_anim(length: float, loop: bool) -> Animation:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	return a


## keys: [[시간, 휴식 위치 기준 오프셋], ...]
func _pos(a: Animation, path: String, keys: Array) -> void:
	var t := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(t, NodePath(path))
	for k in keys:
		a.position_track_insert_key(t, k[0], REST[path] + k[1])


## keys: [[시간, 오일러 각도(도)], ...]
func _rot(a: Animation, path: String, keys: Array) -> void:
	var t := a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(t, NodePath(path))
	for k in keys:
		a.rotation_track_insert_key(t, k[0], Quaternion.from_euler(k[1] * (PI / 180.0)))


func _scl(a: Animation, path: String, keys: Array) -> void:
	var t := a.add_track(Animation.TYPE_SCALE_3D)
	a.track_set_path(t, NodePath(path))
	for k in keys:
		a.scale_track_insert_key(t, k[0], k[1])


func _anim_reset() -> Animation:
	var a := _new_anim(0.001, false)
	for path: String in REST:
		_pos(a, path, [[0.0, Vector3.ZERO]])
		_rot(a, path, [[0.0, Vector3.ZERO]])
		_scl(a, path, [[0.0, Vector3.ONE]])
	return a


func _anim_idle() -> Animation:
	var a := _new_anim(1.6, true)
	_scl(a, "Rig", [[0.0, Vector3.ONE], [0.8, Vector3(1.03, 0.97, 1.03)], [1.6, Vector3.ONE]])
	_rot(a, "Rig/Head", [[0.0, Vector3.ZERO], [0.8, Vector3(0, 0, 3)], [1.6, Vector3.ZERO]])
	_pos(a, "Rig/HandL", [[0.0, Vector3.ZERO], [0.8, Vector3(0, -0.02, 0)], [1.6, Vector3.ZERO]])
	_pos(a, "Rig/HandR", [[0.0, Vector3.ZERO], [0.8, Vector3(0, -0.02, 0)], [1.6, Vector3.ZERO]])
	return a


func _anim_gait(length: float, stride: float, lift: float, bob: float, swing: float, pitch: float, roll: float) -> Animation:
	var a := _new_anim(length, true)
	var q := length / 4.0
	_pos(a, "Rig/FootL", [[0.0, Vector3(0, 0, stride)], [q, Vector3(0, lift, 0)], [2 * q, Vector3(0, 0, -stride)], [3 * q, Vector3.ZERO], [length, Vector3(0, 0, stride)]])
	_pos(a, "Rig/FootR", [[0.0, Vector3(0, 0, -stride)], [q, Vector3.ZERO], [2 * q, Vector3(0, 0, stride)], [3 * q, Vector3(0, lift, 0)], [length, Vector3(0, 0, -stride)]])
	_pos(a, "Rig", [[0.0, Vector3.ZERO], [q, Vector3(0, bob, 0)], [2 * q, Vector3.ZERO], [3 * q, Vector3(0, bob, 0)], [length, Vector3.ZERO]])
	_pos(a, "Rig/HandL", [[0.0, Vector3(0, 0, -swing)], [2 * q, Vector3(0, 0.03, swing)], [length, Vector3(0, 0, -swing)]])
	_pos(a, "Rig/HandR", [[0.0, Vector3(0, 0.03, swing)], [2 * q, Vector3(0, 0, -swing)], [length, Vector3(0, 0.03, swing)]])
	_rot(a, "Rig", [[0.0, Vector3(pitch, 0, roll)], [2 * q, Vector3(pitch, 0, -roll)], [length, Vector3(pitch, 0, roll)]])
	return a


func _anim_jump() -> Animation:
	var a := _new_anim(0.25, false)
	_scl(a, "Rig", [[0.0, Vector3(0.85, 1.2, 0.85)], [0.25, Vector3(0.95, 1.05, 0.95)]])
	_pos(a, "Rig/HandL", [[0.0, Vector3(0.05, 0.3, 0)]])
	_pos(a, "Rig/HandR", [[0.0, Vector3(-0.05, 0.3, 0)]])
	_pos(a, "Rig/FootL", [[0.0, Vector3(0, 0.05, -0.05)]])
	_pos(a, "Rig/FootR", [[0.0, Vector3(0, 0.08, 0.05)]])
	return a


func _anim_fall() -> Animation:
	var a := _new_anim(0.4, true)
	_pos(a, "Rig/HandL", [[0.0, Vector3(0.1, 0.35, 0)], [0.2, Vector3(0.14, 0.45, 0)], [0.4, Vector3(0.1, 0.35, 0)]])
	_pos(a, "Rig/HandR", [[0.0, Vector3(-0.14, 0.45, 0)], [0.2, Vector3(-0.1, 0.35, 0)], [0.4, Vector3(-0.14, 0.45, 0)]])
	_pos(a, "Rig/FootL", [[0.0, Vector3(0, 0.04, 0.06)], [0.2, Vector3(0, 0.08, -0.06)], [0.4, Vector3(0, 0.04, 0.06)]])
	_pos(a, "Rig/FootR", [[0.0, Vector3(0, 0.08, -0.06)], [0.2, Vector3(0, 0.04, 0.06)], [0.4, Vector3(0, 0.08, -0.06)]])
	return a


func _anim_land() -> Animation:
	var a := _new_anim(0.25, false)
	_scl(a, "Rig", [[0.0, Vector3(1.25, 0.75, 1.25)], [0.1, Vector3(0.94, 1.07, 0.94)], [0.25, Vector3.ONE]])
	return a


func _anim_wave() -> Animation:
	var a := _new_anim(1.5, false)
	var up := Vector3(0.05, 0.55, 0.1)
	var side := Vector3(0.2, 0.55, 0.1)
	_pos(a, "Rig/HandL", [[0.0, Vector3.ZERO], [0.2, up], [0.4, side], [0.6, up], [0.8, side], [1.0, up], [1.3, up], [1.5, Vector3.ZERO]])
	_rot(a, "Rig/Head", [[0.0, Vector3.ZERO], [0.3, Vector3(0, 0, 8)], [1.2, Vector3(0, 0, 8)], [1.5, Vector3.ZERO]])
	return a


func _anim_dance() -> Animation:
	var a := _new_anim(2.0, false)
	var rk: Array = []
	var pk: Array = []
	var hl: Array = []
	var hr: Array = []
	for i in 9:
		var t := i * 0.25
		var s := 0.0 if i % 2 == 0 else (1.0 if i % 4 == 1 else -1.0)
		rk.append([t, Vector3(0, 25.0 * s, 8.0 * s)])
		pk.append([t, Vector3(0, 0.0 if i % 2 == 0 else 0.12, 0)])
		hl.append([t, Vector3(0.05, 0.5, 0) if i % 4 < 2 else Vector3(0.05, 0.0, 0.1)])
		hr.append([t, Vector3(-0.05, 0.0, 0.1) if i % 4 < 2 else Vector3(-0.05, 0.5, 0)])
	_rot(a, "Rig", rk)
	_pos(a, "Rig", pk)
	_pos(a, "Rig/HandL", hl)
	_pos(a, "Rig/HandR", hr)
	return a


func _anim_victory() -> Animation:
	var a := _new_anim(1.6, false)
	var pk: Array = []
	for i in 9:
		pk.append([i * 0.2, Vector3(0, 0.45, 0) if i % 2 == 1 and i < 8 else Vector3.ZERO])
	_pos(a, "Rig", pk)
	_pos(a, "Rig/HandL", [[0.0, Vector3.ZERO], [0.15, Vector3(0.1, 0.55, 0)], [1.4, Vector3(0.1, 0.55, 0)], [1.6, Vector3.ZERO]])
	_pos(a, "Rig/HandR", [[0.0, Vector3.ZERO], [0.15, Vector3(-0.1, 0.55, 0)], [1.4, Vector3(-0.1, 0.55, 0)], [1.6, Vector3.ZERO]])
	return a


func _anim_defeat() -> Animation:
	var a := _new_anim(1.8, false)
	_rot(a, "Rig/Head", [[0.0, Vector3.ZERO], [0.3, Vector3(25, 0, 0)], [1.5, Vector3(25, 0, 5)], [1.8, Vector3.ZERO]])
	_rot(a, "Rig", [[0.0, Vector3.ZERO], [0.3, Vector3(10, 0, 0)], [1.5, Vector3(10, 0, 0)], [1.8, Vector3.ZERO]])
	_scl(a, "Rig", [[0.0, Vector3.ONE], [0.3, Vector3(1.05, 0.9, 1.05)], [1.5, Vector3(1.05, 0.9, 1.05)], [1.8, Vector3.ONE]])
	_pos(a, "Rig/HandL", [[0.0, Vector3.ZERO], [0.3, Vector3(-0.1, -0.15, 0.12)], [1.5, Vector3(-0.1, -0.15, 0.12)], [1.8, Vector3.ZERO]])
	_pos(a, "Rig/HandR", [[0.0, Vector3.ZERO], [0.3, Vector3(0.1, -0.15, 0.12)], [1.5, Vector3(0.1, -0.15, 0.12)], [1.8, Vector3.ZERO]])
	return a


func _anim_knockdown() -> Animation:
	var a := _new_anim(1.4, false)
	_rot(a, "Rig", [[0.0, Vector3.ZERO], [0.25, Vector3(-80, 0, 0)], [1.0, Vector3(-80, 0, 0)], [1.4, Vector3.ZERO]])
	_pos(a, "Rig", [[0.0, Vector3.ZERO], [0.25, Vector3(0, 0.4, -0.3)], [1.0, Vector3(0, 0.4, -0.3)], [1.4, Vector3.ZERO]])
	return a
