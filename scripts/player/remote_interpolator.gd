class_name RemoteInterpolator
extends Node
## 원격 플레이어 보간: 서버 스냅샷을 버퍼에 쌓고, 약 100ms 과거 시점을 두 스냅샷 사이에서 보간해 표시한다.
## 원격 플레이어는 물리 시뮬레이션을 하지 않는다 (충돌 비활성).

const MAX_BUFFER := 40
const TELEPORT_DISTANCE := 5.0

var body: PlayerBody
var visual: CharacterVisual
var client: Node   # GameClient (get_render_tick 제공)
var buffer: Array = []
var last_position := Vector3.ZERO


func push(e: Dictionary) -> void:
	if buffer.is_empty() or int(e["tick"]) > int(buffer.back()["tick"]):
		buffer.append(e)
		if buffer.size() > MAX_BUFFER:
			buffer.pop_front()


func _process(delta: float) -> void:
	if buffer.is_empty() or client == null:
		return
	var rt: float = client.get_render_tick()
	while buffer.size() > 2 and float(buffer[1]["tick"]) <= rt:
		buffer.pop_front()

	var a: Dictionary = buffer[0]
	var b: Dictionary = buffer[1] if buffer.size() > 1 else a
	var t := 0.0
	var span := int(b["tick"]) - int(a["tick"])
	if span > 0:
		t = clampf((rt - float(a["tick"])) / span, 0.0, 1.0)
	var pa: Vector3 = a["pos"]
	var pb: Vector3 = b["pos"]
	if pa.distance_to(pb) > TELEPORT_DISTANCE:
		t = 1.0  # 리스폰 등 순간이동은 보간하지 않음
	body.global_position = pa.lerp(pb, t)
	last_position = body.global_position

	if visual:
		visual.set_target_yaw(lerp_angle(float(a["yaw"]), float(b["yaw"]), t))
		var vel: Vector3 = (a["vel"] as Vector3).lerp(b["vel"], t)
		visual.update_motion(vel, (int(b["flags"]) & SnapshotCodec.FLAG_GROUNDED) != 0, delta)
