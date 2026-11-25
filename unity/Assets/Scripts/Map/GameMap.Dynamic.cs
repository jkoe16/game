using System.Collections.Generic;
using UnityEngine;

namespace PartyWorld
{
    /// <summary>
    /// 움직이는 맵 요소 (Godot game_map.gd 의 "동적 월드 API" 이식).
    /// 모두 틱 번호(60Hz)로 위치를 계산하므로 서버와 클라이언트가 따로 계산해도 같은 결과가 나온다.
    /// 한 틱 순서: UpdateWorld(tick) → PreMove(몸, tick) → PlayerBody.Simulate → PostMove(몸, tick)
    /// </summary>
    public abstract partial class GameMap
    {
        public const float PlayerRadius = 0.45f;
        public const float PlayerHeight = 1.6f;
        /// <summary>가속 회전 막대의 최고 각속도 (라디안/초 ≈ 160°/s)</summary>
        public const float MaxSweepOmega = 2.8f;

        /// <summary>가속 막대·후반 장애물의 기준 틱 (라운드 시작 틱)</summary>
        public int roundStartTick;

        static float PosMod(float a, float b) { float r = a % b; return r < 0 ? r + b : r; }

        // ================================================================== 회전 막대

        public class Sweeper
        {
            public Vector3 center; public float radius, y, omega, phase, accel, half; public int arms;
            public Transform pivot;
        }
        public readonly List<Sweeper> sweepers = new List<Sweeper>();

        /// <summary>회전 막대. arms=2면 양쪽으로 뻗은 막대. omega/accel 단위: 도/초, 도/초²</summary>
        public void AddSweeper(Vector3 center, float radius, float barY, float omegaDeg, float phaseDeg = 0f, float accelDeg = 0f,
            int arms = 1, float thickness = 0.4f, Color? colorOpt = null, bool hammer = false)
        {
            Color color = colorOpt ?? C(1f, 0.45f, 0.4f);
            var pivot = NewDynamic("Sweeper", new Vector3(center.x, barY, center.z));
            // 사탕 막대: 둥근 막대 + 흰 줄무늬 + 끝 구슬 (판정은 SweeperHit 계산식이라 모양과 무관)
            float length = radius * (arms == 2 ? 2f : 1f);
            float z0 = arms == 2 ? 0f : radius * 0.5f;
            float r = thickness * 0.55f;
            AddMesh(Cyl(r, r, length, 14), new Vector3(0, 0, z0), Toon(color), new Vector3(90, 0, 0), Vector3.one, pivot);
            int n = (int)(length / 0.9f);
            for (int i = 0; i < n; i++)
                AddMesh(Cyl(r * 1.06f, r * 1.06f, 0.28f, 14), new Vector3(0, 0, z0 - length * 0.5f + (i + 0.5f) * length / n), Toon(Color.white), new Vector3(90, 0, 0), Vector3.one, pivot);
            foreach (float endZ in arms == 2 ? new[] { -radius, radius } : new[] { radius })
            {
                if (hammer) // 회전 망치 머리
                    AddMesh(Cyl(0.42f, 0.42f, 1.1f, 16), new Vector3(0, 0, endZ), Toon(Darken(color, 0.1f)), Vector3.zero, Vector3.one, pivot);
                else
                    AddMesh(Sph(r * 1.7f, 14), new Vector3(0, 0, endZ), Toon(Lighten(color, 0.25f)), Vector3.zero, Vector3.one, pivot);
            }
            AddMesh(Cyl(0.5f, 0.65f, barY - center.y + 0.4f, 18), new Vector3(0, -(barY - center.y) * 0.5f + 0.2f, 0), Toon(C(0.95f, 0.85f, 0.3f)), Vector3.zero, Vector3.one, pivot);
            AddMesh(Sph(0.62f, 16), new Vector3(0, 0.35f, 0), Toon(C(1f, 0.6f, 0.7f)), Vector3.zero, Vector3.one, pivot);
            sweepers.Add(new Sweeper
            {
                center = center, radius = radius, y = barY, omega = omegaDeg * Mathf.Deg2Rad, phase = phaseDeg * Mathf.Deg2Rad,
                accel = accelDeg * Mathf.Deg2Rad, arms = arms, half = thickness * 0.5f, pivot = pivot,
            });
        }

