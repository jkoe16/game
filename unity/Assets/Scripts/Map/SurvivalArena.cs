using System.Collections.Generic;
using UnityEngine;

namespace PartyWorld
{
    /// <summary>
    /// 최후의 생존자 "무너지는 섬" (Godot scripts/gameplay/maps/survival_arena.gd 이식).
    /// 가운데 원판(끝까지 남음) + 바깥 두 줄의 타일. 30초부터 바깥 타일이, 75초부터 안쪽 타일 절반이
    /// 하나씩 흔들리다(2.5초 경고) 떨어진다. 회전 막대 2개(낮은 빨강은 점프, 높은 파랑은 점프 금지). 40초부터 돌풍.
    /// </summary>
    public class SurvivalArena : GameMap
    {
        public const float ArenaRadius = 11f;
        public const float CoreRadius = 5f;
        const float WarnSec = 2.5f;
        static readonly Color TILE_A = C(1f, 0.78f, 0.88f);
        static readonly Color TILE_B = C(0.86f, 0.78f, 1f);

        /// <summary>무너짐이 시작된 라운드 시작 틱 (0 = 무너지지 않음)</summary>
        public int crumbleStart;

        class Tile
        {
            public GameObject body; public Collider shape; public MeshRenderer mesh; public Vector3 basePos;
            public float fallAt; public bool fallen; public Material baseMat;
        }
        readonly List<Tile> _tiles = new List<Tile>();
        Material _warnA, _warnB;
        WindStreaks _wind;

        protected override void BuildMap()
        {
            mapId = "survival_arena";
            displayName = "무너지는 섬";
            killHeight = -12f;
            SetupEnvironment(C(0.55f, 0.45f, 0.9f), C(1f, 0.8f, 0.85f), new Vector3(-60, -30, 0));
            _warnA = Toon(C(1f, 0.45f, 0.45f));
            _warnB = Toon(C(1f, 0.8f, 0.5f));
            AddCylinder(new Vector3(0, -1, 0), CoreRadius, 2f, C(1f, 0.86f, 0.92f), true, 48);
            BuildRing(CoreRadius, 8f, 12, 75f, 4f, true);
            BuildRing(8f, ArenaRadius, 16, 30f, 2.6f, false);
            AddCylinder(new Vector3(0, 1.5f, 0), 0.9f, 3f, C(0.95f, 0.85f, 0.3f)); // 가운데 기둥
            AddSweeper(Vector3.zero, ArenaRadius + 0.5f, 0.5f, 55f, 0f, 5f, 2, 0.45f, C(1f, 0.4f, 0.4f));
            AddSweeper(Vector3.zero, ArenaRadius + 0.5f, 2.4f, -35f, 90f, -3f, 1, 0.45f, C(0.4f, 0.6f, 1f));

            // 관전석
            AddBox(new Vector3(0, 8, -20), new Vector3(10, 1, 5), C(0.8f, 0.8f, 0.9f));
            AddBox(new Vector3(0, 9, -17.6f), new Vector3(10, 1.2f, 0.3f), C(0.8f, 0.8f, 0.9f));
            AddLabel(new Vector3(0, 11, -20), "관전석", 64);

            for (int i = 0; i < 8; i++)
            {
                float a = Mathf.PI * 2f * i / 8f + 0.2f;
                spawnPoints.Add(new Vector3(Mathf.Sin(a) * 6.5f, 0.5f, Mathf.Cos(a) * 6.5f));
            }
            Decorate();
            _wind = NewDynamic("Wind", new Vector3(0, 1.5f, 0)).gameObject.AddComponent<WindStreaks>();
        }

