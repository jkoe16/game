using System.Collections.Generic;
using PartyWorld.Net;
using UnityEngine;

namespace PartyWorld
{
    /// <summary>
    /// 내 캐릭터 조작 (Godot scripts/player/local_player_controller.gd 이식).
    /// 매 물리 틱(60Hz): 입력 모으기 → 맵 갱신 → PlayerBody.Simulate().
    ///
    /// 온라인일 때 (online != null):
    ///   예측: 입력을 바로 시뮬레이션하고 (번호, 입력, 예측 위치)를 기록해 두며, 최근 입력 16개를 서버에 보낸다.
    ///   보정: 스냅샷의 ack(서버가 마지막으로 처리한 입력 번호)와 서버 위치를 같은 번호의 예측 위치와 비교해
    ///         5cm 넘게 어긋나면 서버 상태로 되돌린 뒤 아직 처리 안 된 입력을 다시 시뮬레이션한다.
    ///   떨어졌을 때 되살리기·포털 입장·점수는 전부 서버가 한다.
    /// </summary>
    public class LocalPlayerController : MonoBehaviour
    {
        const float CorrectionEpsilon = 0.05f;
        const int MaxHistory = 240;

        public PlayerBody body;
        public ThirdPersonCamera cam;
        /// <summary>모바일 가상 조이스틱 등 외부 입력 (x = 오른쪽, y = 앞). 키보드와 합산.</summary>
        public Vector2 externalMove;
        public bool externalJump;
        public float killHeight = -25f;
        public Vector3 spawnPoint = new Vector3(0f, 1f, 0f);
        /// <summary>맵·모드 진행 (없으면 맵 없이 이동만)</summary>
        public GameSession session;
        /// <summary>물리 틱 번호 (60Hz). 움직이는 장애물 위치가 이 번호로 정해진다. 온라인이면 서버 틱 기준.</summary>
        public int tick;

        /// <summary>온라인 접속 중이면 그 연결 (null = 혼자 하기)</summary>
        public OnlineClient online;
        /// <summary>보정 횟수 (테스트·화면 표시용)</summary>
        public int corrections, teleports;
        public float maxSmallCorrection;

        uint _seq;
        int _jumpHold;
        bool _jumpQueued;

        struct Hist { public PlayerInput input; public Vector3 pos; public int wt; }
        readonly List<Hist> _hist = new List<Hist>();
        readonly List<WireInput> _send = new List<WireInput>();
        int _tickOffset;
        bool _offsetValid;
        bool _hasPending;
        SnapEntry _pending;

        void Update()
        {
            // 키 누름은 화면 프레임에서 잡아 두었다가 다음 물리 틱에 넘긴다 (틱 사이 입력을 놓치지 않게)
            if (InputReader.JumpPressedThisFrame() || externalJump)
                _jumpQueued = true;
            externalJump = false;
        }

        GameMap Map => session != null ? session.map : null;

        void FixedUpdate()
        {
            if (body == null) return;
            if (online != null)
            {
                OnlineTick();
                return;
            }
            PlayerInput input = GatherInput();
            _seq++;
            input.seq = _seq;
            tick++;
            Step(input, tick);
            if (session != null) session.OnTick(tick);
            if (body.transform.position.y < killHeight)
                body.Teleport(session != null ? session.RespawnPoint() : spawnPoint);
        }

        /// <summary>한 틱: 장애물 위치 → 발판에 실림 → 이동 → 패드·넉백</summary>
        void Step(PlayerInput input, int wt)
        {
            GameMap map = Map;
            if (map != null)
            {
                map.UpdateWorld(wt);
                map.PreMove(body, wt);
            }
            body.Simulate(input, Time.fixedDeltaTime);
            if (map != null) map.PostMove(body, wt);
        }

        // ------------------------------------------------------------------ 온라인

        /// <summary>서버에 입장했을 때 (입장할 때마다 입력 번호를 1부터 다시)</summary>
        public void StartOnline(OnlineClient client, int serverTick)
        {
            online = client;
            _seq = 0;
            _hist.Clear();
            _tickOffset = serverTick;
            _offsetValid = false;
            _hasPending = false;
            tick = serverTick;
        }

        public void StopOnline()
        {
            online = null;
            _hist.Clear();
            _hasPending = false;
        }

        /// <summary>스냅샷 속 내 항목: 다음 물리 틱에서 처리 (최신 것만 의미 있음)</summary>
        public void QueueReconcile(SnapEntry e)
        {
            _pending = e;
            _hasPending = true;
        }

