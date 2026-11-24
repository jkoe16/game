class_name Hud
extends CanvasLayer
## 인게임 HUD: 방·접속 정보 + 조작 안내 + 게임 모드(제목·규칙·카운트다운·남은 시간·점수판·결과) + 화면 전환 연출.

signal leave_requested

const BIG_COLORS := {"3": Color(1.0, 0.5, 0.55), "2": Color(1.0, 0.8, 0.35), "1": Color(0.45, 0.85, 0.6), "출발!": Color(1.0, 0.55, 0.8)}
const MEDALS := [Color(1.0, 0.78, 0.25), Color(0.78, 0.8, 0.9), Color(0.92, 0.62, 0.42)]

var client: GameClient
var _people: Label
var _invite_btn: Button
var _toast: Label
var _toast_card: PanelContainer
var _toast_left := 0.0
var _status: Label
var _info: Label
var _mode_card: PanelContainer
var _mode_title: Label
var _mode_phase: Label
var _board: Label
var _big: Label
var _last_big := ""
var _banner: Label
var _last_phase := ""
var _confetti: CPUParticles2D
var _results: PanelContainer
var _results_label: RichTextLabel
var _room: Label
var _fade: ColorRect
var _fade_a := 1.0


func _ready() -> void:
	# 화면 전환용 덮개 (맨 아래에 두어 접속 상태 글자는 위에 보이게)
	_fade = ColorRect.new()
	_fade.color = Color(0.78, 0.84, 1.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

	# ---- 왼쪽 위: 정보 카드
	var info_card := PanelContainer.new()
	info_card.add_theme_stylebox_override("panel", UiStyle.hud_box())
	info_card.position = Vector2(14, 12)
	info_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(info_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.custom_minimum_size = Vector2(400, 0)
	info_card.add_child(box)
	_room = _label(box, 24)
	_room.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	_room.visible = false
	_status = _label(box, 20)
	_people = _label(box, 17)
	_people.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	_info = _label(box, 13)
	_info.modulate = Color(1, 1, 1, 0.6)
	var help := _label(box, 14)
	help.modulate = Color(1, 1, 1, 0.75)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_people.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = "WASD 이동 · Shift 걷기 · Space 점프 · 클릭 후 마우스 카메라 · 휠 줌 · 1~4 감정표현 · Esc 마우스 해제"
	if DisplayServer.is_touchscreen_available():
		help.text = "왼쪽 조이스틱 이동 · 오른쪽 드래그 카메라 · 버튼으로 점프/감정표현"

	# ---- 위쪽 가운데: 초대 링크 복사 / 나가기
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.offset_left = -170
	top.offset_right = 170
	top.offset_top = 12
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 10)
	add_child(top)
	_invite_btn = _hud_button("초대 링크 복사", _copy_invite)
	_invite_btn.theme_type_variation = "AccentButton"
	top.add_child(_invite_btn)
	top.add_child(_hud_button("나가기", func() -> void: leave_requested.emit()))

	_toast_card = PanelContainer.new()
	_toast_card.add_theme_stylebox_override("panel", UiStyle.hud_box(0.7))
	_toast_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_card.offset_left = -300
	_toast_card.offset_right = 300
	_toast_card.offset_top = 74
	_toast_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_card.visible = false
	add_child(_toast_card)
	_toast = _label(_toast_card, 23)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# ---- 오른쪽 위: 모드 카드
	_mode_card = PanelContainer.new()
	_mode_card.add_theme_stylebox_override("panel", UiStyle.hud_box())
	_mode_card.anchor_left = 1.0
	_mode_card.anchor_right = 1.0
	_mode_card.offset_left = -380
	_mode_card.offset_top = 12
	_mode_card.offset_right = -14
	_mode_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mode_card)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	_mode_card.add_child(right)
	_mode_title = _label(right, 26)
	_mode_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.6))
	_mode_phase = _label(right, 18)
	_mode_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_phase.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_board = _label(right, 18)
	_board.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# ---- 가운데: 카운트다운 / 상태 큰 글자
	_big = Label.new()
	_big.set_anchors_preset(Control.PRESET_CENTER)
	_big.offset_left = -360
	_big.offset_right = 360
	_big.offset_top = -190
	_big.offset_bottom = -40
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_big.add_theme_font_size_override("font_size", 110)
	_big.add_theme_color_override("font_outline_color", Color.WHITE)
	_big.add_theme_constant_override("outline_size", 26)
	_big.add_theme_color_override("font_shadow_color", Color(0.25, 0.15, 0.45, 0.4))
	_big.add_theme_constant_override("shadow_offset_y", 8)
	_big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_big)

	# ---- 결과: 배너 + 순위 카드 + 색종이
	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.offset_left = -360
	_banner.offset_right = 360
	_banner.offset_top = -250
	_banner.offset_bottom = -150
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 76)
	_banner.add_theme_color_override("font_outline_color", Color.WHITE)
	_banner.add_theme_constant_override("outline_size", 20)
	_banner.add_theme_color_override("font_shadow_color", Color(0.25, 0.15, 0.45, 0.4))
	_banner.add_theme_constant_override("shadow_offset_y", 6)
	_banner.visible = false
	add_child(_banner)

	_results = PanelContainer.new()
	var rb := UiStyle.card_box(0.95, 26)
	rb.set_content_margin_all(22)
	_results.add_theme_stylebox_override("panel", rb)
	_results.set_anchors_preset(Control.PRESET_CENTER)
	_results.offset_left = -270
	_results.offset_right = 270
	_results.offset_top = -140
	_results.offset_bottom = -100
	_results.grow_vertical = Control.GROW_DIRECTION_END  # 내용 높이만큼 아래로
	_results_label = RichTextLabel.new()
	_results_label.bbcode_enabled = true
	_results_label.fit_content = true
	_results_label.scroll_active = false
	_results_label.add_theme_font_size_override("normal_font_size", 22)
	_results_label.add_theme_color_override("default_color", UiStyle.INK)
	_results.add_child(_results_label)
	_results.visible = false
	add_child(_results)

	_confetti = CPUParticles2D.new()
	_confetti.emitting = false
	_confetti.one_shot = true
	_confetti.amount = 90
	_confetti.lifetime = 2.6
	_confetti.explosiveness = 0.85
	_confetti.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_confetti.emission_rect_extents = Vector2(420, 10)
	_confetti.direction = Vector2(0, 1)
	_confetti.spread = 40.0
	_confetti.gravity = Vector2(0, 380)
	_confetti.initial_velocity_min = 80.0
	_confetti.initial_velocity_max = 260.0
	_confetti.angular_velocity_min = -360.0
	_confetti.angular_velocity_max = 360.0
	_confetti.scale_amount_min = 5.0
	_confetti.scale_amount_max = 9.0
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1.0, 0.55, 0.7), Color(1.0, 0.85, 0.35), Color(0.5, 0.8, 1.0), Color(0.6, 0.9, 0.6)])
	g.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	_confetti.color_initial_ramp = g
	add_child(_confetti)


