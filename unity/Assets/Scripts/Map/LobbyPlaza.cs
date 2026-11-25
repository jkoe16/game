using System.Collections.Generic;
using UnityEngine;

namespace PartyWorld
{
    /// <summary>
    /// 메인 로비 "하늘 위의 광장" (Godot scripts/gameplay/maps/lobby_plaza.gd 이식).
    /// 충돌 레이아웃(바닥·분수·경사로·계단·포털 기둥·나무 줄기·벤치)은 서버와 같아야 하므로 숫자를 바꾸지 않는다.
    /// </summary>
    public class LobbyPlaza : GameMap
    {
        static readonly Color GRASS = C(0.46f, 0.79f, 0.42f);
        static readonly Color GRASS_EDGE = C(0.36f, 0.66f, 0.38f);
        static readonly Color STONE = C(0.92f, 0.85f, 0.78f);
        static readonly Color PATH = C(0.97f, 0.8f, 0.64f);
        static readonly Color ROCK = C(0.72f, 0.6f, 0.58f);
        static readonly Color WOOD = C(0.78f, 0.55f, 0.4f);

        public static readonly (string name, Color color, string mode)[] ModePortals =
        {
            ("장애물 레이스", C(1f, 0.5f, 0.45f), "obstacle_race"),
            ("최후의 생존자", C(0.62f, 0.52f, 1f), "survival"),
            ("레이싱", C(1f, 0.78f, 0.25f), "racing"),
            ("협동 미션", C(0.3f, 0.85f, 0.72f), "coop"),
            ("보물 수집", C(1f, 0.52f, 0.82f), "party"),
        };

        public struct Portal { public string mode; public Vector3 center; public float radius; }
        /// <summary>포털 판정 영역 (로비 모드가 사용)</summary>
        public readonly List<Portal> portals = new List<Portal>();

        static float Deg(float d) => d * Mathf.Deg2Rad;