        int WorldTickFor(uint seq) => (int)seq + _tickOffset;

        void OnlineTick()
        {
            if (_hasPending)
            {
                _hasPending = false;
                Reconcile(_pending);
            }
            PlayerInput input = GatherInput();
            _seq++;
            input.seq = _seq;
            int wt = WorldTickFor(_seq);
            tick = wt;
            Step(input, wt);
            _hist.Add(new Hist { input = input, pos = body.transform.position, wt = wt });
            if (_hist.Count > MaxHistory) _hist.RemoveAt(0);

            int n = Mathf.Min(NetConst.InputRedundancy, _hist.Count);
            _send.Clear();
            for (int i = _hist.Count - n; i < _hist.Count; i++)
            {
                var h = _hist[i].input;
                _send.Add(new WireInput { seq = h.seq, moveX = h.moveX, moveZ = h.moveZ, flags = h.Flags });
            }
            online.SendInputs(InputCodec.Encode(_send, 0, _send.Count));
        }

        static Vector3 V(GVec3 g) => new Vector3(g.x, g.y, g.z);

        void Reconcile(SnapEntry e)
        {
            uint ack = e.ack;
            if (ack == 0) return;
            // 서버 처리 틱과 입력 번호의 차이로 장애물 시간을 맞춘다 (±2틱 흔들림은 무시)
            int sample = (int)e.ackTick - (int)ack;
            if (e.ackTick > 0 && (!_offsetValid || Mathf.Abs(sample - _tickOffset) > 2))
            {
                _tickOffset = sample;
                _offsetValid = true;
                for (int i = 0; i < _hist.Count; i++)
                {
                    var h = _hist[i];
                    h.wt = WorldTickFor(h.input.seq);
                    _hist[i] = h;
                }
            }
            while (_hist.Count > 0 && _hist[0].input.seq < ack) _hist.RemoveAt(0);
            Vector3 serverPos = V(e.pos);
            float err = float.PositiveInfinity;
            if (_hist.Count > 0 && _hist[0].input.seq == ack)
            {
                err = Vector3.Distance(_hist[0].pos, serverPos);
                _hist.RemoveAt(0);
            }
            if (err <= CorrectionEpsilon) return;

            corrections++;
            if (err > 3f) teleports++;
            else maxSmallCorrection = Mathf.Max(maxSmallCorrection, err);
            Vector3 shownBefore = body.InterpolatedPosition + body.visualOffset;
            body.SetNetState(serverPos, V(e.vel), e.air, e.stun, e.boost, e.jumpBoost, e.shield, e.mover,
                (e.flags & SnapEntry.FlagGrounded) != 0);
            for (int i = 0; i < _hist.Count; i++)
            {
                var h = _hist[i];
                Step(h.input, h.wt);
                h.pos = body.transform.position;
                _hist[i] = h;
            }
            if (err > 2f) body.SnapInterpolation();
            else
            {
                // 작은 보정은 튀지 않게: 모습만 이전 자리에서 잠깐 따라오게
                body.SnapInterpolation();
                body.visualOffset = shownBefore - body.transform.position;
                if (body.visualOffset.magnitude > 1.5f) body.visualOffset = Vector3.zero;
            }
        }

        // ------------------------------------------------------------------ 입력

        PlayerInput GatherInput()
        {
            var inp = new PlayerInput();
            Vector2 v = Vector2.ClampMagnitude(InputReader.Move() + externalMove, 1f);
            if (InputReader.WalkHeld()) v *= 0.5f;
            if (UiKit.MenuOpen) v = Vector2.zero;
            // 카메라 방향 기준 → 월드 방향
            float yaw = cam != null ? cam.yaw : 0f;
            float s = Mathf.Sin(yaw), c = Mathf.Cos(yaw);
            Vector2 world = new Vector2(v.x * c + v.y * s, -v.x * s + v.y * c);
            inp.SetMove(world);

            if (_jumpQueued)
            {
                _jumpHold = PlayerBody.JumpHoldTicks;
                _jumpQueued = false;
            }
            inp.jump = _jumpHold > 0;
            _jumpHold = Mathf.Max(_jumpHold - 1, 0);
            if (inp.jump && body.velocity.y > 2f)
                _jumpHold = 0; // 이미 뛰어올랐으면 남은 유지 입력은 버린다
            return inp;
        }
    }
}