        public float SweeperAngle(Sweeper s, int tick)
        {
            if (s.accel != 0f)
            {
                // 가속하다가 최고 속도에서 멈춘다 → 끝없이 빨라져 피할 수 없게 되는 일 방지
                float t = Mathf.Max(0f, tick - roundStartTick) / 60f;
                float cap = MaxSweepOmega * Mathf.Sign(s.accel);
                float tCap = Mathf.Max(0f, (cap - s.omega) / s.accel);
                if (t <= tCap) return s.phase + s.omega * t + 0.5f * s.accel * t * t;
                return s.phase + s.omega * tCap + 0.5f * s.accel * tCap * tCap + cap * (t - tCap);
            }
            return s.phase + s.omega * tick / 60f;
        }

        /// <summary>회전 막대 판정. 맞으면 넉백 벡터, 아니면 zero</summary>
        public Vector3 SweeperHit(Sweeper s, Vector3 p, int tick)
        {
            if (p.y > s.y + s.half || p.y + PlayerHeight < s.y - s.half) return Vector3.zero;
            var r = new Vector2(p.x - s.center.x, p.z - s.center.z);
            if (r.magnitude > s.radius + PlayerRadius) return Vector3.zero;
            float baseA = SweeperAngle(s, tick);
            for (int k = 0; k < s.arms; k++)
            {
                float a = baseA + Mathf.PI * 2f * k / s.arms;
                var d = new Vector2(Mathf.Sin(a), Mathf.Cos(a));
                float along = Vector2.Dot(r, d);
                float perp = Mathf.Abs(r.x * d.y - r.y * d.x);
                if (along >= -PlayerRadius && along <= s.radius && perp <= s.half + PlayerRadius)
                {
                    var tangent = new Vector2(Mathf.Cos(a), -Mathf.Sin(a)) * Mathf.Sign(s.omega != 0f ? s.omega : 1f);
                    var away = (d * 0.4f + tangent).normalized;
                    return new Vector3(away.x * 9f, 7f, away.y * 9f);
                }
            }
            return Vector3.zero;
        }

        // ================================================================== 왕복 이동 발판

        public class Mover { public Transform node; public Vector3 a, b; public float period, phase; }
        public readonly List<Mover> movers = new List<Mover>();

        /// <summary>발판 충돌체에 붙여 둔다 (밟은 발판 찾기용)</summary>
        public class MoverTag : MonoBehaviour { public int index; }

        /// <summary>왕복 이동 발판 (a ↔ b, 코사인 감속). 반환: 발판 번호</summary>
        public int AddMover(Vector3 a, Vector3 b, Vector3 size, float periodSec, float phase = 0f, Color? colorOpt = null)
        {
            var root = AddBox(a, size, colorOpt ?? C(0.55f, 0.75f, 1f), Vector3.zero, true, true, true);
            root.name = "Mover";
            root.AddComponent<MoverTag>().index = movers.Count;
            movers.Add(new Mover { node = root.transform, a = a, b = b, period = periodSec * 60f, phase = phase });
            return movers.Count - 1;
        }

        public Vector3 MoverPos(int i, int tick)
        {
            var m = movers[i];
            float u = 0.5f - 0.5f * Mathf.Cos(Mathf.PI * 2f * (tick / m.period + m.phase));
            return Vector3.Lerp(m.a, m.b, u);
        }

        // ================================================================== 부스트 / 점프 패드

        public class Pad { public string kind; public Vector3 center, half; public float power; }
        public readonly List<Pad> pads = new List<Pad>();

        /// <summary>kind: "boost"(가속) | "jump"(높이 점프). half: 영역 반크기</summary>
        public void AddPad(string kind, Vector3 center, Vector3 half, float power = 15f)
        {
            pads.Add(new Pad { kind = kind, center = center, half = half, power = power });
            Color c = kind == "boost" ? C(1f, 0.82f, 0.25f) : C(0.35f, 0.95f, 0.6f);
            AddMesh(MeshFactory.Box(), center + new Vector3(0, 0.03f, 0), C(0.98f, 0.96f, 1f), Vector3.zero, new Vector3(half.x * 2f + 0.3f, 0.08f, half.z * 2f + 0.3f));
            AddMesh(MeshFactory.Box(), center + new Vector3(0, 0.05f, 0), Glow(c, 1.1f), Vector3.zero, new Vector3(half.x * 2f, 0.1f, half.z * 2f));
            // 화살표 줄무늬 (밝은 막대 3개)
            bool alongZ = half.z >= half.x;
            Vector3 stripe = alongZ ? new Vector3(half.x * 1.6f, 0.04f, 0.22f) : new Vector3(0.22f, 0.04f, half.z * 1.6f);
            for (int k = 0; k < 3; k++)
            {
                float o = (k - 1) * Mathf.Min(half.z, alongZ ? half.z : half.x) * 0.55f;
                AddMesh(MeshFactory.Box(), center + (alongZ ? new Vector3(0, 0.11f, o) : new Vector3(o, 0.11f, 0)), Glow(Color.white, 1f), Vector3.zero, stripe);
            }
            AddLabel(center + new Vector3(0, 1.3f, 0), kind == "boost" ? "부스트" : "점프!", 44, Lighten(c, 0.3f));
        }

