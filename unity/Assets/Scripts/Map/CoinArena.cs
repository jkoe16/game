using System.Collections.Generic;
using UnityEngine;

namespace PartyWorld
{
    /// <summary>
    /// 보물 수집 경기장 "보물섬" (Godot scripts/gameplay/maps/coin_arena.gd 이식).
    /// 30×30 모래 바닥 + 울타리 + 높이가 다른 발판 2개(경사로로 연결) + 가운데 회전 망치. 보물은 모드가 배치.
    /// </summary>
    public class CoinArena : GameMap
    {
        public const float Half = 15f;
        /// <summary>바위 (x, 높이, z)</summary>
        static readonly Vector3[] Rocks = { new Vector3(-12.6f, 3.2f, -12.6f), new Vector3(-12.6f, 2.4f, -9.4f), new Vector3(-9.4f, 2.4f, -12.6f), new Vector3(12.6f, 2f, -12.6f) };
        static readonly Vector3[] Palms = { new Vector3(12.5f, 0, 12.5f), new Vector3(-12.5f, 0, 12.5f), new Vector3(12.8f, 0, -9f) };
        public static readonly (Vector3 center, float top)[] Platforms = { (new Vector3(-7, 0, -7), 1.6f), (new Vector3(7, 0, 7), 3f) };
        /// <summary>숨겨진 전설 보물상자가 나타날 수 있는 곳</summary>
        public static readonly Vector3[] HiddenSpots = { new Vector3(-11f, 1f, -11f), new Vector3(13.2f, 1f, 13.2f), new Vector3(9.6f, 4f, 9.6f), new Vector3(13.2f, 1f, -12f), new Vector3(-13.2f, 1f, 13.2f) };

        protected override void BuildMap()
        {
            mapId = "coin_arena";
            displayName = "보물섬";
            killHeight = -10f;
            SetupEnvironment(C(0.4f, 0.62f, 0.95f), C(1f, 0.92f, 0.75f), new Vector3(-50, -20, 0));
            AddBox(new Vector3(0, -0.5f, 0), new Vector3(Half * 2, 1, Half * 2), C(0.98f, 0.87f, 0.6f));
            foreach (var r in Rocks)
                AddCylinder(new Vector3(r.x, r.y * 0.5f, r.z), r.y * 0.5f, r.y, C(0.66f, 0.58f, 0.55f), true, 14);
            foreach (var p in Palms)
                AddBox(p + new Vector3(0, 2.5f, 0), new Vector3(0.6f, 5f, 0.6f), Color.white, Vector3.zero, true, false);
            foreach (float side in new[] { -1f, 1f })
            {
                AddBox(new Vector3(Half * side, 0.5f, 0), new Vector3(0.6f, 1, Half * 2), C(1, 0.95f, 0.85f));
                AddBox(new Vector3(0, 0.5f, Half * side), new Vector3(Half * 2, 1, 0.6f), C(1, 0.95f, 0.85f));
            }
            foreach (var p in Platforms)
                AddBox(new Vector3(p.center.x, p.top * 0.5f, p.center.z), new Vector3(6, p.top, 6), C(0.95f, 0.7f, 0.5f));
            AddBox(new Vector3(-7, 0.8f, -1.9f), new Vector3(3, 0.3f, 4.5f), C(0.9f, 0.8f, 0.6f), new Vector3(20, 0, 0));
            AddBox(new Vector3(7, 1.5f, 0f), new Vector3(3, 0.3f, 8.5f), C(0.9f, 0.8f, 0.6f), new Vector3(-20, 0, 0));
            for (int i = 0; i < 8; i++)
            {
                float a = Mathf.PI * 2f * i / 8f;
                spawnPoints.Add(new Vector3(Mathf.Sin(a) * 4f, 0.5f, Mathf.Cos(a) * 4f));
            }
            // 가운데 황금 별 자리를 지키는 회전 망치 (점프로 넘기)
            AddSweeper(Vector3.zero, 3.4f, 0.5f, 80f, 0f, 0f, 1, 0.4f, C(1f, 0.45f, 0.5f), true);
            Decorate();
        }