func _hud_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 18)
	b.theme_type_variation = "SecondaryButton"
	b.focus_mode = Control.FOCUS_NONE  # 스페이스(점프)로 버튼이 눌리지 않게
	b.pressed.connect(cb)
	b.add_to_group("touch_ui")
	return b


func _copy_invite() -> void:
	var code := OnlineConfig.room_from_url(client.address) if client else ""
	if code == "":
		return
	var link := OnlineConfig.invite_link(code)
	DisplayServer.clipboard_set(link)
	show_toast("복사했어요! 친구에게 보내 주세요\n%s" % link)


func show_toast(text: String, secs := 4.0) -> void:
	_toast.text = text
	_toast_left = secs
	_toast_card.visible = true
	_toast_card.modulate.a = 1.0


func set_status(text: String) -> void:
	# 모드 알림("!"로 시작)은 위쪽에 크게 잠깐 띄운다
	if text.begins_with("!"):
		show_toast(text.substr(1), 3.5)
		return
	if _status:
		_status.text = text


func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast_card.modulate.a = clampf(_toast_left / 0.4, 0.0, 1.0)
		if _toast_left <= 0.0:
			_toast_card.visible = false
	if client == null or _info == null:
		return
	# 화면 전환: 월드가 없으면(접속·이동 중) 덮개를 덮고, 생기면 부드럽게 걷어 낸다
	var target := 0.0 if client.local_player != null else 1.0
	_fade_a = move_toward(_fade_a, target, delta * (4.0 if target > _fade_a else 1.8))
	_fade.color.a = _fade_a
	_fade.visible = _fade_a > 0.01

	var code := OnlineConfig.room_from_url(client.address) if not client.offline else ""
	_room.visible = code != ""
	_invite_btn.visible = code != ""
	if code != "":
		_room.text = "방 코드  %s" % code
	_people.visible = not client.offline and client.local_player != null
	if _people.visible:
		var names: Array[String] = ["나(%s)" % client.nickname]
		for id in client.remote_names:
			names.append(str(client.remote_names[id]))
		var shown := names.slice(0, 8)
		_people.text = "함께 있는 사람 %d명: %s%s" % [names.size(), ", ".join(shown), " 외 %d명" % (names.size() - 8) if names.size() > 8 else ""]
	if client.offline:
		_info.text = "FPS %d" % Engine.get_frames_per_second()
	else:
		var corr := client.controller.corrections if client.controller else 0
		var rtt := Net.get_rtt_ms()
		var ping := "%d ms" % rtt if rtt >= 0 else "-"
		_info.text = "핑 %s · 서버 보정 %d회 · FPS %d" % [ping, corr, Engine.get_frames_per_second()]
	_update_mode()