        // ================================================================== 여닫는 벽

        public readonly List<GameObject> gates = new List<GameObject>();

        public int AddGate(Vector3 pos, Vector3 size, Color? colorOpt = null)
        {
            var g = AddBox(pos, size, colorOpt ?? C(0.75f, 0.55f, 0.95f), Vector3.zero, true, true, true);
            gates.Add(g);
            return gates.Count - 1;
        }

        public void SetGateOpen(int i, bool open)
        {
            if (i < 0 || i >= gates.Count) return;
            gates[i].SetActive(!open);
        }

        // ================================================================== 추가 장애물

        /// <summary>시간 제한 장애물: fromSec > 0 이면 라운드 시작 후 fromSec초부터 나타난다</summary>
        public bool HazardActive(float fromSec, int tick)
        {
            if (fromSec <= 0f) return true;
            return roundStartTick > 0 && tick - roundStartTick >= (int)(fromSec * 60f);
        }

        public class Pusher { public Transform node; public Vector3 rest, size, dir; public float travel, period, phase, from; }
        public readonly List<Pusher> pushers = new List<Pusher>();

        /// <summary>밀어내는 벽. 쉼 → 0.45초 전 흔들림 경고 → 빠르게 튀어나옴 → 잠깐 멈춤 → 천천히 들어감</summary>
        public void AddPusher(Vector3 rest, Vector3 size, Vector3 dir, float travel, float periodSec, float phase = 0f, float fromSec = 0f, Color? colorOpt = null)
        {
            Color color = colorOpt ?? C(1f, 0.5f, 0.35f);
            var node = NewDynamic("Pusher", rest);
            AddMesh(MeshFactory.Box(), Vector3.zero, Toon(color), Vector3.zero, size, node);
            bool alongX = Mathf.Abs(dir.x) > 0.5f;
            var face = new Vector3(Mathf.Abs(dir.x) < 0.5f ? size.x * 0.8f : 0.25f, size.y * 0.8f, Mathf.Abs(dir.z) < 0.5f ? size.z * 0.8f : 0.25f);
            AddMesh(MeshFactory.Box(), dir * ((alongX ? size.x : size.z) * 0.5f + 0.1f), Toon(C(1f, 0.95f, 0.9f)), Vector3.zero, face, node);
            // 벽 속 하우징 (고정)
            AddMesh(MeshFactory.Box(), rest - dir * ((alongX ? size.x : size.z) * 0.6f), Darken(color, 0.45f), Vector3.zero, size + new Vector3(0.3f, 0.3f, 0.3f));
            pushers.Add(new Pusher { node = node, rest = rest, size = size, dir = dir.normalized, travel = travel, period = periodSec * 60f, phase = phase, from = fromSec });
        }

        /// <summary>0(들어감) ~ 1(다 튀어나옴)</summary>
        public float PusherOut(Pusher s, int tick)
        {
            float u = PosMod(tick / s.period + s.phase, 1f);
            if (u < 0.55f) return 0f;
            if (u < 0.62f) return (u - 0.55f) / 0.07f;
            if (u < 0.78f) return 1f;
            return 1f - (u - 0.78f) / 0.22f;
        }

        public Vector3 PusherHit(Pusher s, Vector3 p, int tick)
        {
            if (!HazardActive(s.from, tick)) return Vector3.zero;
            float u = PosMod(tick / s.period + s.phase, 1f);
            float o = PusherOut(s, tick);
            if (o <= 0.05f || u >= 0.8f) return Vector3.zero; // 천천히 들어가는 동안은 안전
            Vector3 c = s.rest + s.dir * s.travel * o;
            Vector3 h = s.size * 0.5f;
            if (Mathf.Abs(p.x - c.x) > h.x + PlayerRadius || Mathf.Abs(p.z - c.z) > h.z + PlayerRadius) return Vector3.zero;
            if (p.y > c.y + h.y || p.y + PlayerHeight < c.y - h.y) return Vector3.zero;
            return new Vector3(s.dir.x * 11f, 6.5f, s.dir.z * 11f);
        }

