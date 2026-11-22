class_name Validation
extends RefCounted
## 서버 측 입력값 검증 유틸리티.

const NICKNAME_MIN := 2
const NICKNAME_MAX := 16
const TOKEN_MAX := 4096  # Firebase ID 토큰은 보통 900~1200자 (제공자 정보에 따라 더 길어짐)

static var _nick_re: RegEx


## 허용: 영문, 숫자, 밑줄, 완성형 한글. 실패 시 "" 반환.
static func sanitize_nickname(v: Variant) -> String:
	if typeof(v) != TYPE_STRING:
		return ""
	var s: String = (v as String).strip_edges()
	if s.length() < NICKNAME_MIN or s.length() > NICKNAME_MAX:
		return ""
	if _nick_re == null:
		_nick_re = RegEx.create_from_string("^[0-9A-Za-z_\\x{AC00}-\\x{D7A3}]+$")
	if _nick_re.search(s) == null:
		return ""
	return s


static func is_valid_token_shape(v: Variant) -> bool:
	return typeof(v) == TYPE_STRING and (v as String).length() > 0 and (v as String).length() <= TOKEN_MAX
