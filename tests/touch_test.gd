class_name TouchTest
extends RefCounted
## 모바일 터치 조작 테스트 (autoload가 필요해 게임 프로세스 안에서 실행).
## 실행: godot --headless --path . -- --touch-test

static var passed := 0
static var failed := 0
static var root: Node
static var tree: SceneTree


static func check(cond: bool, label: String, detail := "") -> void:
	if cond:
		passed += 1
		print("  PASS  " + label)
	else:
		failed += 1
		print("  FAIL  " + label + ("  -- " + detail if detail != "" else ""))


static func run(host: Node) -> int:
	tree = host.get_tree()
	root = host
	await tree.process_frame
	await test_touch_controls()
	print("TOUCH_TEST_RESULT passed=%d failed=%d" % [passed, failed])
	return failed


static func _touch(tc: TouchControls, idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = pos
	e.pressed = pressed
	tc._on_touch(e)


static func _drag(tc: TouchControls, idx: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = pos
	e.relative = rel
	tc._on_drag(e)


static func test_touch_controls() -> void:
	var ctrl := LocalPlayerController.new()
	var cam := ThirdPersonCamera.new()
	root.add_child(cam)
	var tc := TouchControls.new()
	tc.controller = ctrl
	tc.camera = cam
	root.add_child(tc)
	await tree.process_frame
	var v := tc._view()

	# 조이스틱: 왼쪽 아래를 누르고 위로 끝까지 밀면 "앞으로" 최대 속도
	var c := Vector2(200, v.y - 200)
	_touch(tc, 0, c, true)
	_drag(tc, 0, c + Vector2(0, -400), Vector2(0, -400))
	check(ctrl.external_move.is_equal_approx(Vector2(0, -1)), "joystick full tilt up = forward (-y), length 1", str(ctrl.external_move))
	_drag(tc, 0, c + Vector2(55, 0), Vector2(55, -400))
	check(absf(ctrl.external_move.x - 0.5) < 0.01, "joystick half tilt = half speed (analog)", str(ctrl.external_move))
	_drag(tc, 0, c + Vector2(5, 0), Vector2(-50, 0))
	check(ctrl.external_move == Vector2.ZERO, "joystick dead zone", str(ctrl.external_move))

	# 오른쪽 드래그 = 카메라 회전 (조이스틱 손가락과 동시에)
	var yaw0 := cam.yaw
	_touch(tc, 1, Vector2(v.x * 0.7, v.y * 0.4), true)
	_drag(tc, 1, Vector2(v.x * 0.7 + 80, v.y * 0.4), Vector2(80, 0))
	check(cam.yaw != yaw0, "right-side drag rotates camera while joystick held")
	_touch(tc, 1, Vector2.ZERO, false)

	_touch(tc, 0, c, false)
	check(ctrl.external_move == Vector2.ZERO, "releasing joystick stops movement")

	_touch(tc, 2, tc._jump_center(), true)
	check(ctrl.external_jump, "jump button sets jump")

	# 공정성: 조이스틱 최대값과 키보드 대각선 입력이 같은 최고 속도로 양자화되는지
	var joy := PlayerInput.new()
	joy.set_move(Vector2(0, -1))
	var kb := PlayerInput.new()
	kb.set_move(Vector2(1, -1))   # 키보드 대각선 (정규화 전)
	check(absf(joy.get_move().length() - kb.get_move().length()) < 0.01, "PC diagonal is not faster than mobile full tilt")
	tc.queue_free()
	cam.queue_free()
	ctrl.free()
	await tree.process_frame