        /// <summary>링 하나를 count개 타일로. 정해진 순서로 firstSec부터 gap초 간격으로 떨어진다. half면 절반만</summary>
        void BuildRing(float rIn, float rOut, int count, float firstSec, float gap, bool half)
        {
            float mid = (rIn + rOut) * 0.5f;
            float width = Mathf.PI * 2f * rOut / count * 1.04f;
            int order = 0;
            for (int k = 0; k < count; k++)
            {
                int i = (k * 7) % count; // 고정된 섞인 순서 (매 판 같음 → 익히면 유리)
                float a = Mathf.PI * 2f * (i + 0.5f) / count;
                var pos = new Vector3(Mathf.Sin(a) * mid, -1f, Mathf.Cos(a) * mid);
                bool falls = !half || k % 2 == 0;
                Color col = _tiles.Count % 2 == 0 ? TILE_A : TILE_B;
                var body = AddBox(pos, new Vector3(width, 2f, rOut - rIn), col, new Vector3(0, a * Mathf.Rad2Deg, 0), true, true, true);
                body.name = "Tile";
                _tiles.Add(new Tile
                {
                    body = body, shape = body.GetComponent<Collider>(), mesh = body.GetComponentInChildren<MeshRenderer>(), basePos = pos,
                    fallAt = falls ? firstSec + gap * order : float.PositiveInfinity, baseMat = Toon(col),
                });
                if (falls) order++;
            }
        }

        public override void UpdateWorld(int tick)
        {
            float t = crumbleStart > 0 ? (tick - crumbleStart) / 60f : float.NegativeInfinity;
            foreach (var tl in _tiles)
            {
                bool fallen = t >= tl.fallAt;
                if (fallen != tl.fallen)
                {
                    tl.fallen = fallen;
                    tl.shape.enabled = !fallen;
                }
                var tr = tl.body.transform;
                if (fallen)
                {
                    float ft = t - tl.fallAt;
                    tr.localPosition = tl.basePos + new Vector3(0, -6f * ft * ft, 0);
                    tl.mesh.enabled = ft < 3f;
                }
                else if (t >= tl.fallAt - WarnSec)
                {
                    // 경고: 흔들리며 빨갛게
                    float w = (t - (tl.fallAt - WarnSec)) / WarnSec;
                    tr.localPosition = tl.basePos + new Vector3(Mathf.Sin(t * 40f) * 0.06f * w, 0, Mathf.Cos(t * 33f) * 0.06f * w);
                    tl.mesh.enabled = true;
                    tl.mesh.sharedMaterial = (int)(t * 6f) % 2 == 0 ? _warnA : _warnB;
                }
                else
                {
                    tr.localPosition = tl.basePos;
                    tl.mesh.enabled = true;
                    tl.mesh.sharedMaterial = tl.baseMat;
                }
            }
            if (_wind != null) _wind.gust = GustAt(tick);
            base.UpdateWorld(tick); // 마지막에 충돌체 위치 반영(SyncTransforms)
        }

        // ---------------------------------------------------------------- 밀어내는 바람
        // 40초부터 18초마다 3초 동안 한 방향으로 돌풍 (초속 2.6m, 걸어서 버틸 수 있음). 방향은 매번 바뀐다
        const float GustFirst = 40f, GustEvery = 18f, GustLen = 3f, GustSpeed = 2.6f;

        public Vector3 GustAt(int tick)
        {
            if (crumbleStart <= 0) return Vector3.zero;
            float t = (tick - crumbleStart) / 60f - GustFirst;
            if (t < 0f) return Vector3.zero;
            int k = (int)(t / GustEvery);
            if (t - k * GustEvery >= GustLen) return Vector3.zero;
            float a = k * 2.4f + 0.6f;
            return new Vector3(Mathf.Cos(a), 0, Mathf.Sin(a)) * GustSpeed;
        }

        /// <summary>다음 돌풍이 시작하는 틱 (안내용)</summary>
        public int NextGustTick(int tick)
        {
            if (crumbleStart <= 0) return -1;
            float t = (tick - crumbleStart) / 60f - GustFirst;
            int k = t < 0f ? 0 : (int)(t / GustEvery) + 1;
            return crumbleStart + (int)((GustFirst + k * GustEvery) * 60f);
        }

        public override void PreMove(PlayerBody body, int tick)
        {
            base.PreMove(body, tick);
            Vector3 w = GustAt(tick);
            if (w != Vector3.zero && !body.frozen) body.Carry(w / 60f);
        }

        public Vector3 SpectatorPoint => new Vector3(0, 9, -20.5f);

