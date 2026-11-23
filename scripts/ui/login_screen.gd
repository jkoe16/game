class_name LoginScreen
extends CanvasLayer
## 로그인 화면. mode "login": 게스트/이메일/Google 로그인, mode "link": 게스트 계정에 이메일·Google 연결.

signal finished(success: bool)

var mode := "login"
var _email: LineEdit
var _password: LineEdit
var _status: Label
var _buttons: Array[Button] = []


func _ready() -> void:
	layer = 10
	var bg := ColorRect.new()
	bg.color = Color(0.35, 0.6, 0.95) if mode == "login" else Color(0, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.95)
	sb.set_corner_radius_all(28)
	sb.set_content_margin_all(32)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(460, 0)
	panel.add_child(box)

	var title := Label.new()
	title.text = "3D PARTY WORLD" if mode == "login" else "게스트 계정 연결"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40 if mode == "login" else 30)
	title.add_theme_color_override("font_color", Color(0.95, 0.4, 0.55))
	box.add_child(title)
	if mode == "link":
		box.add_child(_note("연결하면 지금까지의 진행도를 다른 기기에서도 이어서 할 수 있어요."))

	if mode == "login":
		box.add_child(_button("게스트로 바로 시작", _on_guest, Color(1.0, 0.62, 0.4)))
	box.add_child(_button("Google로 " + ("로그인" if mode == "login" else "연결"), _on_google, Color(0.3, 0.55, 0.95)))
	box.add_child(_note("또는 이메일"))
	_email = _field("이메일", false)
	box.add_child(_email)
	_password = _field("비밀번호 (6자 이상)", true)
	box.add_child(_password)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	if mode == "login":
		row.add_child(_button("로그인", _on_email_login, Color(0.45, 0.75, 0.45), true))
		row.add_child(_button("회원가입", _on_sign_up, Color(0.6, 0.5, 0.9), true))
		box.add_child(_button("비밀번호를 잊었어요", _on_reset, Color(0.6, 0.6, 0.65), false, 44))
	else:
		row.add_child(_button("이메일로 연결", _on_link_email, Color(0.45, 0.75, 0.45), true))
		row.add_child(_button("취소", func() -> void: _close(false), Color(0.6, 0.6, 0.65), true))

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", Color(0.75, 0.25, 0.3))
	box.add_child(_status)
	if not Auth.is_configured():
		_set_status("Firebase 설정 파일(config/firebase.cfg)이 없습니다.")


func _on_guest() -> void:
	await _run(Auth.sign_in_anonymous)


func _on_google() -> void:
	_set_status("Google 로그인 창에서 계정을 선택해 주세요..." if OS.has_feature("web") else "브라우저에서 Google 로그인을 완료해 주세요...", false)
	await _run(Auth.sign_in_google)


func _on_email_login() -> void:
	await _run(Auth.sign_in_email.bind(_email.text, _password.text))


func _on_sign_up() -> void:
	await _run(Auth.sign_up_email.bind(_email.text, _password.text))


func _on_link_email() -> void:
	await _run(Auth.link_email.bind(_email.text, _password.text))


func _on_reset() -> void:
	_set_busy(true)
	var r: Dictionary = await Auth.send_password_reset(_email.text)
	_set_busy(false)
	_set_status("비밀번호 재설정 메일을 보냈습니다. 메일함을 확인해 주세요." if r["ok"] else r["error"], not r["ok"])


## action: Auth 로그인 메서드(Callable). 코루틴 결과를 받기 위해 여기서 호출+await 한다.
func _run(action: Callable) -> void:
	_set_busy(true)
	var r: Dictionary = await action.call()
	_set_busy(false)
	if r["ok"]:
		_close(true)
	else:
		_set_status(r["error"])


func _close(success: bool) -> void:
	finished.emit(success)
	queue_free()


func _set_busy(busy: bool) -> void:
	for b in _buttons:
		b.disabled = busy
	if busy:
		_set_status("처리 중...", false)


func _set_status(text: String, is_error := true) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", Color(0.75, 0.25, 0.3) if is_error else Color(0.3, 0.4, 0.6))


func _field(placeholder: String, secret: bool) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.secret = secret
	e.custom_minimum_size = Vector2(0, 52)
	e.add_theme_font_size_override("font_size", 22)
	return e


func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
	return l


func _button(text: String, cb: Callable, color: Color, expand := false, height := 60) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_size_override("font_size", 22)
	if expand:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for state in ["normal", "hover", "pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		s.bg_color = color.lightened(0.1) if state == "hover" else (color.darkened(0.15) if state == "pressed" else (color.darkened(0.3) if state == "disabled" else color))
		s.set_corner_radius_all(16)
		b.add_theme_stylebox_override(state, s)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.pressed.connect(cb)
	_buttons.append(b)
	return b