        void Decorate()
        {
            AddMesh(Cyl(40f, 40f, 0.2f, 48), new Vector3(0, -2.6f, 0), Water(C(0.35f, 0.75f, 0.95f, 0.8f)), Vector3.zero, Vector3.one);
            AddMesh(Cyl(23f, 24f, 0.6f, 48), new Vector3(0, -2.3f, 0), C(0.98f, 0.9f, 0.68f));
            for (int i = 0; i < 5; i++)
                AddMesh(MeshFactory.Box(), new Vector3(-12f + i * 6f, 0.01f, 0), C(0.99f, 0.92f, 0.72f), Vector3.zero, new Vector3(2f, 0.02f, Half * 2 - 1f));
            foreach (var p in Palms) Palm(p);
            foreach (var r in Rocks)
            {
                AddMesh(Sph(r.y * 0.45f, 12), new Vector3(r.x, r.y, r.z), C(0.72f, 0.64f, 0.6f), Vector3.zero, new Vector3(1, 0.6f, 1));
                AddBush(new Vector3(r.x + 0.6f, r.y * 0.85f, r.z + 0.4f), 0.45f, C(0.35f, 0.7f, 0.45f));
            }
            AddMesh(MeshFactory.Torus(1.9f, 2.7f, 24, 10), new Vector3(-11f, 0.2f, -11f), C(0.6f, 0.52f, 0.5f), new Vector3(90, 45, 0), Vector3.one);
            Chest(new Vector3(-11.6f, 0, -11.6f), 45f);
            Chest(new Vector3(9.5f, 3f, 9.5f), -135f);
            Color[] cols = { C(1f, 0.6f, 0.7f), C(0.55f, 0.75f, 1f), C(1f, 0.82f, 0.35f), C(0.6f, 0.88f, 0.55f) };
            int k = 0;
            for (int t = -15; t <= 15; t += 5)
                foreach (float side in new[] { -1f, 1f })
                {
                    AddMesh(MeshFactory.Box(), new Vector3(t, 0.75f, Half * side), cols[k % 4], Vector3.zero, new Vector3(0.8f, 1.5f, 0.8f));
                    AddMesh(MeshFactory.Box(), new Vector3(Half * side, 0.75f, t), cols[(k + 2) % 4], Vector3.zero, new Vector3(0.8f, 1.5f, 0.8f));
                    k++;
                }
            foreach (var p in Platforms)
                AddEdgeTrim(new Vector3(p.center.x, p.top * 0.5f, p.center.z), new Vector3(6, p.top, 6), Color.white);
            AddMesh(Cyl(2.2f, 2.2f, 0.03f, 32), new Vector3(0, 0.02f, 0), C(1f, 0.86f, 0.35f));
            AddMesh(Cyl(1.6f, 1.6f, 0.035f, 32), new Vector3(0, 0.03f, 0), C(1f, 0.95f, 0.7f));
        }

        void Palm(Vector3 p)
        {
            Color trunk = C(0.72f, 0.52f, 0.36f);
            for (int k = 0; k < 5; k++)
                AddMesh(Cyl(0.22f, 0.28f, 0.95f, 10), p + new Vector3(k * 0.12f, 0.5f + k * 0.9f, 0), Lighten(trunk, 0.05f * (k % 2)), new Vector3(0, 0, -6f * k), Vector3.one);
            var top = p + new Vector3(0.6f, 4.9f, 0);
            for (int k = 0; k < 6; k++)
            {
                float a = Mathf.PI * 2f * k / 6f;
                AddMesh(Sph(1f, 10), top + new Vector3(Mathf.Cos(a), -0.25f, Mathf.Sin(a)) * 1.2f, C(0.35f, 0.75f, 0.4f), new Vector3(0, -a * Mathf.Rad2Deg, -25), new Vector3(1.6f, 0.18f, 0.55f));
            }
            AddMesh(Sph(0.22f, 8), top + new Vector3(0.2f, -0.35f, 0.2f), C(0.55f, 0.4f, 0.3f));
            AddMesh(Sph(0.22f, 8), top + new Vector3(-0.2f, -0.38f, 0.1f), C(0.55f, 0.4f, 0.3f));
        }

        void Chest(Vector3 p, float yaw)
        {
            var root = NewDecorGroup("Chest", p, new Vector3(0, yaw, 0));
            AddMesh(MeshFactory.Box(), new Vector3(0, 0.35f, 0), C(0.72f, 0.45f, 0.3f), Vector3.zero, new Vector3(1.2f, 0.7f, 0.8f), root);
            AddMesh(MeshFactory.Box(), new Vector3(0, 0.75f, -0.3f), C(0.8f, 0.52f, 0.35f), new Vector3(-35, 0, 0), new Vector3(1.25f, 0.12f, 0.85f), root);
            AddMesh(MeshFactory.Box(), new Vector3(0, 0.36f, 0.41f), C(1f, 0.82f, 0.3f), Vector3.zero, new Vector3(0.25f, 0.3f, 0.04f), root);
            for (int k = 0; k < 5; k++)
                AddMesh(Cyl(0.14f, 0.14f, 0.05f, 10), new Vector3(-0.35f + k * 0.17f, 0.74f, 0.05f * (k % 2)), Glow(C(1f, 0.82f, 0.3f), 1.3f), Vector3.zero, Vector3.one, root);
        }

