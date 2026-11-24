class_name MainMenu
extends CanvasLayer
## 임시 시작 메뉴 (Phase 12에서 3D 카툰 UI로 교체 예정). 큰 버튼 위주로 모바일에서도 누르기 쉽게 구성.

signal offline_requested(nickname: String)
## 오프라인으로 특정 미니게임 바로 연습 (mode_id)
signal practice_requested(nickname: String, mode_id: String)
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
var _room: LineEdit
var _room_note: Label


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
	var online_url := OnlineConfig.server_url()
	_addr = _field(box, "서버 주소 (예: 192.168.0.5:7777 또는 wss://주소)", online_url if online_url != "" else "127.0.0.1:%d" % NetConfig.DEFAULT_PORT)

	var look := HBoxContainer.new()
	box.add_child(look)
	_look_label = Label.new()
	_look_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_look_label.add_theme_font_size_override("font_size", 20)
	look.add_child(_look_label)
	look.add_child(_small_button("색상", func() -> void: _color = (_color + 1) % Appearance.BODY_COLORS.size(); _refresh_look()))
	look.add_child(_small_button("모자", func() -> void: _hat = (_hat + 1) % Appearance.HATS.size(); _refresh_look()))
	_refresh_look()

	# 온라인 서버(config/online.cfg)가 있으면: 방 만들기 / 코드로 입장 / 공개 광장
	if online_url != "":
		var room_row := HBoxContainer.new()
		room_row.add_theme_constant_override("separation", 8)
		box.add_child(room_row)
		var make := _big_button("방 만들기", func() -> void:
			join_requested.emit(_nick.text.strip_edges(), OnlineConfig.room_url(online_url, OnlineConfig.new_room_code())))
		make.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		room_row.add_child(make)
		_room = LineEdit.new()
		_room.placeholder_text = "방 코드"
		_room.max_length = 8
		_room.custom_minimum_size = Vector2(120, 64)
		_room.add_theme_font_size_override("font_size", 24)
		_room.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_room.text_submitted.connect(func(_t: String) -> void: _join_room(online_url))
		room_row.add_child(_room)
		var enter := _big_button("입장", func() -> void: _join_room(online_url))
		enter.custom_minimum_size = Vector2(90, 64)
		room_row.add_child(enter)
		_room_note = Label.new()
		_room_note.text = "방을 만들면 나오는 코드를 친구에게 알려 주세요"
		_room_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_room_note.add_theme_font_size_override("font_size", 15)
		_room_note.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
		box.add_child(_room_note)
		box.add_child(_big_button("공개 광장 입장 (누구나)", func() -> void: join_requested.emit(_nick.text.strip_edges(), online_url)))
	var practice := HBoxContainer.new()
	practice.add_theme_constant_override("separation", 8)
	box.add_child(practice)
	var p1 := _big_button("혼자 연습", func() -> void: offline_requested.emit(_nick.text.strip_edges()))
	p1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	practice.add_child(p1)
	var p2 := _big_button("레이스 연습", func() -> void: practice_requested.emit(_nick.text.strip_edges(), "obstacle_race"))
	p2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	practice.add_child(p2)
	# 웹 브라우저는 ENet(UDP) 불가 → WebSocket(wss://) 주소로만 접속
	if OS.has_feature("web"):
		_addr.visible = false
		if online_url == "":
			var note := Label.new()
			note.text = "온라인 서버가 아직 설정되지 않았어요 (혼자 연습만 가능)"
			note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			note.add_theme_font_size_override("font_size", 16)
			note.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
			box.add_child(note)
		return
	box.add_child(_big_button("로컬 서버 열고 접속", func() -> void: host_requested.emit(_nick.text.strip_edges())))
	box.add_child(_big_button("서버 접속", func() -> void: join_requested.emit(_nick.text.strip_edges(), _addr.text.strip_edges())))


func _join_room(online_url: String) -> void:
	var code := OnlineConfig.normalize_room_code(_room.text)
	if code == "":
		_room_note.text = "방 코드는 영문/숫자 4~8자예요"
		_room_note.add_theme_color_override("font_color", Color(0.85, 0.3, 0.35))
		return
	join_requested.emit(_nick.text.strip_edges(), OnlineConfig.room_url(online_url, code))


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
