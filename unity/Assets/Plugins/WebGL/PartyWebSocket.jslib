// 웹(WebGL)용 웹소켓: 브라우저의 WebSocket 을 그대로 쓴다. C# 은 매 프레임 꺼내 가는(폴링) 방식이라 콜백이 없다.
mergeInto(LibraryManager.library, {
  PwWsOpen: function (urlPtr) {
    var url = UTF8ToString(urlPtr);
    if (!window._pwws) window._pwws = { next: 1, socks: {} };
    var id = window._pwws.next++;
    var o = { q: [], ws: null, failed: false };
    window._pwws.socks[id] = o;
    try {
      o.ws = new WebSocket(url);
      o.ws.binaryType = "arraybuffer";
      o.ws.onmessage = function (e) {
        if (e.data instanceof ArrayBuffer) o.q.push(new Uint8Array(e.data));
      };
      o.ws.onerror = function () { o.failed = true; };
    } catch (e) {
      o.failed = true;
    }
    return id;
  },

  // 0 연결 중, 1 열림, 2 닫는 중, 3 닫힘
  PwWsState: function (id) {
    var o = window._pwws && window._pwws.socks[id];
    if (!o || !o.ws) return 3;
    return o.ws.readyState;
  },

  PwWsNextLength: function (id) {
    var o = window._pwws && window._pwws.socks[id];
    if (!o || o.q.length === 0) return -1;
    return o.q[0].length;
  },

  PwWsReceive: function (id, ptr, len) {
    var o = window._pwws && window._pwws.socks[id];
    if (!o || o.q.length === 0) return 0;
    var m = o.q.shift();
    var n = Math.min(len, m.length);
    HEAPU8.set(m.subarray(0, n), ptr);
    return n;
  },

  PwWsSend: function (id, ptr, len) {
    var o = window._pwws && window._pwws.socks[id];
    if (!o || !o.ws || o.ws.readyState !== 1) return 0;
    o.ws.send(HEAPU8.slice(ptr, ptr + len));
    return 1;
  },

  PwWsClose: function (id) {
    var o = window._pwws && window._pwws.socks[id];
    if (!o) return;
    try { if (o.ws) o.ws.close(); } catch (e) {}
    delete window._pwws.socks[id];
  },
});