        /// <summary>시각 장식: 가장자리 띠, 기둥 줄무늬, 떠 있는 등불, 관전석 꾸밈</summary>
        void Decorate()
        {
            AddMesh(MeshFactory.Torus(CoreRadius - 0.25f, CoreRadius + 0.05f, 48, 6), Vector3.zero, C(1f, 0.95f, 0.7f), Vector3.zero, new Vector3(1, 0.06f, 1));
            for (int i = 0; i < 3; i++)
                AddMesh(MeshFactory.Torus(0.86f, 1.06f, 24, 8), new Vector3(0, 0.6f + i * 0.95f, 0), i % 2 == 0 ? C(1f, 0.45f, 0.5f) : Color.white, Vector3.zero, Vector3.one);
            AddMesh(Sph(0.95f, 18), new Vector3(0, 3f, 0), C(1f, 0.9f, 0.4f), Vector3.zero, new Vector3(1, 0.5f, 1));
            for (int i = 0; i < 10; i++)
            {
                float a = Mathf.PI * 2f * i / 10f;
                var p = new Vector3(Mathf.Sin(a) * 15f, 3f + (i % 2) * 1.5f, Mathf.Cos(a) * 15f);
                AddMesh(Sph(0.42f, 12), p, Glow(i % 2 == 0 ? C(1f, 0.8f, 0.55f) : C(0.85f, 0.7f, 1f), 1.6f), Vector3.zero, Vector3.one);
                AddMesh(Cyl(0.18f, 0.28f, 0.16f, 10), p + new Vector3(0, -0.45f, 0), C(0.6f, 0.45f, 0.7f));
            }
            AddEdgeTrim(new Vector3(0, 8, -20), new Vector3(10, 1, 5), C(1f, 0.6f, 0.75f));
            foreach (float x in new[] { -4f, -2f, 0f, 2f, 4f })
                AddMesh(MeshFactory.Box(), new Vector3(x, 8.75f, -21.2f), (int)x % 4 == 0 ? C(0.55f, 0.75f, 1f) : C(1f, 0.7f, 0.8f), Vector3.zero, new Vector3(1.4f, 0.5f, 1.2f));
            AddFlag(new Vector3(-5.2f, 8.5f, -22.2f), C(1f, 0.55f, 0.7f), 0f, 2.6f);
            AddFlag(new Vector3(5.2f, 8.5f, -22.2f), C(0.55f, 0.75f, 1f), 180f, 2.6f);
        }
    }

    /// <summary>돌풍이 부는 동안 흰 줄이 바람 방향으로 날아간다 (시각 전용)</summary>
    public class WindStreaks : MonoBehaviour
    {
        public Vector3 gust;
        const int Count = 40;
        readonly Transform[] _s = new Transform[Count];
        readonly Vector3[] _p = new Vector3[Count];
        readonly float[] _v = new float[Count];

        void Start()
        {
            Mesh m = MeshFactory.Cylinder(0.03f, 0.03f, 1.4f, 4);
            Material mat = GameMap.Glow(Color.white, 1f);
            for (int i = 0; i < Count; i++)
            {
                var go = new GameObject("w");
                go.transform.SetParent(transform, false);
                go.AddComponent<MeshFilter>().sharedMesh = m;
                var mr = go.AddComponent<MeshRenderer>();
                mr.sharedMaterial = mat;
                mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
                _s[i] = go.transform;
                _p[i] = new Vector3(Random.Range(-12f, 12f), Random.Range(-2f, 2f), Random.Range(-12f, 12f));
                _v[i] = Random.Range(9f, 13f);
                go.SetActive(false);
            }
        }

        void Update()
        {
            bool on = gust != Vector3.zero;
            if (_s[0] == null) return;
            Vector3 dir = on ? gust.normalized : Vector3.forward;
            Quaternion rot = Quaternion.FromToRotation(Vector3.up, dir);
            for (int i = 0; i < Count; i++)
            {
                if (_s[i].gameObject.activeSelf != on) _s[i].gameObject.SetActive(on);
                if (!on) continue;
                _p[i] += dir * _v[i] * Time.deltaTime;
                if (Mathf.Abs(_p[i].x) > 14f || Mathf.Abs(_p[i].z) > 14f)
                    _p[i] = -dir * 13f + Vector3.Cross(dir, Vector3.up) * Random.Range(-12f, 12f) + Vector3.up * Random.Range(-2f, 2f);
                _s[i].localPosition = _p[i];
                _s[i].localRotation = rot;
            }
        }
    }
}
