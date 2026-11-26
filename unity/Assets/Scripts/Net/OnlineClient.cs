using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Networking;
using static PartyWorld.Net.GodotVariant;

namespace PartyWorld.Net
{
    /// <summary>
    /// 온라인 접속 (Godot scripts/multiplayer/game_client.gd 이식). 지금 쓰는 Godot 서버(Render)에 그대로 붙는다.
    /// 그래서 Godot 판 사람과 유니티 판 사람이 같은 광장·미니게임에서 함께 논다.
    ///
    /// 흐름: 게스트 로그인 → 웹소켓 연결 → 서버가 피어 번호를 줌 → c_hello → s_welcome(맵·사람들) → 매 틱 c_input,
    ///       서버는 초당 30번 s_snapshot(위치), 바뀔 때마다 s_mode_state(단계·점수), 포털에 서면 s_transfer(다른 서버로).
    /// 연결이 갑자기 끊기면 같은 주소로 다시 접속해 hello 에 "resume" 을 보내 같은 자리에서 이어 한다.
    /// </summary>
    public class OnlineClient : MonoBehaviour
    {
        public static OnlineClient I;

        /// <summary>공개 서버 (Godot config/online.cfg 와 같은 주소)</summary>
        public const string PublicServer = "wss://threed-party-world.onrender.com";

        /// <summary>
        /// 접속할 서버. 테스트용으로 주소 끝 ?server=ws://127.0.0.1:포트 를 쓰면 내 PC 서버(개발 모드)로 간다.
        /// 다른 주소는 받지 않는다 (남의 서버로 로그인 토큰이 새지 않게).
        /// </summary>
        public static string ServerUrl
        {
            get
            {
                string url = Application.absoluteURL ?? "";
                int i = url.IndexOf("server=", StringComparison.Ordinal);
                if (i >= 0)
                {
                    string v = UnityWebRequest.UnEscapeURL(url.Substring(i + 7).Split('&')[0]);
                    if (v.StartsWith("ws://127.0.0.1:") || v.StartsWith("ws://localhost:")) return v.TrimEnd('/');
                }
                return PublicServer;
            }
        }

        /// <summary>내 PC 테스트 서버면 로그인 없이 개발용 토큰</summary>
        static bool IsLocal(string url) => url.StartsWith("ws://127.0.0.1:") || url.StartsWith("ws://localhost:");
        const int MaxAttemptsCloud = 45;     // 무료 서버가 깨어나는 데 최대 1분 → 2초 간격 약 90초
        const float RetrySec = 2f, ReconnectRetrySec = 1f;
        const int ReconnectMaxAttempts = 25;
        const float ConnectTimeoutSec = 25f;

        public GameSession session;
        public PlayerBody body;
        public LocalPlayerController ctrl;
        public ThirdPersonCamera cam;
        /// <summary>온라인이 끝났을 때 (이유: left, rejected:…, connection_failed …). 혼자 하기 광장으로 돌아간다</summary>
        public Action<string> onEnded;

        public string nickname = "Player";
        public int color, hat;
        /// <summary>방 코드 (공개 광장이면 "")</summary>
        public string roomCode = "";
        public string status = "";

        public int myId;
        public bool welcomed;
        public string mapId = "", modeId = "", serverVersion = "";
        public Dictionary<object, object> modeState = new Dictionary<object, object>();
        public uint latestTick;
        public double serverTickEst;
        public int snapshots;
        public readonly Dictionary<int, RemotePlayer> remotes = new Dictionary<int, RemotePlayer>();

        public double RenderTick => serverTickEst - NetConst.InterpDelayTicks;
        public bool Busy => _url != null && !_ended;

        WireSocket _sock;
        readonly GodotWire _wire = new GodotWire();
        string _url;
        bool _gotId, _ended, _left, _reconnecting;
        int _attempts;
        float _openedAt, _lastSnapAt;
        string _sessionToken = "", _reject = "";
        bool _connectPending;

        // ------------------------------------------------------------------ 시작·끝