        protected override void BuildMap()
        {
            mapId = "lobby_plaza";
            displayName = "하늘 위의 광장";
            killHeight = -25f;
            autoUnderside = false; // 섬 아래는 직접 꾸민다
            SetupEnvironment(C(0.38f, 0.62f, 0.98f), C(0.93f, 0.9f, 1f), new Vector3(-48, 35, 0));

            // ------------------------------------------------ 섬 본체 (충돌)
            AddCylinder(new Vector3(0, -1, 0), 28f, 2f, GRASS, true, 96);
            AddCylinder(new Vector3(0, -4.5f, 0), 25f, 5f, ROCK, true, 48);
            AddMesh(Cyl(28.35f, 28.1f, 0.9f, 96), new Vector3(0, -1.55f, 0), GRASS_EDGE);
            AddIslandUnderside(new Vector3(0, -7f, 0), 25f, 14f, ROCK);

            // ------------------------------------------------ 길 (바닥 위 얇게)
            AddMesh(Cyl(9f, 9f, 0.04f, 72), new Vector3(0, 0.02f, 0), PATH);
            AddMesh(Cyl(7.6f, 7.6f, 0.05f, 72), new Vector3(0, 0.03f, 0), GRASS);
            AddFlowers(Vector3.zero, 7.2f, 70, 3);
            for (int i = 0; i < ModePortals.Length; i++)
            {
                float ang = Deg(-60f + 30f * i);
                var mid = new Vector3(Mathf.Sin(ang), 0, Mathf.Cos(ang)) * 13.5f;
                AddMesh(MeshFactory.Box(), mid + new Vector3(0, 0.025f, 0), PATH, new Vector3(0, ang * Mathf.Rad2Deg, 0), new Vector3(2.4f, 0.04f, 9f));
            }

            // ------------------------------------------------ 중앙 분수
            AddCylinder(new Vector3(0, 0.5f, 0), 3.2f, 1f, STONE);
            AddCylinder(new Vector3(0, 1.8f, 0), 0.45f, 2.6f, STONE);
            AddMesh(Cyl(3.35f, 3.35f, 0.18f, 48), new Vector3(0, 1f, 0), Darken(STONE, 0.04f));
            var water = Water(C(0.55f, 0.85f, 1f, 0.85f));
            AddMesh(Cyl(2.95f, 2.95f, 0.06f, 48), new Vector3(0, 1.04f, 0), water, Vector3.zero, Vector3.one);
            AddMesh(Cyl(1.4f, 0.6f, 0.5f, 32), new Vector3(0, 3.1f, 0), STONE);
            AddMesh(Cyl(1.25f, 1.25f, 0.05f, 32), new Vector3(0, 3.33f, 0), water, Vector3.zero, Vector3.one);
            AddBobbing(Sph(0.55f, 18), new Vector3(0, 3.75f, 0), Glow(C(0.75f, 0.93f, 1f), 0.9f), new Vector3(1, 0.75f, 1), 0.12f, 2.2f, 0f);
            for (int i = 0; i < 8; i++) // 물줄기 방울
            {
                float a = Mathf.PI * 2f * i / 8f;
                AddBobbing(Sph(0.14f, 8), new Vector3(Mathf.Cos(a) * 1.9f, 1.9f, Mathf.Sin(a) * 1.9f), Glow(C(0.8f, 0.95f, 1f), 0.8f), Vector3.one, 0.35f, 3f, i * 0.8f);
            }

            // ------------------------------------------------ 스폰 지점: 분수 주변 링
            for (int i = 0; i < 12; i++)
            {
                float ang = Mathf.PI * 2f * i / 12f;
                spawnPoints.Add(new Vector3(Mathf.Sin(ang) * 6f, 0.5f, Mathf.Cos(ang) * 6f));
            }

            // ------------------------------------------------ 경사로(20°) → 전망대
            AddBox(new Vector3(12, 1.6f, -8), new Vector3(4, 0.5f, 10), STONE, new Vector3(20, 0, 0));
            AddBox(new Vector3(12, 2.95f, -15.7f), new Vector3(6, 1f, 6), STONE);
            AddLabel(new Vector3(12, 5.6f, -15.7f), "전망대", 72, C(1f, 0.96f, 0.8f));
            foreach (float x in new[] { -2.8f, 2.8f })
                foreach (float z in new[] { -2.8f, 2.8f })
                    AddMesh(Cyl(0.18f, 0.22f, 0.9f, 10), new Vector3(12 + x, 3.9f, -15.7f + z), WOOD);
            AddFlowers(new Vector3(12, 3.45f, -15.7f), 1.6f, 18, 7);
            AddLamp(new Vector3(9.6f, 0, -2.8f));
            AddLamp(new Vector3(14.4f, 0, -2.8f));

            // ------------------------------------------------ 계단 (단 높이 0.2m)
            for (int i = 0; i < 8; i++)
            {
                float h = 0.2f * (i + 1);
                AddBox(new Vector3(-12, h * 0.5f, -6 - 0.8f * i), new Vector3(4, h, 0.8f), Darken(STONE, 0.03f * (i % 2)));
            }
            AddBox(new Vector3(-12, 0.8f, -14), new Vector3(4, 1.6f, 2.4f), STONE);
            AddBush(new Vector3(-14.8f, 0, -9f), 1f);
            AddBush(new Vector3(-9.2f, 0, -9.5f), 0.9f, C(0.5f, 0.8f, 0.45f));
            AddTree(new Vector3(-12, 1.6f, -14.6f), 2, 0.6f, false);

            // ------------------------------------------------ 게임 모드 포털
            for (int i = 0; i < ModePortals.Length; i++)
            {
                float ang = Deg(-60f + 30f * i);
                var center = new Vector3(Mathf.Sin(ang) * 19f, 0, Mathf.Cos(ang) * 19f);
                Color c = ModePortals[i].color;
                var side = new Vector3(Mathf.Cos(ang), 0, -Mathf.Sin(ang)) * 2.2f;
                // 충돌용 기둥 (모습은 아래 둥근 아치가 대신함)
                AddBox(center + side + new Vector3(0, 1.75f, 0), new Vector3(0.5f, 3.5f, 0.5f), c, new Vector3(0, ang * Mathf.Rad2Deg, 0), true, false);
                AddBox(center - side + new Vector3(0, 1.75f, 0), new Vector3(0.5f, 3.5f, 0.5f), c, new Vector3(0, ang * Mathf.Rad2Deg, 0), true, false);
                BuildPortalVisual(center, ang, c);
                AddLabel(center + new Vector3(0, 5.6f, 0), ModePortals[i].name, 84, Lighten(c, 0.55f));
                AddLabel(center + new Vector3(0, 4.85f, 0), "올라서면 입장", 44, C(1, 1, 1, 0.9f));
                portals.Add(new Portal { mode = ModePortals[i].mode, center = center, radius = 2f });
            }

            // ------------------------------------------------ 나무 (줄기 충돌) & 벤치
            Vector3[] trees = { new Vector3(18, 0, 6), new Vector3(-19, 0, 2), new Vector3(5, 0, -21), new Vector3(-5, 0, -22), new Vector3(22, 0, -6) };
            int[] treeStyles = { 0, 2, 1, 0, 2 };
            for (int i = 0; i < trees.Length; i++)
                AddTree(trees[i], treeStyles[i], 1f, true);
            foreach (float angDeg in new[] { 45f, 135f, 225f, 315f })
            {
                float a = Deg(angDeg);
                var bp = new Vector3(Mathf.Sin(a) * 9f, 0.25f, Mathf.Cos(a) * 9f);
                AddBox(bp, new Vector3(2.4f, 0.5f, 0.7f), WOOD, new Vector3(0, angDeg, 0), true, false);
                var bench = NewDecorGroup("Bench", bp, new Vector3(0, angDeg, 0));
                AddMesh(MeshFactory.Box(), new Vector3(0, 0.12f, 0), WOOD, Vector3.zero, new Vector3(2.4f, 0.16f, 0.7f), bench);
                AddMesh(MeshFactory.Box(), new Vector3(0, 0.55f, 0.3f), Lighten(WOOD, 0.08f), new Vector3(-12, 0, 0), new Vector3(2.4f, 0.5f, 0.12f), bench);
                foreach (float lx in new[] { -1f, 1f })
                    AddMesh(MeshFactory.Box(), new Vector3(lx, -0.12f, 0), Darken(WOOD, 0.2f), Vector3.zero, new Vector3(0.14f, 0.3f, 0.6f), bench);
                AddBush(bp + new Vector3(Mathf.Sin(a), 0, Mathf.Cos(a)) * 1.4f + new Vector3(0, -0.25f, 0), 0.75f);
            }

            // ------------------------------------------------ 꽃밭·덤불·가로등·나무 더
            foreach (var p in new[] { new Vector3(20, 0, 10), new Vector3(-21, 0, -3), new Vector3(2, 0, -24), new Vector3(24, 0, -11), new Vector3(-22, 0, 8), new Vector3(-8, 0, -18) })
            {
                AddFlowers(p, 2.2f, 26, (int)(p.x * 7 + p.z));
                AddBush(p + new Vector3(1.6f, 0, 1f), 0.8f);
            }
            foreach (var p in new[] { new Vector3(-24, 0, -10), new Vector3(25, 0, 3), new Vector3(-10, 0, -24), new Vector3(14, 0, -22) })
                AddTree(p, 1, 0.85f, false);
            for (int i = 0; i < 4; i++) // 스폰 방향(30° 간격)을 피해 배치
            {
                float a = Deg(15f + 90f * i);
                AddLamp(new Vector3(Mathf.Sin(a) * 13f, 0, Mathf.Cos(a) * 13f), C(1f, 0.9f, 0.7f));
            }

            // ------------------------------------------------ 섬 밖: 떠 있는 작은 섬, 구름, 풍선
            for (int i = 0; i < 6; i++)
            {
                float a = Mathf.PI * 2f * i / 6f + 0.4f;
                var p = new Vector3(Mathf.Sin(a) * 45f, -6f + (i % 3) * 4f, Mathf.Cos(a) * 45f);
                AddMesh(Cyl(4f, 4f, 1.5f, 32), p, GRASS);
                AddMesh(Cyl(4.15f, 3.9f, 0.5f, 32), p + new Vector3(0, -0.85f, 0), GRASS_EDGE);
                AddIslandUnderside(p + new Vector3(0, -1f, 0), 3.9f, 5f, ROCK);
                AddTree(p + new Vector3(0.8f, 0.75f, -0.5f), i % 3, 0.75f, false);
                AddFlowers(p + new Vector3(0, 0.75f, 0), 3f, 14, i + 20);
            }
            for (int i = 0; i < 12; i++)
            {
                float a = Mathf.PI * 2f * i / 12f + 0.2f;
                float r = 62f + (i % 3) * 10f;
                AddCloud(new Vector3(Mathf.Sin(a) * r, 4f + (i % 4) * 4f, Mathf.Cos(a) * r), 1f + (i % 3) * 0.3f);
            }
            for (int i = 0; i < 6; i++) // 섬 아래 구름 → 아득한 높이감
            {
                float a = Mathf.PI * 2f * i / 6f;
                AddCloud(new Vector3(Mathf.Sin(a) * 34f, -22f - (i % 2) * 4f, Mathf.Cos(a) * 34f), 1.8f);
            }
            Color[] balloonColors = { C(1f, 0.55f, 0.65f), C(0.6f, 0.8f, 1f), C(1f, 0.85f, 0.4f), C(0.7f, 0.95f, 0.6f), C(0.82f, 0.68f, 1f) };
            for (int i = 0; i < 10; i++)
            {
                float a = Mathf.PI * 2f * i / 10f + 0.15f;
                float rr = 31f + (i % 3) * 3f;
                var p = new Vector3(Mathf.Sin(a) * rr, 6f + (i % 4) * 1.6f, Mathf.Cos(a) * rr);
                var bal = NewDynamic("Balloon", p);
                AddMesh(Sph(0.8f, 16), Vector3.zero, balloonColors[i % 5], Vector3.zero, new Vector3(1, 1.18f, 1), bal);
                AddMesh(Cyl(0.015f, 0.015f, 2.4f, 4), new Vector3(0, -2.1f, 0), Color.white, Vector3.zero, Vector3.one, bal);
                var b = bal.gameObject.AddComponent<Bobber>();
                b.basePos = p; b.amp = 0.5f; b.speed = 0.8f + (i % 3) * 0.2f; b.phase = i * 1.3f;
            }
        }