        public class Roller { public Transform node; public Vector3 a, b; public float r, period, phase, from; }
        public readonly List<Roller> rollers = new List<Roller>();

        /// <summary>굴러오는 공: a → b 로 periodSec 동안 굴러가고, 끝나면 a에서 다시 나온다</summary>
        public void AddRoller(Vector3 a, Vector3 b, float radius, float periodSec, float phase = 0f, float fromSec = 0f, Color? colorOpt = null)
        {
            var node = NewDynamic("Roller", a);
            AddMesh(Sph(radius, 18), Vector3.zero, Toon(colorOpt ?? C(0.95f, 0.35f, 0.55f)), Vector3.zero, Vector3.one, node);
            AddMesh(Cyl(radius * 1.02f, radius * 1.02f, radius * 0.45f, 18), Vector3.zero, Toon(Color.white), new Vector3(0, 0, 90), Vector3.one, node);
            rollers.Add(new Roller { node = node, a = a, b = b, r = radius, period = periodSec * 60f, phase = phase, from = fromSec });
        }

        public Vector3 RollerPos(Roller s, int tick) => Vector3.Lerp(s.a, s.b, PosMod(tick / s.period + s.phase, 1f));

        public Vector3 RollerHit(Roller s, Vector3 p, int tick)
        {
            if (!HazardActive(s.from, tick)) return Vector3.zero;
            Vector3 c = RollerPos(s, tick);
            if (p.y > c.y + s.r || p.y + PlayerHeight < c.y - s.r) return Vector3.zero;
            var rel = new Vector2(p.x - c.x, p.z - c.z);
            if (rel.magnitude > s.r + PlayerRadius) return Vector3.zero;
            var roll = new Vector2(s.b.x - s.a.x, s.b.z - s.a.z).normalized;
            Vector2 side = rel - roll * Vector2.Dot(rel, roll);
            Vector2 away = side.magnitude > 0.01f ? (roll + side.normalized * 0.5f).normalized : roll;
            return new Vector3(away.x * 9f, 7.5f, away.y * 9f);
        }

        public class Blinker { public GameObject body; public Collider shape; public MeshRenderer mesh; public Vector3 size; public Color color; public Material baseMat, warnMat; public float period, phase, on; public bool solid = true; }
        public readonly List<Blinker> blinkers = new List<Blinker>();

        /// <summary>사라졌다 나타나는 발판: 주기 중 앞쪽 onFrac 동안 단단하고, 사라지기 0.9초 전부터 깜빡인다</summary>
        public void AddBlinker(Vector3 pos, Vector3 size, float periodSec, float phase = 0f, float onFrac = 0.62f, Color? colorOpt = null)
        {
            Color color = colorOpt ?? C(0.6f, 0.9f, 1f);
            var body = AddBox(pos, size, color, Vector3.zero, true, true, true);
            body.name = "Blinker";
            blinkers.Add(new Blinker
            {
                body = body, shape = body.GetComponent<Collider>(), mesh = body.GetComponentInChildren<MeshRenderer>(),
                size = size, color = color, baseMat = Toon(color), warnMat = Toon(C(1f, 0.5f, 0.45f)), period = periodSec * 60f, phase = phase, on = onFrac,
            });
        }

        public bool BlinkerSolid(Blinker s, int tick) => PosMod(tick / s.period + s.phase, 1f) < s.on;

