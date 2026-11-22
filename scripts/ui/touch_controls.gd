class_name TouchControls
extends CanvasLayer
## 모바일 터치 조작 (Phase 3). 핵심 규칙은 PC와 동일하고 입력 방식만 다르다.
##  - 화면 왼쪽 아래 아무 곳이나 누르면 그 자리에 가상 조이스틱이 생긴다 (기울기 = 속도, 최대 1)
##  - 오른쪽 화면 드래그 = 카메라 회전, 두 손가락 벌리기/모으기 = 줌
##  - 큰 점프 버튼, 감정표현 버튼(누르면 4개 펼침)
## PC에서 테스트할 때는 실행 인자 --touch 로 강제 표시 (마우스로 터치 흉내).

const JOY_RADIUS := 110.0
const DEAD_ZONE := 0.12
const BUTTON_RADIUS := 70.0

var controller: LocalPlayerController
var camera: ThirdPersonCamera
var client: GameClient

var _joy_index := -1
var _joy_center := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _cam_touches := {}         # index -> 마지막 위치 (카메라용 손가락)
var _pinch_dist := 0.0
var _emote_open := false
var _canvas: Control


func _ready() -> void:
	layer = 5
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_controls)
	add_child(_canvas)


func _process(_delta: float) -> void:
	_canvas.queue_redraw()


# ------------------------------------------------------------------ 배치

func _view() -> Vector2:
	return _canvas.get_viewport_rect().size


func _jump_center() -> Vector2:
	var v := _view()
	return Vector2(v.x - 130, v.y - 150)


func _emote_center() -> Vector2:
	var v := _view()
	return Vector2(v.x - 290, v.y - 90)


func _emote_item_center(i: int) -> Vector2:
	return _emote_center() + Vector2(-20 - i * 100, -150)


# ------------------------------------------------------------------ 입력

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)


func _on_touch(e: InputEventScreenTouch) -> void:
	var v := _view()
	if e.pressed:
		if e.position.distance_to(_jump_center()) <= BUTTON_RADIUS:
			if controller:
				controller.external_jump = true
			get_viewport().set_input_as_handled()
			return
		if e.position.distance_to(_emote_center()) <= BUTTON_RADIUS * 0.7:
			_emote_open = not _emote_open
			get_viewport().set_input_as_handled()
			return
		if _emote_open:
			for i in Appearance.EMOTES.size():
				if e.position.distance_to(_emote_item_center(i)) <= 45.0:
					if client:
						client.request_emote(i)
					_emote_open = false
					get_viewport().set_input_as_handled()
					return
		if e.position.x < v.x * 0.45 and e.position.y > v.y * 0.3 and _joy_index == -1:
			_joy_index = e.index
			_joy_center = e.position
			_joy_pos = e.position
			_update_joy()
		else:
			_cam_touches[e.index] = e.position
			_pinch_dist = _current_pinch()
		get_viewport().set_input_as_handled()
	else:
		if e.index == _joy_index:
			_joy_index = -1
			if controller:
				controller.external_move = Vector2.ZERO
		_cam_touches.erase(e.index)
		_pinch_dist = _current_pinch()


func _on_drag(e: InputEventScreenDrag) -> void:
	if e.index == _joy_index:
		_joy_pos = e.position
		_update_joy()
	elif _cam_touches.has(e.index):
		_cam_touches[e.index] = e.position
		if _cam_touches.size() >= 2:
			var d := _current_pinch()
			if camera and _pinch_dist > 0.0:
				camera.zoom((_pinch_dist - d) * 0.02)
			_pinch_dist = d
		elif camera:
			camera.rotate_by(e.relative, camera.touch_sensitivity)
	get_viewport().set_input_as_handled()


func _current_pinch() -> float:
	if _cam_touches.size() < 2:
		return 0.0
	var pts: Array = _cam_touches.values()
	return (pts[0] as Vector2).distance_to(pts[1])


## 조이스틱 벡터: 화면 위쪽 = 앞(-y). Input.get_vector와 같은 규약 (x 오른쪽, y 아래=뒤)
func _update_joy() -> void:
	var off := (_joy_pos - _joy_center).limit_length(JOY_RADIUS)
	var v := off / JOY_RADIUS
	if v.length() < DEAD_ZONE:
		v = Vector2.ZERO
	if controller:
		controller.external_move = v


# ------------------------------------------------------------------ 그리기

func _draw_controls() -> void:
	var white := Color(1, 1, 1, 0.55)
	var dark := Color(0.15, 0.15, 0.3, 0.35)
	if _joy_index != -1:
		_canvas.draw_circle(_joy_center, JOY_RADIUS, dark)
		_canvas.draw_arc(_joy_center, JOY_RADIUS, 0, TAU, 48, white, 4.0)
		var knob := _joy_center + (_joy_pos - _joy_center).limit_length(JOY_RADIUS)
		_canvas.draw_circle(knob, 48, Color(1, 1, 1, 0.8))
	else:
		var v := _view()
		var hint := Vector2(200, v.y - 190)
		_canvas.draw_arc(hint, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.3), 3.0)
		_canvas.draw_circle(hint, 40, Color(1, 1, 1, 0.3))
	_canvas.draw_circle(_jump_center(), BUTTON_RADIUS, Color(1.0, 0.6, 0.35, 0.85))
	_canvas.draw_string(ThemeDB.fallback_font, _jump_center() + Vector2(-34, 12), "점프", HORIZONTAL_ALIGNMENT_CENTER, -1, 32, Color.WHITE)
	_canvas.draw_circle(_emote_center(), BUTTON_RADIUS * 0.7, Color(0.6, 0.5, 1.0, 0.85))
	_canvas.draw_string(ThemeDB.fallback_font, _emote_center() + Vector2(-16, 12), "♥", HORIZONTAL_ALIGNMENT_CENTER, -1, 36, Color.WHITE)
	if _emote_open:
		var names := ["인사", "춤", "만세", "시무룩"]
		for i in Appearance.EMOTES.size():
			var c := _emote_item_center(i)
			_canvas.draw_circle(c, 45, Color(1, 1, 1, 0.9))
			_canvas.draw_string(ThemeDB.fallback_font, c + Vector2(-30, 8), names[i], HORIZONTAL_ALIGNMENT_CENTER, 60, 22, Color(0.3, 0.25, 0.5))