        void AddBobbing(Mesh mesh, Vector3 pos, Material mat, Vector3 scale, float amp, float speed, float phase)
        {
            var t = NewDynamic("Bobber", pos);
            AddMesh(mesh, Vector3.zero, mat, Vector3.zero, scale, t);
            var b = t.gameObject.AddComponent<Bobber>();
            b.basePos = pos; b.amp = amp; b.speed = speed; b.phase = phase;
        }

        /// <summary>포털 모습: 둥근 아치 링 + 소용돌이 + 빛나는 바닥 + 떠오르는 반짝이</summary>
        void BuildPortalVisual(Vector3 center, float ang, Color c)
        {
            var root = NewDecorGroup("Portal", center, new Vector3(0, ang * Mathf.Rad2Deg, 0)); // 로컬 +Z = 섬 바깥쪽
            AddMesh(Cyl(2.6f, 2.8f, 0.25f, 40), new Vector3(0, 0.1f, 0), STONE, Vector3.zero, Vector3.one, root);
            AddMesh(Cyl(2.05f, 2.05f, 0.06f, 40), new Vector3(0, 0.25f, 0), Glow(Lighten(c, 0.25f), 1.3f), Vector3.zero, Vector3.one, root);
            foreach (float sx in new[] { -1f, 1f })
            {
                AddMesh(Cyl(0.34f, 0.42f, 3.4f, 16), new Vector3(2.2f * sx, 1.8f, 0), Darken(c, 0.15f), Vector3.zero, Vector3.one, root);
                AddMesh(Sph(0.42f, 14), new Vector3(2.2f * sx, 3.55f, 0), Lighten(c, 0.35f), Vector3.zero, Vector3.one, root);
                AddMesh(Cyl(0.5f, 0.55f, 0.3f, 16), new Vector3(2.2f * sx, 0.3f, 0), Darken(STONE, 0.05f), Vector3.zero, Vector3.one, root);
            }
            AddMesh(MeshFactory.Torus(2f, 2.55f, 40, 12), new Vector3(0, 2.1f, 0), c, new Vector3(90, 0, 0), Vector3.one, root);
            for (int k = 0; k < 7; k++)
            {
                float t = Mathf.PI * (0.15f + 0.7f * k / 6f);
                AddMesh(Sph(0.16f, 10), new Vector3(Mathf.Cos(t) * 2.28f, 2.1f + Mathf.Sin(t) * 2.28f, 0.32f), Glow(Lighten(c, 0.6f), 1.4f), Vector3.zero, Vector3.one, root);
            }
            // 소용돌이 (셰이더 애니메이션, 양면)
            var sw = AddMesh(MeshFactory.Quad(4.1f, 4.1f), new Vector3(0, 2.1f, 0), PortalSwirl(c), Vector3.zero, Vector3.one, root);
            sw.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            sw.receiveShadows = false;
            // 떠오르는 반짝이 16개 (움직이므로 합치기에서 빠짐)
            var sp = NewDynamic("Sparkles", center + new Vector3(0, 0.3f, 0));
            var s = sp.gameObject.AddComponent<PortalSparkles>();
            s.Init(Glow(Lighten(c, 0.5f), 2f), center.GetHashCode());
        }
    }

