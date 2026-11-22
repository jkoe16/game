class_name FirestoreClient
extends Node
## Firestore REST API 클라이언트 (클라이언트·서버 공용).
##  - 클라이언트: 플레이어의 Firebase ID 토큰으로 호출 → 보안 규칙 적용
##  - 게임 서버: 서비스 계정 액세스 토큰으로 호출 → 규칙 우회(관리자). 서버 전용 데이터 기록에 사용
## 인증 토큰은 token_provider(Callable, await 가능, String 반환)로 받는다.
## 모든 메서드 반환: {ok:bool, status:int, data:Dictionary(문서 필드, 일반 GDScript 값), error:String}

var base_url := "https://firestore.googleapis.com/v1"
var project_id := ""
var token_provider: Callable


func setup(p_project_id: String, p_token_provider: Callable, p_base_url := "") -> void:
	project_id = p_project_id
	token_provider = p_token_provider
	if p_base_url != "":
		base_url = p_base_url


func doc_name(path: String) -> String:
	return "projects/%s/databases/(default)/documents/%s" % [project_id, path]


## 문서 읽기. 없으면 ok=false, status=404
func get_doc(path: String) -> Dictionary:
	var r := await _call(HTTPClient.METHOD_GET, "/" + doc_name(path), "")
	if r["ok"]:
		r["data"] = decode_fields(r["json"].get("fields", {}))
	return r


## 지정 필드만 생성/수정 (updateMask). 문서가 없으면 만든다.
func set_fields(path: String, fields: Dictionary) -> Dictionary:
	var mask: PackedStringArray = []
	for k in fields:
		mask.append("updateMask.fieldPaths=" + str(k).uri_encode())
	var url := "/" + doc_name(path) + "?" + "&".join(mask)
	return await _call(HTTPClient.METHOD_PATCH, url, JSON.stringify({"fields": encode_fields(fields)}))


## 원자적 증가 + 서버 시각 기록 (문서가 없으면 생성). increments: {필드: 정수}, server_time_fields: [필드]
func increment(path: String, increments: Dictionary, server_time_fields: Array = []) -> Dictionary:
	var transforms: Array = []
	for k in increments:
		transforms.append({"fieldPath": k, "increment": encode_value(increments[k])})
	for k in server_time_fields:
		transforms.append({"fieldPath": k, "setToServerValue": "REQUEST_TIME"})
	var body := {"writes": [{
		"update": {"name": doc_name(path), "fields": {}},
		"updateMask": {"fieldPaths": []},
		"updateTransforms": transforms,
	}]}
	return await _call(HTTPClient.METHOD_POST, "/projects/%s/databases/(default)/documents:commit" % project_id, JSON.stringify(body))


func _call(method: int, path_and_query: String, body: String) -> Dictionary:
	var token: String = await token_provider.call() if token_provider.is_valid() else ""
	if token == "":
		return {"ok": false, "status": 401, "data": {}, "error": "no_token", "json": null}
	var headers := PackedStringArray(["Authorization: Bearer " + token, "Content-Type: application/json"])
	var r := await HttpUtil.request(self, base_url + path_and_query, method, body, headers)
	var err := ""
	if not r["ok"]:
		if typeof(r["json"]) == TYPE_DICTIONARY and typeof(r["json"].get("error")) == TYPE_DICTIONARY:
			err = str(r["json"]["error"].get("status", r["json"]["error"].get("message", "")))
		else:
			err = "network" if r["code"] == 0 else "HTTP_%d" % r["code"]
	return {"ok": r["ok"], "status": r["code"], "data": {}, "error": err, "json": r["json"] if typeof(r["json"]) == TYPE_DICTIONARY else {}}


# ------------------------------------------------------------------ 값 변환 (Firestore typed JSON ↔ GDScript)

static func encode_fields(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[str(k)] = encode_value(d[k])
	return out


static func encode_value(v: Variant) -> Dictionary:
	match typeof(v):
		TYPE_NIL:
			return {"nullValue": null}
		TYPE_BOOL:
			return {"booleanValue": v}
		TYPE_INT:
			return {"integerValue": str(v)}  # Firestore는 64비트 정수를 문자열로 주고받는다
		TYPE_FLOAT:
			return {"doubleValue": v}
		TYPE_STRING, TYPE_STRING_NAME:
			return {"stringValue": str(v)}
		TYPE_DICTIONARY:
			return {"mapValue": {"fields": encode_fields(v)}}
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY:
			var vals: Array = []
			for x in v:
				vals.append(encode_value(x))
			return {"arrayValue": {"values": vals}}
	return {"stringValue": str(v)}


static func decode_fields(fields: Variant) -> Dictionary:
	var out := {}
	if typeof(fields) != TYPE_DICTIONARY:
		return out
	for k in fields:
		out[k] = decode_value(fields[k])
	return out


static func decode_value(v: Variant) -> Variant:
	if typeof(v) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = v
	if d.has("integerValue"):
		return int(str(d["integerValue"]))
	if d.has("doubleValue"):
		return float(d["doubleValue"])
	if d.has("booleanValue"):
		return d["booleanValue"] == true
	if d.has("stringValue"):
		return str(d["stringValue"])
	if d.has("timestampValue"):
		return str(d["timestampValue"])
	if d.has("mapValue"):
		return decode_fields(d["mapValue"].get("fields", {}))
	if d.has("arrayValue"):
		var arr: Array = []
		for x in d["arrayValue"].get("values", []):
			arr.append(decode_value(x))
		return arr
	return null
