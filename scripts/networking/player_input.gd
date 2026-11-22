class_name PlayerInput
extends RefCounted
## 한 물리 틱 동안의 플레이어 입력.
## 클라이언트가 서버에 보내는 게임플레이 데이터는 이것뿐이다 (위치/점수는 절대 보내지 않음).
## 이동값은 -127..127 정수로 양자화되어, 클라이언트 예측과 서버 시뮬레이션이 완전히 같은 값을 쓴다.

const FLAG_JUMP := 1
const FLAG_INTERACT := 2
const VALID_FLAGS := FLAG_JUMP | FLAG_INTERACT
const QUANT := 127

var seq: int = 0
var move_x: int = 0   # 월드 X축 이동 의도
var move_z: int = 0   # 월드 Z축 이동 의도
var jump: bool = false
var interact: bool = false


func set_move(v: Vector2) -> void:
	var m := v.limit_length(1.0)
	move_x = clampi(roundi(m.x * QUANT), -QUANT, QUANT)
	move_z = clampi(roundi(m.y * QUANT), -QUANT, QUANT)


## 항상 길이 1 이하로 제한된 이동 벡터를 반환 (위조된 값도 여기서 제한됨)
func get_move() -> Vector2:
	return Vector2(float(move_x) / QUANT, float(move_z) / QUANT).limit_length(1.0)


func get_flags() -> int:
	var f := 0
	if jump:
		f |= FLAG_JUMP
	if interact:
		f |= FLAG_INTERACT
	return f


func copy() -> PlayerInput:
	var c := PlayerInput.new()
	c.seq = seq
	c.move_x = move_x
	c.move_z = move_z
	c.jump = jump
	c.interact = interact
	return c
