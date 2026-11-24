class_name MenuBackdrop
extends Control
## 메뉴·로그인 배경: 하늘색→분홍 그라디언트 + 천천히 흘러가는 구름과 반짝이 (그리기만, 가벼움)

const TOP := Color(0.45, 0.66, 1.0)
const BOTTOM := Color(1.0, 0.78, 0.88)

var _t := 0.0
var _clouds: Array[Vector3] = []   # x(0~1), y(0~1), 크기
var _sparks: Array[Vector3] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 7:
		_clouds.append(Vector3(rng.randf(), 0.08 + rng.randf() * 0.8, 0.6 + rng.randf() * 0.8))
	for i in 26:
		_sparks.append(Vector3(rng.randf(), rng.randf(), rng.randf() * TAU))


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var s := size
	# 세로 그라디언트 (띠 24개)
	var bands := 24
	for i in bands:
		var c := TOP.lerp(BOTTOM, float(i) / (bands - 1))
		draw_rect(Rect2(0, s.y * i / bands, s.x, s.y / bands + 1.0), c)
	# 구름
	for c in _clouds:
		var x := fposmod(c.x + _t * 0.008 * c.z, 1.3) - 0.15
		var p := Vector2(x * s.x, c.y * s.y)
		var r := 46.0 * c.z
		var col := Color(1, 1, 1, 0.55)
		draw_circle(p, r, col)
		draw_circle(p + Vector2(r * 0.9, r * 0.2), r * 0.75, col)
		draw_circle(p + Vector2(-r * 0.9, r * 0.25), r * 0.7, col)
		draw_circle(p + Vector2(r * 0.2, -r * 0.45), r * 0.7, col)
	# 반짝이
	for sp in _sparks:
		var a := 0.25 + 0.35 * (0.5 + 0.5 * sin(_t * 1.6 + sp.z))
		draw_circle(Vector2(sp.x * s.x, fposmod(sp.y - _t * 0.01, 1.0) * s.y), 2.5, Color(1, 1, 1, a))
