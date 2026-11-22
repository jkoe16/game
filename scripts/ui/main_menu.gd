class_name MainMenu
extends CanvasLayer
## 임시 시작 메뉴 (Phase 12에서 3D 카툰 UI로 교체 예정). 큰 버튼 위주로 모바일에서도 누르기 쉽게 구성.

signal offline_requested(nickname: String)
signal host_requested(nickname: String)
signal join_requested(nickname: String, address: String)
signal logout_requested
signal link_requested

var _nick: LineEdit
var _addr: LineEdit
var _color := 0
var _hat := 0
var _look_label: Label
var _account_label: Label
var _logout_btn: Button
var _link_btn: Button


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.35, 0.6, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.92)
	sb.set_corner_radius_all(28)
	sb.set_content_margin_all(32)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(440, 0)
	panel.add_child(box)

	var title := Label.new()
	title.text = "3D PARTY WORLD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.95, 0.4, 0.55))
	box.add_child(title)

	var acc := HBoxContainer.new()
	box.add_child(acc)
	_account_label = Label.new()
	_account_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_account_label.add_theme_font_size_override("font_size", 18)
	_account_label.add_theme_color_override("font_color", Color(0.3, 0.35, 0.5))
	acc.add_child(_account_label)
	_link_btn = _small_button("계정 연결", func() -> void: link_requested.emit())
	acc.add_child(_link_btn)
	_logout_btn = _small_button("로그아웃", func() -> void: logout_requested.emit())
	acc.add_child(_logout_btn)
	refresh_account()

	_nick = _field(box, "닉네임 (2~16자, 한글/영문/숫자/_)", "Player%d" % (randi() % 1000))
	_addr = _field(box, "서버 주소", "127.0.0.1:%d" % NetConfig.DEFAULT_PORT)

	var look := HBoxContainer.new()
	box.add_child(look)
	_look_label = Label.new()
	_look_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_look_label.add_theme_font_size_override("font_size", 20)
	look.add_child(_look_label)
	look.add_child(_small_button("색상", func() -> void: _color = (_color + 1) % Appearance.BODY_COLORS.size(); _refresh_look()))
	look.add_child(_small_button("모자", func() -> void: _hat = (_hat + 1) % Appearance.HATS.size(); _refresh_look()))
	_refresh_look()

	box.add_child(_big_button("연습 모드 (오프라인)", func() -> void: offline_requested.emit(_nick.text.strip_edges())))
	box.add_child(_big_button("로컬 서버 열고 접속", func() -> void: host_requested.emit(_nick.text.strip_edges())))
	box.add_child(_big_button("서버 접속", func() -> void: join_requested.emit(_nick.text.strip_edges(), _addr.text.strip_edges())))


func refresh_account() -> void:
	if _account_label == null:
		return
	if not Auth.is_configured():
		_account_label.text = "개발 모드 (Firebase 미설정)"
	else:
		_account_label.text = "계정: " + Auth.display_account()
		if not PlayerData.stats.is_empty():
			var xp := int(PlayerData.stats.get("xp", 0))
			_account_label.text += "\nLv.%d  (XP %d · %d판 · %d승)" % [Progression.level_for_xp(xp), xp, int(PlayerData.stats.get("matches", 0)), int(PlayerData.stats.get("wins", 0))]
	_logout_btn.visible = Auth.is_signed_in()
	_link_btn.visible = Auth.is_signed_in() and Auth.is_anonymous()


## Firestore 프로필을 메뉴에 반영
func apply_profile(p: Dictionary) -> void:
	var a := Appearance.sanitize(p.get("appearance"))
	_color = a["color"]
	_hat = a["hat"]
	if typeof(p.get("nickname")) == TYPE_STRING and _nick:
		_nick.text = p["nickname"]
	_refresh_look()


func get_nickname() -> String:
	return _nick.text.strip_edges()


func get_appearance() -> Dictionary:
	return {"color": _color, "hat": _hat}


func _refresh_look() -> void:
	_look_label.text = "외형: 색상 %d / 모자 %s" % [_color + 1, Appearance.HATS[_hat]]
	_look_label.add_theme_color_override("font_color", Appearance.BODY_COLORS[_color].darkened(0.3))


func _field(parent: Control, placeholder: String, value: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = value
	e.custom_minimum_size = Vector2(0, 52)
	e.add_theme_font_size_override("font_size", 22)
	parent.add_child(e)
	return e


func _big_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 64)
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(cb)
	return b


func _small_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(80, 44)
	b.pressed.connect(cb)
	return b
