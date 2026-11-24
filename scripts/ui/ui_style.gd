class_name UiStyle
extends RefCounted
## 게임 전체 UI 스타일 (파스텔 카툰). 시작할 때 한 번 apply()로 기본 테마를 바꾸면
## 메뉴·로그인·HUD의 모든 버튼/입력칸/패널이 같은 모양이 된다.
## 버튼 종류는 theme_type_variation 으로 고른다: "" (기본 분홍), "AccentButton"(하늘), "SecondaryButton"(흰색)

const INK := Color(0.32, 0.27, 0.48)        # 진한 글자색 (보라빛 남색)
const INK_SOFT := Color(0.52, 0.48, 0.66)
const PINK := Color(1.0, 0.52, 0.66)
const SKY := Color(0.42, 0.68, 1.0)
const MINT := Color(0.36, 0.82, 0.7)
const GOLD := Color(1.0, 0.8, 0.3)
const CARD := Color(1, 1, 1, 0.96)

static var _applied := false


static func apply() -> void:
	if _applied:
		return
	_applied = true
	var t := ThemeDB.get_default_theme()
	_button(t, "Button", PINK, Color.WHITE)
	_button(t, "AccentButton", SKY, Color.WHITE)
	_button(t, "SecondaryButton", Color(1, 1, 1), INK)
	t.set_type_variation("AccentButton", "Button")
	t.set_type_variation("SecondaryButton", "Button")

	var le := _box(Color(0.97, 0.96, 1.0), 14, Color(0.82, 0.78, 0.95), 2)
	le.set_content_margin_all(12)
	var le_focus := le.duplicate() as StyleBoxFlat
	le_focus.border_color = PINK
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le_focus)
	t.set_stylebox("read_only", "LineEdit", le)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(0.62, 0.6, 0.72))
	t.set_color("caret_color", "LineEdit", PINK)
	t.set_color("selection_color", "LineEdit", Color(1.0, 0.75, 0.85, 0.6))

	var panel := card_box()
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)


## 흰 카드 (둥근 모서리 + 부드러운 그림자)
static func card_box(alpha := 0.96, radius := 28) -> StyleBoxFlat:
	var b := _box(Color(1, 1, 1, alpha), radius)
	b.shadow_color = Color(0.25, 0.18, 0.45, 0.22)
	b.shadow_size = 16
	b.shadow_offset = Vector2(0, 6)
	b.set_content_margin_all(28)
	return b


## 게임 화면 위에 올리는 반투명 남색 카드 (흰 글자용)
static func hud_box(alpha := 0.42) -> StyleBoxFlat:
	var b := _box(Color(0.16, 0.12, 0.32, alpha), 16)
	b.content_margin_left = 14
	b.content_margin_right = 14
	b.content_margin_top = 8
	b.content_margin_bottom = 10
	return b


static func _box(bg: Color, radius: int, border := Color.TRANSPARENT, border_w := 0) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.set_corner_radius_all(radius)
	b.corner_detail = 8
	b.anti_aliasing = true
	if border_w > 0:
		b.border_color = border
		b.set_border_width_all(border_w)
	return b


## 통통한 버튼: 아래쪽 두꺼운 테두리로 입체감, 누르면 꺼지는 느낌
static func _button(t: Theme, type: String, bg: Color, fg: Color) -> void:
	var edge := bg.darkened(0.22) if bg != Color(1, 1, 1) else Color(0.84, 0.8, 0.95)
	var normal := _box(bg, 18, edge, 0)
	normal.border_width_bottom = 5
	normal.border_color = edge
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 8
	normal.content_margin_bottom = 10
	normal.shadow_color = Color(0.25, 0.18, 0.45, 0.16)
	normal.shadow_size = 6
	normal.shadow_offset = Vector2(0, 3)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = bg.lightened(0.12)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = bg.darkened(0.06)
	pressed.border_width_bottom = 1
	pressed.content_margin_top = 12
	pressed.content_margin_bottom = 6
	pressed.shadow_size = 2
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.85, 0.84, 0.9)
	disabled.border_color = Color(0.75, 0.74, 0.82)
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, pressed)
	t.set_stylebox("disabled", type, disabled)
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, type, fg)
	t.set_color("font_disabled_color", type, Color(0.6, 0.58, 0.7))
	t.set_constant("outline_size", type, 0)