    /// <summary>포털 바닥 고리에서 반짝이가 떠오른다 (Godot CPUParticles3D 와 같은 값)</summary>
    public class PortalSparkles : MonoBehaviour
    {
        const int Amount = 16;
        const float Lifetime = 2.2f;
        readonly Transform[] _p = new Transform[Amount];
        readonly Vector3[] _start = new Vector3[Amount];
        readonly float[] _speed = new float[Amount], _scale = new float[Amount];
        System.Random _rng;

        public void Init(Material mat, int seed)
        {
            _rng = new System.Random(seed);
            Mesh m = MeshFactory.Sphere(0.07f, 6);
            for (int i = 0; i < Amount; i++)
            {
                var go = new GameObject("s");
                go.transform.SetParent(transform, false);
                go.AddComponent<MeshFilter>().sharedMesh = m;
                var mr = go.AddComponent<MeshRenderer>();
                mr.sharedMaterial = mat;
                mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
                mr.receiveShadows = false;
                _p[i] = go.transform;
                Respawn(i);
            }
        }

        void Respawn(int i)
        {
            float a = (float)_rng.NextDouble() * Mathf.PI * 2f;
            float r = Mathf.Lerp(0.3f, 1.9f, Mathf.Sqrt((float)_rng.NextDouble()));
            _start[i] = new Vector3(Mathf.Cos(a) * r, (float)_rng.NextDouble() * 0.1f, Mathf.Sin(a) * r);
            _speed[i] = Mathf.Lerp(0.6f, 1.2f, (float)_rng.NextDouble());
            _scale[i] = Mathf.Lerp(0.6f, 1.3f, (float)_rng.NextDouble());
        }

        void Update()
        {
            if (_rng == null) return;
            for (int i = 0; i < Amount; i++)
            {
                // 각 반짝이는 시작 시각을 엇갈리게: 0~수명 사이를 반복
                float age = (Time.time + i * Lifetime / Amount) % Lifetime;
                if (age < Time.deltaTime) Respawn(i);
                float y = _speed[i] * age + 0.3f * age * age; // 위로 가속 (gravity +0.6)
                _p[i].localPosition = _start[i] + new Vector3(0, y, 0);
                float fade = Mathf.Sin(age / Lifetime * Mathf.PI);
                _p[i].localScale = Vector3.one * (_scale[i] * fade);
            }
        }
    }
}