        public static OnlineClient Create(GameSession session, PlayerBody body, LocalPlayerController ctrl, ThirdPersonCamera cam)
        {
            var go = new GameObject("OnlineClient");
            DontDestroyOnLoad(go);
            var c = go.AddComponent<OnlineClient>();
            c.session = session;
            c.body = body;
            c.ctrl = ctrl;
            c.cam = cam;
            I = c;
            CharacterVisual.onLocalEmote += c.OnLocalEmote;
            return c;
        }

        void OnDestroy()
        {
            CharacterVisual.onLocalEmote -= OnLocalEmote;
            if (I == this) I = null;
        }

        /// <summary>빠른 매칭: 자리가 남은 공개 광장으로</summary>
        public void QuickMatch() => StartCoroutine(QuickMatchRoutine());

        /// <summary>방 코드로 입장 (없는 코드면 새 방이 만들어진다)</summary>
        public void JoinRoom(string code)
        {
            roomCode = code;
            Begin(ServerUrl + "/r/" + code);
        }

        /// <summary>새 방 만들기: 쓰이지 않는 코드를 골라 입장</summary>
        public void CreateRoom() => StartCoroutine(CreateRoomRoutine());

        public void Begin(string url)
        {
            StopAllCoroutines();
            CloseSocket();
            _url = url;
            _ended = _left = _reconnecting = false;
            _attempts = 0;
            _sessionToken = "";
            _reject = "";
            welcomed = false;
            if (!url.Contains("/r/")) roomCode = "";
            StartCoroutine(ConnectRoutine(0f));
        }

        /// <summary>스스로 나가기: 서버에 알려 자리를 바로 비우게 한 뒤 닫는다</summary>
        public void Leave()
        {
            if (_ended) return;
            _left = true;
            if (welcomed && _sock != null && _sock.State == WireSocket.Open)
            {
                _sock.Send(GodotWire.BuildRpc("c_leave"));
                StartCoroutine(CloseLater(0.15f));
            }
            else CloseSocket();
            End("left");
        }

        IEnumerator CloseLater(float sec)
        {
            var s = _sock;
            _sock = null;
            yield return new WaitForSecondsRealtime(sec);
            s?.Close();
        }

        void End(string reason)
        {
            if (_ended) return;
            _ended = true;
            if (!_left) CloseSocket();
            ResetWorld();
            ctrl.StopOnline();
            body.frozen = false;
            ClearHud();
            onEnded?.Invoke(reason);
        }

        void CloseSocket()
        {
            _sock?.Close();
            _sock = null;
        }

        // ------------------------------------------------------------------ 접속

        IEnumerator QuickMatchRoutine()
        {
            status = "자리가 있는 광장을 찾는 중...";
            string path = "/";
            yield return GetJson("/api/quickmatch", text =>
            {
                var r = JsonUtility.FromJson<QuickRes>(text);
                if (r != null && r.ok && !string.IsNullOrEmpty(r.path) && r.path.StartsWith("/p/")) path = r.path;
            });
            Begin(path == "/" ? ServerUrl : ServerUrl + path);
        }

        IEnumerator CreateRoomRoutine()
        {
            status = "방을 만드는 중...";
            string code = NewRoomCode();
            for (int i = 0; i < 5; i++)
            {
                bool answered = false, exists = false;
                yield return GetJson("/api/room/" + code, text =>
                {
                    var r = JsonUtility.FromJson<RoomRes>(text);
                    if (r != null && r.ok) { answered = true; exists = r.exists; }
                });
                if (!answered || !exists) break; // 답이 없으면(서버가 자는 중) 그냥 접속
                code = NewRoomCode();
            }
            JoinRoom(code);
        }

        [Serializable] class QuickRes { public bool ok; public string path; }
        [Serializable] class RoomRes { public bool ok; public bool exists; public int players; public bool full; }

        IEnumerator GetJson(string path, Action<string> onOk)
        {
            string server = ServerUrl;
            string http = server.StartsWith("wss://") ? "https://" + server.Substring(6) + path : "http://" + server.Substring(5) + path;
            using (var req = UnityWebRequest.Get(http))
            {
                req.timeout = 6;
                yield return req.SendWebRequest();
                if (req.result == UnityWebRequest.Result.Success)
                {
                    try { onOk(req.downloadHandler.text); } catch (Exception) { }
                }
            }
        }

