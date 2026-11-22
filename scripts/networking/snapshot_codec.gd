class_name SnapshotCodec
extends RefCounted
## 서버 상태 스냅샷 직렬화.
## 형식: [tick:u32, count:u8] + count * [id:s32, pos:3f, vel:3f, yaw:f, air:f, stun:f, boost:f,
##                                       flags:u8, mover:s8, ack:u32, ack_tick:u32]
## ack_tick = 서버가 ack 입력을 처리한 서버 틱 → 클라이언트가 장애물 예측 틱을 맞추는 데 사용
## 플레이어당 54바이트 → 8인 기준 약 440바이트 * 30Hz ≈ 13KB/s (추후 양자화로 축소 예정)

const HEADER_BYTES := 5
const BYTES_PER_PLAYER := 54
const FLAG_GROUNDED := 1
const FLAG_FROZEN := 2
const FLAG_OUT := 4        # 탈락/관전
const MAX_PLAYERS_PER_SNAPSHOT := 64


static func encode(tick: int, entries: Array) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u32(tick)
	buf.put_u8(entries.size())
	for e in entries:
		buf.put_32(e["id"])
		_put_vec3(buf, e["pos"])
		_put_vec3(buf, e["vel"])
		buf.put_float(e["yaw"])
		buf.put_float(e["air"])
		buf.put_float(e.get("stun", 0.0))
		buf.put_float(e.get("boost", 0.0))
		buf.put_u8(e["flags"])
		buf.put_8(e.get("mover", -1))
		buf.put_u32(e["ack"])
		buf.put_u32(e.get("ack_tick", 0))
	return buf.data_array


## 실패 시 빈 Dictionary 반환
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < HEADER_BYTES:
		return {}
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	var tick := buf.get_u32()
	var count := buf.get_u8()
	if count > MAX_PLAYERS_PER_SNAPSHOT or bytes.size() != HEADER_BYTES + count * BYTES_PER_PLAYER:
		return {}
	var players: Array = []
	for i in count:
		var e := {}
		e["id"] = buf.get_32()
		e["pos"] = _get_vec3(buf)
		e["vel"] = _get_vec3(buf)
		e["yaw"] = buf.get_float()
		e["air"] = buf.get_float()
		e["stun"] = buf.get_float()
		e["boost"] = buf.get_float()
		e["flags"] = buf.get_u8()
		e["mover"] = buf.get_8()
		e["ack"] = buf.get_u32()
		e["ack_tick"] = buf.get_u32()
		e["tick"] = tick
		players.append(e)
	return {"tick": tick, "players": players}


static func _put_vec3(buf: StreamPeerBuffer, v: Vector3) -> void:
	buf.put_float(v.x)
	buf.put_float(v.y)
	buf.put_float(v.z)


static func _get_vec3(buf: StreamPeerBuffer) -> Vector3:
	var x := buf.get_float()
	var y := buf.get_float()
	var z := buf.get_float()
	return Vector3(x, y, z)