        /// <summary>보물 배치. pattern: 0 = 흩뿌리기, 1 = 원형, 2 = 십자</summary>
        public List<Vector3> RandomCoinPoints(System.Random rng, int n, int pattern)
        {
            float R(float lo, float hi) => lo + (float)rng.NextDouble() * (hi - lo);
            var output = new List<Vector3>();
            for (int i = 0; i < n; i++)
            {
                var p = new Vector3(R(-Half + 2, Half - 2), 1f, R(-Half + 2, Half - 2));
                if (pattern == 1)
                {
                    float a = Mathf.PI * 2f * i / n;
                    p = new Vector3(Mathf.Sin(a) * 9f, 1f, Mathf.Cos(a) * 9f);
                }
                else if (pattern == 2)
                {
                    int arm = i % 4;
                    float d = 3f + (i / 4) * 2.6f;
                    p = new Vector3(new[] { d, -d, 0f, 0f }[arm], 1f, new[] { 0f, 0f, d, -d }[arm]);
                }
                foreach (var pl in Platforms)
                {
                    if (Mathf.Abs(p.x - pl.center.x) <= 3f && Mathf.Abs(p.z - pl.center.z) <= 3f)
                    {
                        p.y = pl.top + 1f;
                        // 발판 가운데는 보석 자리 → 금화는 가장자리 쪽으로
                        var off = new Vector2(p.x - pl.center.x, p.z - pl.center.z);
                        if (off.magnitude < 1.8f)
                        {
                            off = (off.magnitude > 0.01f ? off.normalized : new Vector2(1, 1).normalized) * 2.2f;
                            p.x = pl.center.x + off.x;
                            p.z = pl.center.z + off.y;
                        }
                    }
                }
                if (new Vector2(p.x, p.z).magnitude < 1.8f) { p.x = 2.2f; p.z = 0f; } // 가운데는 황금 별 자리
                // 바위·야자수 안에 생기지 않게 바깥으로
                var obstacles = new List<Vector3>(Rocks);
                obstacles.AddRange(Palms);
                foreach (var r in obstacles)
                {
                    var flat = new Vector2(p.x - r.x, p.z - r.z);
                    float keep = (r.y > 0f ? r.y * 0.5f : 0.4f) + 1.2f;
                    if (flat.magnitude < keep)
                    {
                        var dir = flat.magnitude > 0.01f ? flat.normalized : new Vector2(1, 1).normalized;
                        var q = new Vector2(r.x, r.z) + dir * keep;
                        p.x = Mathf.Clamp(q.x, -Half + 2, Half - 2);
                        p.z = Mathf.Clamp(q.y, -Half + 2, Half - 2);
                    }
                }
                output.Add(p);
            }
            return output;
        }

        // ---------------------------------------------------------------- 보물 표시
        public class Coin { public Vector3 pos; public bool alive = true; public int value; }
        readonly List<Transform> _coinNodes = new List<Transform>();
        readonly List<int> _coinLook = new List<int>();

        /// <summary>등급별 모양: 금화 1 · 보석 3(하늘색) · 황금 별 5 · 전설 보물상자 10(보라)</summary>
        public void RenderCoins(List<Coin> coins)
        {
            while (_coinNodes.Count < coins.Count)
            {
                var t = NewDynamic("Coin", Vector3.zero);
                var spin = new GameObject("spin").transform;
                spin.SetParent(t, false);
                spin.gameObject.AddComponent<Spinner>().speed = 3f * Mathf.Rad2Deg;
                AddMesh(Cyl(0.45f, 0.45f, 0.12f, 20), Vector3.zero, Glow(C(1f, 0.8f, 0.25f), 1.15f), new Vector3(90, 0, 0), Vector3.one, spin);
                AddMesh(Cyl(0.28f, 0.28f, 0.14f, 16), Vector3.zero, Glow(C(1f, 0.95f, 0.6f), 1.3f), new Vector3(90, 0, 0), Vector3.one, spin);
                _coinNodes.Add(t);
                _coinLook.Add(0);
            }
            for (int i = 0; i < _coinNodes.Count; i++)
            {
                var node = _coinNodes[i];
                bool show = i < coins.Count && coins[i].alive;
                if (node.gameObject.activeSelf != show) node.gameObject.SetActive(show);
                if (!show) continue;
                node.localPosition = coins[i].pos;
                int v = coins[i].value;
                if (_coinLook[i] == v) continue;
                _coinLook[i] = v;
                float scale; Color col; float energy;
                switch (v)
                {
                    case 3: scale = 1.5f; col = C(0.45f, 0.85f, 1f); energy = 1.8f; break;
                    case 5: scale = 2.2f; col = C(1f, 0.95f, 0.4f); energy = 1.8f; break;
                    case 10: scale = 2.6f; col = C(0.85f, 0.5f, 1f); energy = 2.4f; break;
                    default: scale = 1f; col = C(1f, 0.8f, 0.25f); energy = 1.15f; break;
                }
                node.localScale = Vector3.one * scale;
                node.GetChild(0).GetChild(0).GetComponent<MeshRenderer>().sharedMaterial = Glow(col, energy);
            }
        }
    }

    /// <summary>Y축으로 계속 돈다 (도/초)</summary>
    public class Spinner : MonoBehaviour
    {
        public float speed = 90f;
        void Update() => transform.Rotate(0f, speed * Time.deltaTime, 0f, Space.Self);
    }
}
