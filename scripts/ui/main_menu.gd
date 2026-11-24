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
var _notice: Label


func _ready() -> void:
	add_child(MenuBackdrop.new())

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)

	# 로고: 흰 테두리 + 그림자를 두른 큰 글자
	var title := Label.new()
	title.text = "3D PARTY WORLD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(1.0, 0.45, 0.62))
	title.add_theme_color_override("font_outline_color", Color.WHITE)
	title.add_theme_constant_override("outline_size", 16)
	title.add_theme_color_override("font_shadow_color", Color(0.3, 0.2, 0.55, 0.35))
	title.add_theme_constant_override("shadow_offset_y", 6)
	title.add_theme_constant_override("shadow_offset_x", 0)
	col.add_child(title)
	var sub := Label.new()
	sub.text = "친구들과 함께하는 하늘 위 파티 게임"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 19)
	sub.add_theme_color_override("font_color", Color.WHITE)
	sub.add_theme_color_override("font_outline_color", Color(0.35, 0.3, 0.6, 0.6))
	sub.add_theme_constant_override("outline_size", 6)
	col.add_child(sub)

	var panel := PanelContainer.new()
	col.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(460, 0)
	panel.add_child(box)

	var acc := HBoxContainer.new()
	box.add_child(acc)
	_account_label = Label.new()
	_account_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_account_label.add_theme_font_size_override("font_size", 18)
	_account_label.add_theme_color_override("font_color", UiStyle.INK_SOFT)
	acc.add_child(_account_label)
	_link_btn = _small_button("계정 연결", func() -> void: link_requested.emit())
	_link_btn.theme_type_variation = "AccentButton"
	acc.add_child(_link_btn)
	_logout_btn = _small_button("로그아웃", func() -> void: logout_requested.emit())
	acc.add_child(_logout_btn)
	refresh_account()

	_notice = Label.new()
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.add_theme_font_size_override("font_size", 17)
	_notice.add_theme_color_override("font_color", Color(0.85, 0.3, 0.35))
	_notice.visible = false
	box.add_child(_notice)

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
		_room.custom_minimum_size = Vector2(120, 62)
		_room.add_theme_font_size_override("font_size", 24)
		_room.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_room.text_submitted.connect(func(_t: String) -> void: _join_room(online_url))
		room_row.add_child(_room)
		var enter := _big_button("입장", func() -> void: _join_room(online_url))
		enter.theme_type_variation = "AccentButton"
		enter.custom_minimum_size = Vector2(90, 64)
		room_row.add_child(enter)
		_room_note = Label.new()
		_room_note.text = "방을 만들면 나오는 코드를 친구에게 알려 주세요"
		var invited := OnlineConfig.room_from_page()
		if invited != "":
			_room.text = invited
			_room_note.text = "초대받은 방: %s → \"입장\"을 눌러 주세요" % invited
		_room_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_room_note.add_theme_font_size_override("font_size", 15)
		_room_note.add_theme_color_override("font_color", UiStyle.INK_SOFT)
		box.add_child(_room_note)
		var pub := _big_button("공개 광장 입장 (누구나)", func() -> void: join_requested.emit(_nick.text.strip_edges(), online_url))
		pub.theme_type_variation = "AccentButton"
		box.add_child(pub)
	var practice := HBoxContainer.new()
	practice.add_theme_constant_override("separation", 8)
	box.add_child(practice)
	var p1 := _big_button("혼자 연습", func() -> void: offline_requested.emit(_nick.text.strip_edges()))
	p1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p1.theme_type_variation = "SecondaryButton"
	practice.add_child(p1)
	var p2 := _big_button("레이스 연습", func() -> void: practice_requested.emit(_nick.text.strip_edges(), "obstacle_race"))
	p2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p2.theme_type_variation = "SecondaryButton"
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
	# PC 전용: 내 PC 서버 / 주소로 접속 (한 줄로)
	var pc := HBoxContainer.new()
	pc.add_theme_constant_override("separation", 8)
	box.add_child(pc)
	for spec in [["내 PC로 서버 열기", func() -> void: host_requested.emit(_nick.text.strip_edges())],
			["주소로 접속", func() -> void: join_requested.emit(_nick.text.strip_edges(), _addr.text.strip_edges())]]:
		var b := _big_button(spec[0], spec[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.theme_type_variation = "SecondaryButton"
		b.custom_minimum_size.y = 52
		b.add_theme_font_size_override("font_size", 19)
		pc.add_child(b)


## 메뉴 위쪽에 안내 문구 (게임에서 나왔을 때 이유 등). 빈 문자열이면 숨김
func show_notice(text: String) -> void:
	if _notice:
		_notice.text = text
		_notice.visible = text != ""


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
	_look_label.text = "외형: %s / %s" % [Appearance.COLOR_NAMES[_color], Appearance.HAT_NAMES[_hat]]
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
	b.custom_minimum_size = Vector2(0, 62)
	b.add_theme_font_size_override("font_size", 23)
	b.pressed.connect(cb)
	return b


func _small_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(80, 42)
	b.add_theme_font_size_override("font_size", 17)
	b.theme_type_variation = "SecondaryButton"
	b.pressed.connect(cb)
	return b