        public const string RoomChars = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

        public static string NewRoomCode()
        {
            var s = new char[4];
            for (int i = 0; i < 4; i++) s[i] = RoomChars[UnityEngine.Random.Range(0, RoomChars.Length)];
            return new string(s);
        }

        /// <summary>입력값 정리: 대문자, 영문/숫자만, 4~8자가 아니면 ""</summary>
        public static string NormalizeRoomCode(string text)
        {
            var sb = new System.Text.StringBuilder();
            foreach (char ch in (text ?? "").Trim().ToUpperInvariant())
                if ((ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9')) sb.Append(ch);
            return sb.Length >= 4 && sb.Length <= 8 ? sb.ToString() : "";
        }

        IEnumerator ConnectRoutine(float delay)
        {
            _connectPending = true;
            if (delay > 0f) yield return new WaitForSecondsRealtime(delay);
            if (_ended) yield break;
            status = _reconnecting ? "다시 접속하는 중..." : "로그인 준비 중...";
            if (!IsLocal(_url)) yield return GuestAuth.Ensure();
            _connectPending = false;
            if (_ended) yield break;
            if (!IsLocal(_url) && GuestAuth.IdToken == "")
            {
                status = "로그인에 실패했어요: " + GuestAuth.LastError;
                End("auth_failed");
                yield break;
            }
            _attempts++;
            _wire.Reset();
            _gotId = false;
            _openedAt = Time.realtimeSinceStartup;
            _sock = WireSocket.Connect(_url);
            if (_reconnecting) status = $"연결이 끊겼어요. 다시 접속하는 중... ({_attempts}/{MaxAttempts})";
            else if (_attempts > 3) status = $"서버를 깨우는 중이에요... 무료 서버는 최대 1분 걸려요 ({(int)(_attempts * RetrySec)}초)";
            else status = "서버 접속 중...";
        }

        int MaxAttempts => _reconnecting ? ReconnectMaxAttempts : MaxAttemptsCloud;

        void ScheduleConnect(float delay)
        {
            if (_connectPending || _ended) return;
            StartCoroutine(ConnectRoutine(delay));
        }

        void OnSocketClosed()
        {
            CloseSocket();
            if (_ended || _left) return;
            if (_reject != "")
            {
                status = "서버가 입장을 거절했어요: " + RejectText(_reject);
                End("rejected:" + _reject);
                return;
            }
            if (welcomed && _sessionToken != "")
            {
                // 갑자기 끊김 → 같은 서버에 다시 (서버가 30초 동안 자리를 남겨 둔다)
                BeginReconnect(ReconnectRetrySec * 0.5f);
                return;
            }
            if (_attempts < MaxAttempts)
            {
                ScheduleConnect(_reconnecting ? ReconnectRetrySec : RetrySec);
                return;
            }
            status = _reconnecting ? "다시 접속하지 못했어요." : "서버에 연결할 수 없어요.";
            End(_reconnecting ? "reconnect_failed" : "connection_failed");
        }

        void BeginReconnect(float delay)
        {
            CloseSocket();
            _reconnecting = true;
            welcomed = false;
            _attempts = 0;
            ResetRemotes();
            status = "연결이 끊겼어요. 다시 접속하는 중...";
            ScheduleConnect(delay);
        }

        static string RejectText(string r)
        {
            switch (r)
            {
                case "room_full": return "방이 꽉 찼어요";
                case "version_mismatch": return "게임 버전이 서버와 달라요 (새로고침해 주세요)";
                case "bad_nickname": return "닉네임은 2~16자 한글/영문/숫자/_ 만 돼요";
                case "auth_failed": return "로그인 확인에 실패했어요";
                case "logged_in_elsewhere": return "다른 곳에서 같은 계정으로 들어왔어요";
            }
            return r;
        }

        // ------------------------------------------------------------------ 매 프레임

        void Update()
        {
            if (_sock != null)
            {
                int st = _sock.State;
                while (_sock != null && _sock.TryReceive(out var msg)) Handle(msg);
                if (_sock != null)
                {
                    if (st == WireSocket.Closed) OnSocketClosed();
                    else if (!welcomed && Time.realtimeSinceStartup - _openedAt > ConnectTimeoutSec) OnSocketClosed();
                    else if (welcomed && Time.realtimeSinceStartup - _lastSnapAt > NetConst.SnapshotSilenceMs / 1000f)
                    {
                        // 회선이 조용히 끊김 (끊김 신호가 아직 안 옴) → 바로 다시 접속
                        if (_sessionToken != "") BeginReconnect(0.1f);
                        else OnSocketClosed();
                    }
                }
            }
            if (welcomed)
            {
                serverTickEst += Time.deltaTime * NetConst.TickRate;
                if (serverTickEst > latestTick + 3) serverTickEst = Mathf.Lerp((float)serverTickEst, latestTick + 3, 0.2f);
            }
            UpdateHud();
        }

        void Handle(byte[] msg)
        {
            if (!_gotId)
            {
                if (msg.Length == 4)
                {
                    myId = BitConverter.ToInt32(msg, 0);
                    _gotId = true;
                    SendHello();
                }
                return;
            }
            bool isRpc;
            GodotWire.Rpc rpc;
            byte[] reply;
            try { isRpc = _wire.Parse(msg, out rpc, out reply); }
            catch (Exception e)
            {
                Debug.LogWarning("[online] bad packet: " + e.Message);
                return;
            }
            if (reply != null) _sock?.Send(reply);
            if (!isRpc) return;
            try { Dispatch(rpc); }
            catch (Exception e) { Debug.LogException(e); }
        }

        void SendHello()
        {
            var hello = new Dictionary<object, object>
            {
                ["protocol"] = NetConst.ProtocolVersion,
                ["token"] = IsLocal(_url) ? "dev-guest" : GuestAuth.IdToken,
                ["nickname"] = nickname,
                ["appearance"] = new Dictionary<object, object> { ["color"] = color, ["hat"] = hat },
                ["platform"] = Application.isMobilePlatform ? "mobile" : "web",
            };
            if (_sessionToken != "") hello["resume"] = _sessionToken;
            _sock.Send(GodotWire.BuildRpc("c_hello", hello));
            status = _reconnecting ? "다시 들어가는 중..." : "입장 요청 중...";
        }

        public void SendInputs(byte[] packet)
        {
            if (welcomed && _sock != null && _sock.State == WireSocket.Open)
                _sock.Send(GodotWire.BuildRpc("c_input", packet));
        }

        void OnLocalEmote(int e)
        {
            if (welcomed && _sock != null && _sock.State == WireSocket.Open)
                _sock.Send(GodotWire.BuildRpc("c_emote", e));
        }

        // ------------------------------------------------------------------ 서버 메시지

        static Vector3 V(object v) => v is GVec3 g ? new Vector3(g.x, g.y, g.z) : Vector3.zero;

        void Dispatch(GodotWire.Rpc rpc)
        {
            object a0 = rpc.args.Length > 0 ? rpc.args[0] : null;
            switch (rpc.method)
            {
                case "s_welcome": OnWelcome(Dict(a0)); break;
                case "s_reject":
                    _reject = Str(a0);
                    status = "서버가 입장을 거절했어요: " + RejectText(_reject);
                    break;
                case "s_player_joined":
                    if (welcomed) SpawnRemote(Dict(a0));
                    break;
                case "s_player_left":
                {
                    int id = (int)Int(a0);
                    if (remotes.TryGetValue(id, out var rp))
                    {
                        Destroy(rp.gameObject);
                        remotes.Remove(id);
                    }
                    break;
                }
                case "s_emote":
                {
                    int id = (int)Int(a0);
                    int e = rpc.args.Length > 1 ? (int)Int(rpc.args[1]) : -1;
                    if (id != myId && remotes.TryGetValue(id, out var rp)) rp.PlayEmote(e);
                    break;
                }
                case "s_snapshot":
                    if (a0 is byte[] bytes) OnSnapshot(bytes);
                    break;
                case "s_mode_state": OnModeState(Dict(a0)); break;
                case "s_transfer": OnTransfer(Str(a0), rpc.args.Length > 1 ? Str(rpc.args[1]) : ""); break;
                case "s_notice":
                {
                    string text = Str(a0);
                    if (text.StartsWith("!")) text = text.Substring(1);
                    Hud.Banner(text, 2.5f);
                    break;
                }
            }
        }

        void OnWelcome(Dictionary<object, object> d)
        {
            if (welcomed) return;
            string map = Str(Get(d, "map_id"));
            if (!session.LoadOnlineMap(map))
            {
                status = "알 수 없는 맵: " + map;
                return;
            }
            welcomed = true;
            bool resumed = Bool(Get(d, "resumed"));
            myId = (int)Int(Get(d, "peer_id"), myId);
            mapId = map;
            modeId = Str(Get(d, "mode_id"));
            serverVersion = Str(Get(d, "server_version"), "?");
            _sessionToken = Str(Get(d, "session"));
            latestTick = (uint)Int(Get(d, "tick"));
            serverTickEst = latestTick;
            snapshots = 0;
            _lastSnapAt = Time.realtimeSinceStartup;
            ResetRemotes();
            foreach (var o in List(Get(d, "players")))
            {
                var info = Dict(o);
                if ((int)Int(Get(info, "peer_id")) == myId)
                {
                    body.Teleport(V(Get(info, "pos")));
                    if (cam != null) cam.yaw = 0f;
                }
                else SpawnRemote(info);
            }
            ctrl.StartOnline(this, (int)latestTick);
            status = resumed ? "다시 연결됐어요! 이어서 놀아요" : _reconnecting ? "다시 연결됐어요" : "";
            _reconnecting = false;
            _attempts = 0;
            if (Get(d, "mode_state") is Dictionary<object, object> ms) OnModeState(ms);
            Debug.Log($"[online] welcomed into {map} as {myId} with {remotes.Count} others");
        }

        void SpawnRemote(Dictionary<object, object> info)
        {
            int id = (int)Int(Get(info, "peer_id"));
            if (id == 0 || id == myId || remotes.ContainsKey(id)) return;
            var app = Dict(Get(info, "appearance"));
            var rp = RemotePlayer.Spawn(this, id, Str(Get(info, "nickname"), "?"), (int)Int(Get(app, "color")), (int)Int(Get(app, "hat")), V(Get(info, "pos")));
            remotes[id] = rp;
        }

        void OnSnapshot(byte[] packet)
        {
            if (!welcomed) return;
            var list = SnapshotCodec.Decode(packet, out uint t);
            if (list == null) return;
            if (t <= latestTick && snapshots > 0) return;
            latestTick = t;
            snapshots++;
            _lastSnapAt = Time.realtimeSinceStartup;
            if (Math.Abs(serverTickEst - t) > 8.0) serverTickEst = t;
            foreach (var e in list)
            {
                if (e.id == myId) ctrl.QueueReconcile(e);
                else if (remotes.TryGetValue(e.id, out var rp)) rp.Push(e);
            }
        }

        void OnModeState(Dictionary<object, object> s)
        {
            modeState = s;
            var map = session.map;
            if (map != null)
            {
                map.roundStartTick = (int)Int(Get(s, "round_start_tick"));
                ApplyMapState(map, Dict(Get(s, "extra")));
            }
            var me = MyEntry();
            string phase = Str(Get(s, "phase"));
            body.frozen = phase == "countdown" || Str(Get(me, "status")) == "finished";
        }

        public Dictionary<object, object> MyEntry() => Dict(Get(Dict(Get(modeState, "players")), myId.ToString()));

        readonly List<CoinArena.Coin> _coins = new List<CoinArena.Coin>();

        void ApplyMapState(GameMap map, Dictionary<object, object> extra)
        {
            switch (map)
            {
                case SurvivalArena arena:
                    arena.crumbleStart = (int)Int(Get(extra, "crumble"));
                    break;
                case CoopRooms rooms:
                {
                    var opened = List(Get(extra, "opened"));
                    for (int i = 0; i < rooms.gates.Count; i++)
                    {
                        bool open = false;
                        foreach (var o in opened) if (Int(o, -1) == i) open = true;
                        rooms.SetGateOpen(i, open);
                    }
                    var occ = List(Get(extra, "occupied"));
                    var flags = new bool[occ.Count];
                    for (int i = 0; i < occ.Count; i++) flags[i] = Bool(occ[i]);
                    rooms.ShowPlates((int)Int(Get(extra, "stage")), flags);
                    break;
                }
                case CoinArena arena:
                {
                    var data = List(Get(extra, "coins"));
                    while (_coins.Count < data.Count) _coins.Add(new CoinArena.Coin());
                    while (_coins.Count > data.Count) _coins.RemoveAt(_coins.Count - 1);
                    for (int i = 0; i < data.Count; i++)
                    {
                        var c = List(data[i]);
                        if (c.Count < 4) continue;
                        _coins[i].pos = new Vector3((float)Num(c[0]), (float)Num(c[1]), (float)Num(c[2]));
                        _coins[i].alive = Int(c[3]) == 1;
                        _coins[i].value = c.Count > 4 ? (int)Int(c[4]) : 1;
                    }
                    arena.RenderCoins(_coins);
                    break;
                }
            }
        }

        /// <summary>다른 서버로 이동 (광장 → 미니게임 → 광장). 같은 게이트웨이의 다른 경로</summary>
        void OnTransfer(string route, string target)
        {
            string next;
            if (route.StartsWith("/")) next = Origin(_url) + route;
            else if (route.StartsWith("ws://") || route.StartsWith("wss://")) next = route;
            else return; // "host:port" 형식은 PC 전용 서버 (웹에서는 안 씀)
            Debug.Log($"[online] transfer -> {route} ({target})");
            status = "이동 중...";
            CloseSocket();
            ResetWorld();
            ctrl.StopOnline();
            _url = next;
            _sessionToken = ""; // 세션 토큰은 서버마다 따로
            _reconnecting = false;
            _attempts = 0;
            welcomed = false;
            ScheduleConnect(0.2f);
        }

        static string Origin(string url)
        {
            int i = url.IndexOf("://", StringComparison.Ordinal);
            if (i < 0) return url;
            int slash = url.IndexOf('/', i + 3);
            return slash < 0 ? url : url.Substring(0, slash);
        }

        void ResetRemotes()
        {
            foreach (var rp in remotes.Values) if (rp != null) Destroy(rp.gameObject);
            remotes.Clear();
        }

        void ResetWorld()
        {
            welcomed = false;
            ResetRemotes();
            modeState = new Dictionary<object, object>();
            latestTick = 0;
            snapshots = 0;
            _coins.Clear();
        }

        // ------------------------------------------------------------------ 화면

        string _lastPhase = "";

        void ClearHud()
        {
            var hud = GameHud.I;
            if (hud == null) return;
            hud.SetTop("", "");
            hud.SetBig("");
            hud.HideResults();
            hud.SetBoard("");
            hud.SetStatus("");
            hud.SetHold("", -1f);
        }

        void UpdateHud()
        {
            var hud = GameHud.I;
            if (hud == null || _ended || _url == null) return;
            hud.ShowExit(true, "나가기");
            hud.SetHold("", -1f);
            if (!welcomed)
            {
                hud.SetTop("", "");
                hud.SetBig("");
                hud.HideResults();
                hud.SetBoard("");
                hud.SetStatus(status);
                return;
            }
            // 함께 있는 사람 + 방 코드
            var names = new List<string> { "나(" + nickname + ")" };
            foreach (var rp in remotes.Values) if (rp != null) names.Add(rp.nickname);
            string people = $"함께 있는 사람 {names.Count}명: {string.Join(", ", names.GetRange(0, Mathf.Min(8, names.Count)))}{(names.Count > 8 ? $" 외 {names.Count - 8}명" : "")}";
            string room = roomCode != "" ? $"방 코드 {roomCode}   " : "";
            hud.SetStatus(status != "" ? status : room + people);

            var s = modeState;
            string phase = Str(Get(s, "phase"));
            string title = Str(Get(s, "title"));
            double secs = Math.Max(0.0, (Num(Get(s, "phase_end_tick")) - serverTickEst) / 60.0);
            var me = MyEntry();
            string myStatus = Str(Get(me, "status"));
            string big = "", rules = "";
            switch (phase)
            {
                case "lobby":
                case "":
                    hud.SetTop("", "");
                    LobbyHold(hud);
                    break;
                case "waiting":
                {
                    int n = Dict(Get(s, "players")).Count;
                    int need = (int)Int(Get(s, "min_players"), 1);
                    hud.SetTop(title, Num(Get(s, "phase_end_tick")) > 0 ? $"{Math.Ceiling(secs)}초 후 시작 ({n}명)" : $"참가자를 기다리는 중 {n}/{need}");
                    break;
                }
                case "countdown":
                    hud.SetTop(title, "");
                    big = secs > 0.05 ? ((int)Math.Ceiling(secs)).ToString() : "출발!";
                    rules = Str(Get(s, "rules"));
                    break;
                case "playing":
                {
                    int left = (int)Math.Ceiling(secs);
                    string score = Get(me, "score") != null ? $"내 점수 {Int(Get(me, "score"))}" : "";
                    hud.SetTop($"{title}   {left / 60}:{left % 60:00}", score);
                    if (myStatus == "out") big = "탈락! 관전 중";
                    else if (myStatus == "finished") big = "완주!";
                    else if (myStatus == "late") big = "다음 판을 기다려요";
                    else if (secs > 0.0 && secs <= 5.0) big = left.ToString();
                    break;
                }
                case "results":
                    hud.SetTop(title, "결과 발표");
                    break;
            }
            hud.SetBig(big, rules);
            var board = List(Get(s, "board"));
            var lines = new List<string>();
            for (int i = 0; i < board.Count && i < 8; i++) lines.Add(Str(board[i]));
            hud.SetBoard(phase == "results" ? "" : string.Join("\n", lines));

            var results = List(Get(s, "results"));
            if (phase == "results" && results.Count > 0) ShowResults(hud, results);
            else hud.HideResults();
            _lastPhase = phase;
        }

        void ShowResults(GameHud hud, List<object> results)
        {
            Dictionary<object, object> mine = null;
            var lines = new List<string>();
            foreach (var o in results)
            {
                var r = Dict(o);
                if ((int)Int(Get(r, "peer_id")) == myId) mine = r;
                if (lines.Count < 5) lines.Add($"{Int(Get(r, "rank"))}. {Str(Get(r, "nickname"))}  {Str(Get(r, "score"))}");
            }
            string head;
            if (Str(Get(modeState, "mode")) == "coop") head = mine != null && Bool(Get(mine, "win")) ? "미션 성공!" : "아쉬워요! 다음엔 꼭";
            else if (mine == null) head = "결과";
            else head = Bool(Get(mine, "win")) ? "1등! 축하해요!" : $"{Int(Get(mine, "rank"))}등";
            string foot = mine != null ? $"경험치 +{Int(Get(mine, "xp"))}" : "";
            hud.ShowResults(head, string.Join("\n", lines), foot);
        }

        // 광장 포털 입장 막대 (서버가 판정하고, 화면 표시만 여기서 같은 규칙으로 흉내 낸다)
        string _holdMode = "";
        float _holdTicks;

        void LobbyHold(GameHud hud)
        {
            if (!(session.map is LobbyPlaza lobby)) return;
            Vector3 pos = body.transform.position;
            string inside = "";
            foreach (var p in lobby.portals)
                if (new Vector2(pos.x - p.center.x, pos.z - p.center.z).magnitude <= p.radius && pos.y < 1.5f)
                {
                    inside = p.mode;
                    break;
                }
            if (inside != _holdMode) { _holdMode = inside; _holdTicks = 0; }
            if (inside == "") return;
            _holdTicks += Time.deltaTime * 60f;
            if (_holdTicks >= 90f) return;
            string name = inside;
            foreach (var m in LobbyPlaza.ModePortals) if (m.mode == inside) name = m.name;
            hud.SetHold(name, _holdTicks / 90f);
        }
    }
}