        void UpdateHazards(int tick)
        {
            foreach (var s in pushers)
            {
                bool act = HazardActive(s.from, tick);
                s.node.gameObject.SetActive(act);
                if (!act) continue;
                float u = PosMod(tick / s.period + s.phase, 1f);
                Vector3 shake = Vector3.zero;
                if (u > 0.42f && u < 0.55f) // 튀어나오기 직전 덜덜 떨림 (경고)
                    shake = new Vector3(Mathf.Sin(tick * 2.1f), 0, Mathf.Cos(tick * 1.7f)) * 0.06f;
                s.node.localPosition = s.rest + s.dir * s.travel * PusherOut(s, tick) + shake;
            }
            foreach (var s in rollers)
            {
                bool act = HazardActive(s.from, tick);
                s.node.gameObject.SetActive(act);
                if (!act) continue;
                Vector3 c = RollerPos(s, tick);
                s.node.localPosition = c;
                Vector3 roll = (s.b - s.a).normalized;
                float dist = Vector3.Distance(s.a, c) / s.r;
                Vector3 axis = Mathf.Abs(roll.y) < 0.9f ? Vector3.Cross(Vector3.up, roll).normalized : Vector3.right;
                s.node.localRotation = Quaternion.AngleAxis(dist * Mathf.Rad2Deg, axis);
            }
            foreach (var s in blinkers)
            {
                bool solid = BlinkerSolid(s, tick);
                if (solid != s.solid)
                {
                    s.solid = solid;
                    s.shape.enabled = solid;
                    s.mesh.enabled = solid;
                }
                float u = PosMod(tick / s.period + s.phase, 1f);
                bool warn = solid && (s.on - u) * s.period < 54f; // 사라지기 0.9초 전
                s.mesh.sharedMaterial = warn && (tick / 6) % 2 == 0 ? s.warnMat : s.baseMat;
            }
        }

        // ================================================================== 틱 처리

        /// <summary>틱 번호에 맞춰 움직이는 것들의 위치를 정한다 (시뮬레이션 직전)</summary>
        public virtual void UpdateWorld(int tick)
        {
            for (int i = 0; i < movers.Count; i++) movers[i].node.position = MoverPos(i, tick);
            foreach (var s in sweepers) s.pivot.localRotation = Quaternion.Euler(0, SweeperAngle(s, tick) * Mathf.Rad2Deg, 0);
            UpdateHazards(tick);
            Physics.SyncTransforms(); // 옮긴 충돌체를 이번 틱 이동 판정에 바로 반영
        }

        /// <summary>이동 직전: 이동 발판 위에 서 있으면 발판 이동량만큼 함께 이동</summary>
        public virtual void PreMove(PlayerBody body, int tick)
        {
            if (body.floorMover >= 0 && body.floorMover < movers.Count)
            {
                Vector3 d = MoverPos(body.floorMover, tick) - MoverPos(body.floorMover, tick - 1);
                body.Carry(d);
            }
        }

        /// <summary>이동 직후: 발판 탑승 판정, 패드, 회전 막대·장애물 넉백</summary>
        public void PostMove(PlayerBody body, int tick)
        {
            body.floorMover = -1;
            Vector3 p = body.transform.position;
            if (body.IsOnFloor && movers.Count > 0)
            {
                // 발밑을 짧게 검사해 발판을 찾는다
                if (Physics.SphereCast(p + Vector3.up * 0.5f, 0.3f, Vector3.down, out RaycastHit hit, 0.4f, ~(1 << PartyLayers.Player), QueryTriggerInteraction.Ignore)
                    && hit.normal.y > 0.6f)
                {
                    var tag = hit.collider.GetComponent<MoverTag>();
                    if (tag != null) body.floorMover = tag.index;
                }
            }
            foreach (var pad in pads)
            {
                Vector3 d = p - pad.center;
                if (Mathf.Abs(d.x) <= pad.half.x && Mathf.Abs(d.z) <= pad.half.z && Mathf.Abs(d.y) <= pad.half.y + 0.3f)
                {
                    if (pad.kind == "boost") body.boostTime = 1.5f;
                    else if (body.velocity.y <= 1f)
                    {
                        body.velocity.y = pad.power;
                        body.airTime = PlayerBody.CoyoteTime + 0.001f;
                    }
                }
            }
            if (body.stunTime > 0f) return;
            foreach (var s in sweepers)
            {
                Vector3 h = SweeperHit(s, p, tick);
                if (h != Vector3.zero) { body.Knock(h, 0.7f); return; }
            }
            foreach (var s in pushers)
            {
                Vector3 h = PusherHit(s, p, tick);
                if (h != Vector3.zero) { body.Knock(h, 0.7f); return; }
            }
            foreach (var s in rollers)
            {
                Vector3 h = RollerHit(s, p, tick);
                if (h != Vector3.zero) { body.Knock(h, 0.8f); return; }
            }
        }

        // ================================================================== 모드 연동 (하위 맵에서 재정의)

        public virtual Vector3 GetStartPoint(int index) => GetSpawnPoint(index);
    }
}
