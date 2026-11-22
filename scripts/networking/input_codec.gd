class_name InputCodec
extends RefCounted
## 입력 패킷 직렬화. 형식: [count:u8] + count * [seq:u32, move_x:s8, move_z:s8, flags:u8]
## decode()는 형식이 조금이라도 어긋나면 빈 배열을 반환한다 (서버는 이를 위반으로 기록).

const BYTES_PER_INPUT := 7
const MAX_INPUTS_PER_PACKET := 16


static func encode(inputs: Array) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(inputs.size())
	for inp in inputs:
		buf.put_u32(inp.seq)
		buf.put_8(inp.move_x)
		buf.put_8(inp.move_z)
		buf.put_u8(inp.get_flags())
	return buf.data_array


static func decode(bytes: PackedByteArray) -> Array[PlayerInput]:
	var out: Array[PlayerInput] = []
	if bytes.size() < 1:
		return out
	var count: int = bytes[0]
	if count < 1 or count > MAX_INPUTS_PER_PACKET:
		return out
	if bytes.size() != 1 + count * BYTES_PER_INPUT:
		return out
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	buf.seek(1)
	for i in count:
		var inp := PlayerInput.new()
		inp.seq = buf.get_u32()
		inp.move_x = clampi(buf.get_8(), -PlayerInput.QUANT, PlayerInput.QUANT)
		inp.move_z = clampi(buf.get_8(), -PlayerInput.QUANT, PlayerInput.QUANT)
		var flags := buf.get_u8()
		if flags & ~PlayerInput.VALID_FLAGS:
			out.clear()
			return out
		inp.jump = (flags & PlayerInput.FLAG_JUMP) != 0
		inp.interact = (flags & PlayerInput.FLAG_INTERACT) != 0
		out.append(inp)
	out.sort_custom(func(a: PlayerInput, b: PlayerInput) -> bool: return a.seq < b.seq)
	return out
