class_name Hud
extends CanvasLayer
## 인게임 HUD: 개발 정보 + 조작 안내 + 게임 모드(제목·규칙·카운트다운·남은 시간·점수판·결과).

var client: GameClient
var _status: Label
var _info: Label
var _mode_title: Label
var _mode_phase: Label
var _board: Label
var _big: Label
var _results: PanelContainer
var _results_label: Label


func _ready() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(16, 12)
	add_child(box)
	_status = _label(box, 22)
	_info = _label(box, 16)
	var help := _label(box, 16)
	help.text = "WASD 이동 · Shift 걷기 · Space 점프 · 클릭 후 마우스 카메라 · 휠 줌 · 1~4 감정표현 · Esc 마우스 해제"
	if DisplayServer.is_touchscreen_available():
		help.text = "왼쪽 조이스틱 이동 · 오른쪽 드래그 카메라 · 버튼으로 점프/감정표현"

	var right := VBoxContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -380
	right.offset_top = 12
	right.offset_right = -16
	add_child(right)
	_mode_title = _label(right, 26)
	_mode_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_phase = _label(right, 20)
	_mode_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_phase.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_board = _label(right, 18)
	_board.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_big = Label.new()
	_big.set_anchors_preset(Control.PRESET_CENTER)
	_big.offset_left = -300
	_big.offset_right = 300
	_big.offset_top = -160
	_big.offset_bottom = -40
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.add_theme_font_size_override("font_size", 96)
	_big.add_theme_color_override("font_outline_color", Color(0.25, 0.15, 0.35))
	_big.add_theme_constant_override("outline_size", 18)
	add_child(_big)

	_results = PanelContainer.new()
	_results.set_anchors_preset(Control.PRESET_CENTER)
	_results.offset_left = -260
	_results.offset_right = 260
	_results.offset_top = -40
	_results.offset_bottom = 220
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.9)
	sb.set_corner_radius_all(24)
	sb.set_content_margin_all(20)
	_results.add_theme_stylebox_override("panel", sb)
	_results_label = Label.new()
	_results_label.add_theme_font_size_override("font_size", 22)
	_results_label.add_theme_color_override("font_color", Color(0.25, 0.2, 0.35))
	_results.add_child(_results_label)
	_results.visible = false
	add_child(_results)


func set_status(text: String) -> void:
	if _status:
		_status.text = text


func _process(_delta: float) -> void:
	if client == null or _info == null:
		return
	if client.offline:
		_info.text = "FPS %d" % Engine.get_frames_per_second()
	else:
		var count := client.remotes.size() + (1 if client.local_player else 0)
		var corr := client.controller.corrections if client.controller else 0
		_info.text = "플레이어 %d명 · 핑 %d ms · 서버 보정 %d회 · FPS %d" % [count, Net.get_rtt_ms(), corr, Engine.get_frames_per_second()]
	_update_mode()


func _update_mode() -> void:
	var s: Dictionary = client.mode_state
	var phase := str(s.get("phase", ""))
	_mode_title.text = str(s.get("title", ""))
	var secs := maxf(0.0, (float(s.get("phase_end_tick", 0)) - client.server_tick_est) / 60.0)
	_big.text = ""
	match phase:
		"lobby", "":
			_mode_phase.text = str(s.get("rules", ""))
		"waiting":
			var n: int = s.get("players", {}).size()
			var need := int(s.get("min_players", 1))
			_mode_phase.text = ("%d초 후 시작 (%d명)" % [ceili(secs), n]) if int(s.get("phase_end_tick", 0)) > 0 else ("참가자를 기다리는 중 %d/%d" % [n, need])
		"countdown":
			_mode_phase.text = str(s.get("rules", ""))
			_big.text = str(ceili(secs)) if secs > 0.05 else "출발!"
		"playing":
			_mode_phase.text = "남은 시간 %d:%02d" % [int(secs) / 60, int(secs) % 60]
			var me: Dictionary = s.get("players", {}).get(str(client.my_id), {})
			if me.get("status") == "out":
				_big.text = "탈락! 관전 중"
			elif me.get("status") == "finished":
				_big.text = "완주!"
			elif me.get("status") == "late":
				_big.text = "다음 판을 기다려요"
		"results":
			_mode_phase.text = "결과 발표"
	var lines: Array = s.get("board", [])
	_board.text = "\n".join(PackedStringArray(lines.slice(0, 8)))
	var results: Array = s.get("results", [])
	_results.visible = phase == "results" and not results.is_empty()
	if _results.visible:
		var txt := "결과\n"
		for r in results:
			var mark := " ★" if r.get("win") else ""
			var me := " ← 나" if int(r.get("peer_id", 0)) == client.my_id else ""
			txt += "%d위  %s  %s  +%dXP%s%s\n" % [r["rank"], r["nickname"], r["score"], r["xp"], mark, me]
		_results_label.text = txt


func _label(parent: Control, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.2))
	l.add_theme_constant_override("outline_size", 6)
	parent.add_child(l)
	return l
