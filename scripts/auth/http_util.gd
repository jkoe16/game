class_name HttpUtil
extends RefCounted
## 간단한 비동기 HTTP 요청 헬퍼. 사용: var r := await HttpUtil.request(self, url, ...)
## 반환: {ok:bool, code:int, json:Variant, text:String, headers:PackedStringArray, net_error:int}

const TIMEOUT_SEC := 15.0


static func request(owner: Node, url: String, method := HTTPClient.METHOD_GET, body := "", headers: PackedStringArray = []) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT_SEC
	# 웹: 브라우저(fetch)가 gzip을 이미 풀어서 넘겨줌 → Godot가 다시 풀면 실패해 본문이 비어 버린다
	if OS.has_feature("web"):
		req.accept_gzip = false
	owner.add_child(req)
	var err := req.request(url, headers, method, body)
	if err != OK:
		req.queue_free()
		return {"ok": false, "code": 0, "json": null, "text": "", "headers": PackedStringArray(), "net_error": err}
	var res: Array = await req.request_completed
	req.queue_free()
	var result: int = res[0]
	var code: int = res[1]
	var text: String = (res[3] as PackedByteArray).get_string_from_utf8()
	return {
		"ok": result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300,
		"code": code,
		"json": JSON.parse_string(text) if text != "" else null,
		"text": text,
		"headers": res[2],
		"net_error": result,
	}


static func post_json(owner: Node, url: String, data: Dictionary) -> Dictionary:
	return await request(owner, url, HTTPClient.METHOD_POST, JSON.stringify(data), PackedStringArray(["Content-Type: application/json"]))


static func post_form(owner: Node, url: String, data: Dictionary) -> Dictionary:
	var parts: PackedStringArray = []
	for k in data:
		parts.append("%s=%s" % [str(k).uri_encode(), str(data[k]).uri_encode()])
	return await request(owner, url, HTTPClient.METHOD_POST, "&".join(parts), PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]))


## Cache-Control: max-age=N 값 (없으면 기본값)
static func max_age(headers: PackedStringArray, default_sec := 3600) -> int:
	for h in headers:
		var lower := h.to_lower()
		if lower.begins_with("cache-control:"):
			var idx := lower.find("max-age=")
			if idx >= 0:
				return int(lower.substr(idx + 8).get_slice(",", 0))
	return default_sec