func _update_mode() -> void:
	var s: Dictionary = client.mode_state
	var phase := str(s.get("phase", ""))
	_mode_title.text = str(s.get("title", ""))
	_mode_card.visible = _mode_title.text != "" or phase != ""
	var secs := maxf(0.0, (float(s.get("phase_end_tick", 0)) - client.server_tick_est) / 60.0)
	var big := ""
	match phase:
		"lobby", "":
			_mode_phase.text = str(s.get("rules", ""))
		"waiting":
			var n: int = s.get("players", {}).size()
			var need := int(s.get("min_players", 1))
			_mode_phase.text = ("%d초 후 시작 (%d명)" % [ceili(secs), n]) if int(s.get("phase_end_tick", 0)) > 0 else ("참가자를 기다리는 중 %d/%d" % [n, need])
		"countdown":
			_mode_phase.text = str(s.get("rules", ""))
			big = str(ceili(secs)) if secs > 0.05 else "출발!"
		"playing":
			_mode_phase.text = "남은 시간 %d:%02d" % [int(secs) / 60, int(secs) % 60]
			var me: Dictionary = s.get("players", {}).get(str(client.my_id), {})
			if me.get("status") == "out":
				big = "탈락! 관전 중"
			elif me.get("status") == "finished":
				big = "완주!"
			elif me.get("status") == "late":
				big = "다음 판을 기다려요"
			elif secs > 0.0 and secs <= 5.0:
				big = str(ceili(secs))  # 마지막 5초 카운트
		"results":
			_mode_phase.text = "결과 발표"
	_set_big(big)
	var lines: Array = s.get("board", [])
	_board.text = "\n".join(PackedStringArray(lines.slice(0, 8)))
	_board.visible = _board.text != ""

	var results: Array = s.get("results", [])
	var show_results := phase == "results" and not results.is_empty()
	if show_results and _last_phase != "results":
		_on_results(results)
	_results.visible = show_results
	_banner.visible = show_results
	if show_results:
		_fill_results(results)
	_last_phase = phase


## 큰 글자가 바뀔 때마다 톡 튀어나오는 연출
func _set_big(text: String) -> void:
	if text == _last_big:
		return
	_last_big = text
	_big.text = text
	if text == "":
		return
	var col: Color = BIG_COLORS.get(text, Color(1.0, 0.6, 0.75))
	_big.add_theme_color_override("font_color", col)
	_big.pivot_offset = _big.size * 0.5
	_big.scale = Vector2(1.7, 1.7)
	_big.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_big, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_big, "modulate:a", 1.0, 0.15)


func _on_results(results: Array) -> void:
	var mine: Dictionary = {}
	for r in results:
		if int(r.get("peer_id", 0)) == client.my_id:
			mine = r
	var rank := int(mine.get("rank", 0))
	if str(client.mode_state.get("mode", "")) == "coop":
		_banner.text = "미션 성공!" if mine.get("win") else "아쉬워요! 다음엔 꼭"
		_banner.add_theme_color_override("font_color", Color(0.4, 0.85, 0.6) if mine.get("win") else Color(0.55, 0.65, 1.0))
		rank = 1 if mine.get("win") else 99  # 성공하면 색종이
	elif rank == 1 and mine.get("win"):
		_banner.text = "우승!"
		_banner.add_theme_color_override("font_color", Color(1.0, 0.72, 0.2))
	elif rank > 0 and (rank <= 3 or mine.get("win")):
		_banner.text = "%d위! 잘했어요" % rank
		_banner.add_theme_color_override("font_color", Color(1.0, 0.55, 0.7))
	elif rank > 0:
		_banner.text = "아쉬워요! %d위" % rank
		_banner.add_theme_color_override("font_color", Color(0.55, 0.65, 1.0))
	else:
		_banner.text = "결과 발표"
		_banner.add_theme_color_override("font_color", Color(1.0, 0.6, 0.75))
	_banner.pivot_offset = _banner.size * 0.5
	_banner.scale = Vector2(0.3, 0.3)
	_results.pivot_offset = _results.size * 0.5
	_results.scale = Vector2(0.85, 0.85)
	_results.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_results, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.15)
	tw.tween_property(_results, "modulate:a", 1.0, 0.25).set_delay(0.15)
	if rank > 0 and rank <= 3:
		var vp := get_viewport().get_visible_rect().size
		_confetti.position = Vector2(vp.x * 0.5, -10)
		_confetti.emission_rect_extents = Vector2(vp.x * 0.5, 10)
		_confetti.restart()
		_confetti.emitting = true


func _fill_results(results: Array) -> void:
	var t := "[center][font_size=30][color=#%s]순위[/color][/font_size][/center]\n" % UiStyle.PINK.to_html(false)
	for r in results:
		var rank := int(r["rank"])
		var medal: Color = MEDALS[rank - 1] if rank >= 1 and rank <= 3 else UiStyle.INK_SOFT
		var me := int(r.get("peer_id", 0)) == client.my_id
		var name_col := UiStyle.PINK if me else UiStyle.INK
		t += "[color=#%s][font_size=28]%d위[/font_size][/color]   [color=#%s]%s%s[/color]   [color=#%s]%s · +%dXP%s[/color]\n" % [
			medal.darkened(0.1).to_html(false), rank, name_col.to_html(false), r["nickname"], " (나)" if me else "",
			UiStyle.INK_SOFT.to_html(false), r["score"], r["xp"], "  ★" if r.get("win") else ""]
	_results_label.text = t


func _label(parent: Control, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.25, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
