using System.Collections.Generic;
using UnityEngine;

namespace PartyWorld
{
    /// <summary>
    /// 모든 맵의 공통 기반 (Godot scripts/gameplay/game_map.gd 이식).
    /// 위치·크기·각도 숫자는 Godot 판을 그대로 쓴다 (충돌 레이아웃이 서버와 같아야 하므로).
    /// 움직이지 않는 장식은 Decor 아래에 모아 두었다가 다 만든 뒤 정적 합치기(static batching)로 묶는다.
    /// </summary>
    public abstract class GameMap : MonoBehaviour
    {
        public string mapId = "";
        public string displayName = "";
        public float killHeight = -25f;
        public readonly List<Vector3> spawnPoints = new List<Vector3>();
        /// <summary>넓은 발판 아래에 바위층을 자동으로 붙인다 (시각 전용). 직접 꾸미는 맵은 false</summary>
        protected bool autoUnderside = true;

        protected Transform solidRoot, decorRoot, dynamicRoot;

        public Vector3 GetSpawnPoint(int index)
        {
            if (spawnPoints.Count == 0) return new Vector3(0, 1, 0);
            int n = spawnPoints.Count;
            return spawnPoints[((index % n) + n) % n];
        }

        /// <summary>맵을 만든다. 하위 클래스가 BuildMap()에 내용을 채운다.</summary>
        public static T Create<T>() where T : GameMap
        {
            var go = new GameObject(typeof(T).Name);
            var map = go.AddComponent<T>();
            map.solidRoot = new GameObject("Solid").transform;
            map.solidRoot.SetParent(go.transform, false);
            map.decorRoot = new GameObject("Decor").transform;
            map.decorRoot.SetParent(go.transform, false);
            map.dynamicRoot = new GameObject("Dynamic").transform;
            map.dynamicRoot.SetParent(go.transform, false);
            map.BuildMap();
            // 장식을 재질별로 합쳐서 그리기 호출을 줄인다
            StaticBatchingUtility.Combine(map.decorRoot.gameObject);
            return map;
        }

        protected abstract void BuildMap();

        // ================================================================== 색 도우미 (Godot Color 와 같은 뜻)

        public static Color Lighten(Color c, float a) => new Color(c.r + (1 - c.r) * a, c.g + (1 - c.g) * a, c.b + (1 - c.b) * a, c.a);
        public static Color Darken(Color c, float a) => new Color(c.r * (1 - a), c.g * (1 - a), c.b * (1 - a), c.a);
        public static Color C(float r, float g, float b, float a = 1f) => new Color(r, g, b, a);

        // ================================================================== 재질

        static readonly Dictionary<string, Material> MatCache = new Dictionary<string, Material>();

        static Shader _toon, _glow, _water, _swirl, _sky;
        static Shader FindShader(ref Shader cache, string name)
        {
            if (cache == null) cache = Shader.Find(name);
            if (cache == null) cache = Shader.Find("Standard");
            return cache;
        }

        /// <summary>카툰 재질 (색마다 하나, 공유)</summary>
        public static Material Toon(Color c)
        {
            string key = "toon/" + ColorUtility.ToHtmlStringRGBA(c);
            if (!MatCache.TryGetValue(key, out var m))
            {
                m = new Material(FindShader(ref _toon, "PartyWorld/Toon")) { name = key, color = c, enableInstancing = true };
                MatCache[key] = m;
            }
            return m;
        }

        /// <summary>스스로 빛나는 재질 (그늘 없음)</summary>
        public static Material Glow(Color c, float energy = 1.5f)
        {
            string key = $"glow/{ColorUtility.ToHtmlStringRGBA(c)}/{energy:0.##}";
            if (!MatCache.TryGetValue(key, out var m))
            {
                m = new Material(FindShader(ref _glow, "PartyWorld/Glow")) { name = key, color = c };
                m.SetFloat("_Energy", energy);
                MatCache[key] = m;
            }
            return m;
        }

        public static Material Water(Color c)
        {
            string key = "water/" + ColorUtility.ToHtmlStringRGBA(c);
            if (!MatCache.TryGetValue(key, out var m))
            {
                m = new Material(FindShader(ref _water, "PartyWorld/Water")) { name = key, color = c };
                MatCache[key] = m;
            }
            return m;
        }

        public static Material PortalSwirl(Color c)
        {
            string key = "swirl/" + ColorUtility.ToHtmlStringRGBA(c);
            if (!MatCache.TryGetValue(key, out var m))
            {
                m = new Material(FindShader(ref _swirl, "PartyWorld/PortalSwirl")) { name = key, color = c };
                MatCache[key] = m;
            }
            return m;
        }

        // ================================================================== 충돌 + 모습

        GameObject MakeSolid(string name, Vector3 pos, Vector3 rotDeg)
        {
            var go = new GameObject(name);
            go.transform.SetParent(solidRoot, false);
            go.transform.localPosition = pos;
            go.transform.localRotation = Quaternion.Euler(rotDeg);
            return go;
        }

        public GameObject AddBox(Vector3 pos, Vector3 size, Color color) => AddBox(pos, size, color, Vector3.zero);

        public GameObject AddBox(Vector3 pos, Vector3 size, Color color, Vector3 rotDeg, bool collide = true, bool show = true)
        {
            GameObject root = null;
            if (collide)
            {
                root = MakeSolid("Box", pos, rotDeg);
                root.AddComponent<BoxCollider>().size = size;
            }
            if (show)
            {
                AddMesh(MeshFactory.Box(), pos, Toon(color), rotDeg, size);
                if (autoUnderside && size.x >= 4f && size.z >= 4f && size.y <= 2f && rotDeg.magnitude < 0.1f)
                    BoxUnderside(pos, size, color);
            }
            return root;
        }

        /// <summary>넓은 판 아래 층층이 좁아지는 바위 → 떠 있는 섬처럼</summary>
        void BoxUnderside(Vector3 pos, Vector3 size, Color color)
        {
            Color rock = Color.Lerp(C(0.74f, 0.62f, 0.6f), color, 0.15f);
            float y = -size.y * 0.5f, k = 0.88f;
            for (int i = 0; i < 3; i++)
            {
                float h = 0.9f + i * 0.5f;
                AddMesh(MeshFactory.Box(), pos + new Vector3(0, y - h * 0.5f, 0), Toon(Darken(rock, 0.07f * i)), Vector3.zero, new Vector3(size.x * k, h, size.z * k));
                y -= h;
                k *= 0.7f;
            }
        }

        public GameObject AddCylinder(Vector3 pos, float radius, float height, Color color, bool collide = true, int segments = 48)
        {
            GameObject root = null;
            if (collide)
            {
                root = MakeSolid("Cylinder", pos, Vector3.zero);
                // 고정된 발판이라 볼록(convex)이 아니어도 된다. 충돌 모양은 48조각으로 통일
                root.AddComponent<MeshCollider>().sharedMesh = MeshFactory.Cylinder(radius, radius, height, Mathf.Min(segments, 48));
            }
            AddMesh(MeshFactory.Cylinder(radius, radius, height, segments), pos, color);
            if (autoUnderside && radius >= 4f && height <= 3f)
                AddIslandUnderside(pos + new Vector3(0, -height * 0.5f, 0), radius * 0.97f, radius * 0.9f);
            return root;
        }

        /// <summary>시각 전용 구 (충돌 없음)</summary>
        public void AddDecoSphere(Vector3 pos, float radius, Color color) => AddMesh(MeshFactory.Sphere(radius, 20), pos, color);

        // ================================================================== 메시 배치 (시각 전용)

        public MeshRenderer AddMesh(Mesh mesh, Vector3 pos, Color color) => AddMesh(mesh, pos, Toon(color), Vector3.zero, Vector3.one);
        public MeshRenderer AddMesh(Mesh mesh, Vector3 pos, Color color, Vector3 rotDeg, Vector3 scale, Transform parent = null)
            => AddMesh(mesh, pos, Toon(color), rotDeg, scale, parent);

        /// <summary>메시 하나를 배치. parent 가 없으면 Decor(나중에 합쳐짐), 있으면 그 아래 로컬 좌표</summary>
        public MeshRenderer AddMesh(Mesh mesh, Vector3 pos, Material mat, Vector3 rotDeg, Vector3 scale, Transform parent = null)
        {
            var go = new GameObject(mesh.name);
            go.transform.SetParent(parent != null ? parent : decorRoot, false);
            go.transform.localPosition = pos;
            go.transform.localRotation = Quaternion.Euler(rotDeg);
            go.transform.localScale = scale;
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterial = mat;
            return mr;
        }

        /// <summary>움직이는 장식의 뿌리 (합치기에서 빠짐)</summary>
        public Transform NewDynamic(string name, Vector3 pos, Vector3 rotDeg = default)
        {
            var t = new GameObject(name).transform;
            t.SetParent(dynamicRoot, false);
            t.localPosition = pos;
            t.localRotation = Quaternion.Euler(rotDeg);
            return t;
        }

        /// <summary>움직이지 않는 장식 묶음 뿌리 (Decor 아래 → 합치기 대상)</summary>
        public Transform NewDecorGroup(string name, Vector3 pos, Vector3 rotDeg = default)
        {
            var t = new GameObject(name).transform;
            t.SetParent(decorRoot, false);
            t.localPosition = pos;
            t.localRotation = Quaternion.Euler(rotDeg);
            return t;
        }

        public static Mesh Cyl(float top, float bottom, float h, int seg = 20) => MeshFactory.Cylinder(top, bottom, h, seg);
        public static Mesh Sph(float r, int seg = 20) => MeshFactory.Sphere(r, seg);

        // ================================================================== 글자

        static Font _font;
        public static Font UIFont
        {
            get
            {
                if (_font == null) _font = Resources.Load<Font>("Fonts/NanumGothic");
                if (_font == null) _font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
                return _font;
            }
        }

        static Material _textMat;
        /// <summary>글자 재질: 깊이 검사를 해서 벽 뒤 글자는 가려진다</summary>
        static Material TextMaterial
        {
            get
            {
                if (_textMat == null)
                {
                    var sh = Shader.Find("PartyWorld/Text");
                    if (sh == null) return UIFont.material;
                    _textMat = new Material(sh) { mainTexture = UIFont.material.mainTexture };
                    // 동적 글꼴은 글자가 늘면 텍스처를 새로 만든다 → 재질도 따라 바꿈
                    Font.textureRebuilt += f => { if (f == UIFont && _textMat != null) _textMat.mainTexture = f.material.mainTexture; };
                }
                return _textMat;
            }
        }

        /// <summary>항상 카메라를 보는 글자 (Godot Label3D, pixel_size 0.01 → 글자 크기 size/100 m)</summary>
        public void AddLabel(Vector3 pos, string text, int size = 96, Color? color = null)
        {
            var root = new GameObject("Label: " + text).transform;
            root.SetParent(dynamicRoot, false);
            root.localPosition = pos;
            root.gameObject.AddComponent<Billboard>();
            Color outline = C(0.15f, 0.12f, 0.25f);
            float o = size * 0.0009f; // 테두리 두께
            Vector2[] offs = { new Vector2(o, 0), new Vector2(-o, 0), new Vector2(0, o), new Vector2(0, -o),
                               new Vector2(o, o) * 0.7f, new Vector2(-o, o) * 0.7f, new Vector2(o, -o) * 0.7f, new Vector2(-o, -o) * 0.7f };
            foreach (var off in offs)
                MakeText(root, text, size, outline, new Vector3(off.x, off.y, 0.01f));
            MakeText(root, text, size, color ?? Color.white, Vector3.zero);
        }

        static void MakeText(Transform parent, string text, int size, Color color, Vector3 local)
        {
            var go = new GameObject("t");
            go.transform.SetParent(parent, false);
            go.transform.localPosition = local;
            var tm = go.AddComponent<TextMesh>();
            tm.font = UIFont;
            tm.text = text;
            tm.fontSize = 64;
            tm.characterSize = size / 100f / 6.4f;
            tm.anchor = TextAnchor.MiddleCenter;
            tm.alignment = TextAlignment.Center;
            tm.color = color;
            var mr = go.GetComponent<MeshRenderer>();
            mr.sharedMaterial = TextMaterial;
            mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            mr.receiveShadows = false;
        }

        // ================================================================== 장식

        static readonly Color Wood = C(0.66f, 0.45f, 0.33f);

        /// <summary>통통한 나무. style 0 = 둥근 활엽수, 1 = 뾰족 침엽수, 2 = 꽃나무. collide면 줄기에 충돌</summary>
        public void AddTree(Vector3 pos, int style = 0, float size = 1f, bool collide = true)
        {
            float trunkH = 2.2f * size;
            if (collide)
            {
                var root = MakeSolid("Tree", pos + new Vector3(0, trunkH * 0.5f, 0), Vector3.zero);
                root.AddComponent<MeshCollider>().sharedMesh = Cyl(0.35f * size, 0.35f * size, trunkH, 12);
            }
            AddMesh(Cyl(0.22f * size, 0.38f * size, trunkH, 10), pos + new Vector3(0, trunkH * 0.5f, 0), Wood);
            if (style == 1)
            {
                Color g = C(0.33f, 0.68f, 0.5f);
                for (int i = 0; i < 3; i++)
                {
                    float r = (1.6f - i * 0.4f) * size;
                    AddMesh(Cyl(0.05f, r, 1.5f * size, 14), pos + new Vector3(0, trunkH + (0.4f + i * 0.95f) * size, 0), Lighten(g, i * 0.07f));
                }
            }
            else
            {
                Color leaf = style == 0 ? C(0.42f, 0.78f, 0.42f) : C(1f, 0.7f, 0.82f);
                (Vector3 p, float r)[] blobs = { (new Vector3(0, 0.9f, 0), 1.35f), (new Vector3(0.75f, 0.55f, 0.3f), 0.95f), (new Vector3(-0.7f, 0.6f, -0.25f), 0.9f), (new Vector3(0.1f, 1.65f, -0.1f), 0.85f), (new Vector3(-0.2f, 0.5f, 0.8f), 0.8f) };
                for (int i = 0; i < blobs.Length; i++)
                    AddMesh(Sph(blobs[i].r * size, 16), pos + new Vector3(0, trunkH, 0) + blobs[i].p * size, Lighten(leaf, 0.06f * (i % 3)));
            }
        }

        public void AddBush(Vector3 pos, float size = 1f) => AddBush(pos, size, C(0.4f, 0.74f, 0.42f));

        /// <summary>덤불 (구 3개 뭉치)</summary>
        public void AddBush(Vector3 pos, float size, Color color)
        {
            AddMesh(Sph(0.7f * size, 14), pos + new Vector3(0, 0.35f * size, 0), color, Vector3.zero, new Vector3(1.2f, 0.8f, 1f));
            AddMesh(Sph(0.5f * size, 12), pos + new Vector3(0.6f * size, 0.25f * size, 0.2f * size), Lighten(color, 0.08f));
            AddMesh(Sph(0.45f * size, 12), pos + new Vector3(-0.55f * size, 0.2f * size, -0.1f * size), Darken(color, 0.05f));
        }

        static readonly Color[] FlowerColors = { C(1f, 0.62f, 0.72f), C(1f, 0.9f, 0.45f), C(0.78f, 0.66f, 1f), C(1, 1, 1), C(1f, 0.7f, 0.45f) };

        /// <summary>꽃밭: 작은 꽃 여러 개 (같은 색끼리 합쳐져 그리기 호출이 적다)</summary>
        public void AddFlowers(Vector3 center, float radius, int count, int seed = 1)
        {
            var rng = new System.Random(seed);
            Mesh m = Sph(0.13f, 8);
            for (int i = 0; i < count; i++)
            {
                float a = (float)rng.NextDouble() * Mathf.PI * 2f;
                float r = Mathf.Sqrt((float)rng.NextDouble()) * radius;
                var p = center + new Vector3(Mathf.Cos(a) * r, 0.12f, Mathf.Sin(a) * r);
                var mr = AddMesh(m, p, FlowerColors[rng.Next(FlowerColors.Length)], Vector3.zero, new Vector3(1, 0.7f, 1));
                mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            }
        }

        /// <summary>푹신한 구름 (구 4개)</summary>
        public void AddCloud(Vector3 pos, float size = 1f)
        {
            (Vector3 p, float r)[] parts = { (Vector3.zero, 3f), (new Vector3(2.6f, -0.4f, 0.4f), 2.2f), (new Vector3(-2.5f, -0.5f, -0.2f), 2f), (new Vector3(0.6f, 1.2f, -0.3f), 2f) };
            foreach (var b in parts)
            {
                var mr = AddMesh(Sph(b.r * size, 14), pos + b.p * size, Color.white, Vector3.zero, new Vector3(1, 0.75f, 0.9f));
                mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
                mr.receiveShadows = false;
            }
        }

        public void AddLamp(Vector3 pos) => AddLamp(pos, C(1f, 0.92f, 0.65f));

        /// <summary>가로등 (빛나는 등불, 실제 조명 없이 발광 재질만)</summary>
        public void AddLamp(Vector3 pos, Color glow)
        {
            Color metal = C(0.45f, 0.42f, 0.6f);
            AddMesh(Cyl(0.07f, 0.1f, 2.6f, 8), pos + new Vector3(0, 1.3f, 0), metal);
            AddMesh(Cyl(0.22f, 0.28f, 0.18f, 10), pos + new Vector3(0, 0.09f, 0), metal);
            AddMesh(Sph(0.3f, 14), pos + new Vector3(0, 2.85f, 0), Glow(glow, 2.2f), Vector3.zero, Vector3.one);
            AddMesh(Cyl(0.02f, 0.34f, 0.22f, 10), pos + new Vector3(0, 3.22f, 0), metal);
        }

        /// <summary>출발/결승 아치. 로컬 X 방향으로 폭 width</summary>
        public void AddArch(Vector3 pos, float width, float height, Color color, float yawDeg = 0f)
        {
            var root = NewDecorGroup("Arch", pos, new Vector3(0, yawDeg, 0));
            float half = width * 0.5f;
            foreach (float sx in new[] { -1f, 1f })
            {
                AddMesh(Cyl(0.32f, 0.4f, height, 14), new Vector3(half * sx, height * 0.5f, 0), Darken(color, 0.12f), Vector3.zero, Vector3.one, root);
                AddMesh(Sph(0.48f, 14), new Vector3(half * sx, height + 0.2f, 0), Lighten(color, 0.4f), Vector3.zero, Vector3.one, root);
                AddMesh(Cyl(0.55f, 0.6f, 0.35f, 14), new Vector3(half * sx, 0.17f, 0), C(0.95f, 0.9f, 0.85f), Vector3.zero, Vector3.one, root);
            }
            AddMesh(MeshFactory.Box(), new Vector3(0, height - 0.45f, 0), color, Vector3.zero, new Vector3(width, 1.1f, 0.3f), root);
            AddMesh(MeshFactory.Box(), new Vector3(0, height + 0.12f, 0), Lighten(color, 0.45f), Vector3.zero, new Vector3(width, 0.18f, 0.36f), root);
            AddMesh(MeshFactory.Box(), new Vector3(0, height - 1.02f, 0), Lighten(color, 0.45f), Vector3.zero, new Vector3(width, 0.18f, 0.36f), root);
        }

        /// <summary>체크무늬 띠 (결승선 등)</summary>
        public void AddChecker(Vector3 center, float width, float depth, float cell = 0.7f, Color? a = null, Color? b = null)
        {
            Color ca = a ?? Color.white, cb = b ?? C(0.25f, 0.22f, 0.35f);
            int nx = Mathf.Max(1, Mathf.RoundToInt(width / cell));
            int nz = Mathf.Max(1, Mathf.RoundToInt(depth / cell));
            float cw = width / nx, cd = depth / nz;
            for (int i = 0; i < nx; i++)
                for (int k = 0; k < nz; k++)
                {
                    var p = center + new Vector3(-width * 0.5f + cw * (i + 0.5f), 0.02f, -depth * 0.5f + cd * (k + 0.5f));
                    AddMesh(MeshFactory.Box(), p, (i + k) % 2 == 0 ? ca : cb, Vector3.zero, new Vector3(cw, 0.04f, cd));
                }
        }

        /// <summary>깃발 (기둥 + 삼각 깃발)</summary>
        public void AddFlag(Vector3 pos, Color color, float yawDeg = 0f, float height = 3.2f)
        {
            AddMesh(Cyl(0.06f, 0.08f, height, 8), pos + new Vector3(0, height * 0.5f, 0), C(0.95f, 0.95f, 1f));
            AddMesh(Sph(0.12f, 8), pos + new Vector3(0, height + 0.08f, 0), C(1f, 0.85f, 0.35f));
            Vector3 off = Quaternion.Euler(0, yawDeg, 0) * new Vector3(0.45f, 0, 0);
            AddMesh(Cyl(0f, 0.5f, 0.9f, 3), pos + new Vector3(0, height - 0.45f, 0) + off, color, new Vector3(0, yawDeg, -90), new Vector3(1, 1, 0.25f));
        }

        /// <summary>판 윗면 가장자리를 두르는 밝은 띠</summary>
        public void AddEdgeTrim(Vector3 pos, Vector3 size, Color color, float w = 0.35f)
        {
            float top = pos.y + size.y * 0.5f + 0.015f;
            foreach (float s in new[] { -1f, 1f })
            {
                AddMesh(MeshFactory.Box(), new Vector3(pos.x, top, pos.z + s * (size.z * 0.5f - w * 0.5f)), color, Vector3.zero, new Vector3(size.x, 0.03f, w));
                AddMesh(MeshFactory.Box(), new Vector3(pos.x + s * (size.x * 0.5f - w * 0.5f), top, pos.z), color, Vector3.zero, new Vector3(w, 0.03f, size.z));
            }
        }

        public void AddIslandUnderside(Vector3 center, float topRadius, float depth) => AddIslandUnderside(center, topRadius, depth, C(0.66f, 0.55f, 0.52f));

        /// <summary>떠 있는 섬의 아랫부분: 아래로 갈수록 좁아지는 바위층</summary>
        public void AddIslandUnderside(Vector3 center, float topRadius, float depth, Color rock)
        {
            AddMesh(Cyl(topRadius, topRadius * 0.72f, depth * 0.35f, 40), center + new Vector3(0, -depth * 0.175f, 0), rock);
            AddMesh(Cyl(topRadius * 0.72f, topRadius * 0.38f, depth * 0.4f, 32), center + new Vector3(0, -depth * 0.55f, 0), Darken(rock, 0.08f));
            AddMesh(Cyl(topRadius * 0.38f, 0.4f, depth * 0.35f, 24), center + new Vector3(0, -depth * 0.925f, 0), Darken(rock, 0.16f));
        }

        // ================================================================== 조명·하늘

        /// <summary>하늘·안개·해. sunRotDeg 는 Godot DirectionalLight3D 회전값 그대로</summary>
        public void SetupEnvironment(Color skyTop, Color skyHorizon, Vector3 sunRotDeg)
        {
            var sky = new Material(FindShader(ref _sky, "PartyWorld/Sky"));
            sky.SetColor("_Top", skyTop);
            sky.SetColor("_Horizon", skyHorizon);
            sky.SetColor("_Bottom", Darken(skyTop, 0.2f));
            sky.SetFloat("_Curve", 0.12f);
            RenderSettings.skybox = sky;

            // 거리 안개: 가까운 곳은 선명하게, 먼 섬·구름만 하늘빛으로
            RenderSettings.fog = true;
            RenderSettings.fogMode = FogMode.Linear;
            RenderSettings.fogColor = Color.Lerp(skyHorizon, skyTop, 0.25f);
            RenderSettings.fogStartDistance = 40f;
            RenderSettings.fogEndDistance = 260f;

            // 주변광: 위는 하늘색, 옆은 지평선색, 아래는 어둡게 (셰이더가 ShadeSH9 로 읽음)
            Color ground = Darken(skyTop, 0.45f);
            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = skyTop;
            RenderSettings.ambientEquatorColor = skyHorizon;
            RenderSettings.ambientGroundColor = ground;
            RenderSettings.ambientIntensity = 1f;
            var sh = new UnityEngine.Rendering.SphericalHarmonicsL2();
            Color mid = (skyTop.linear + skyHorizon.linear * 2f + ground.linear) * 0.25f;
            sh.AddAmbientLight(mid);
            sh.AddDirectionalLight(Vector3.up, (skyTop.linear - ground.linear) * 0.6f, 1f);
            RenderSettings.ambientProbe = sh;

            // 해: Godot 빛은 로컬 -Z, Unity 빛은 로컬 +Z 로 비춘다 → Y 로 180° 더 돌림
            var sunGo = new GameObject("Sun");
            sunGo.transform.SetParent(transform, false);
            sunGo.transform.rotation = Quaternion.Euler(sunRotDeg) * Quaternion.Euler(0, 180, 0);
            var sun = sunGo.AddComponent<Light>();
            sun.type = LightType.Directional;
            sun.intensity = 1f;
            sun.color = C(1f, 0.97f, 0.9f);
            sun.shadows = LightShadows.Soft;
            sun.shadowStrength = 0.55f;
            sun.shadowBias = 0.05f;
            sun.shadowNormalBias = 0.4f;
            RenderSettings.sun = sun;
            QualitySettings.shadowDistance = 50f;
            QualitySettings.shadowCascades = 2;

            AddBackdrop();
        }

        /// <summary>모든 맵 공통 원경: 멀리 떠 있는 구름과 작은 섬</summary>
        void AddBackdrop()
        {
            var rng = new System.Random(StableHash(mapId));
            float Rand(float lo, float hi) => lo + (float)rng.NextDouble() * (hi - lo);
            Color grass = C(0.46f, 0.79f, 0.42f), rock = C(0.72f, 0.6f, 0.58f);
            for (int i = 0; i < 14; i++)
            {
                float a = Mathf.PI * 2f * i / 14f + Rand(0, 0.3f);
                float r = Rand(95f, 135f);
                AddCloud(new Vector3(Mathf.Cos(a) * r, Rand(-6f, 22f), Mathf.Sin(a) * r), Rand(1.4f, 2.4f));
            }
            for (int i = 0; i < 6; i++)
            {
                float a = Mathf.PI * 2f * i / 6f + Rand(0, 0.5f);
                float r = Rand(80f, 110f);
                var p = new Vector3(Mathf.Cos(a) * r, Rand(-28f, -12f), Mathf.Sin(a) * r);
                float s = Rand(4f, 8f);
                AddMesh(Cyl(s, s, 1.4f, 20), p, grass);
                AddIslandUnderside(p + new Vector3(0, -0.7f, 0), s, s * 1.4f, rock);
                AddTree(p + new Vector3(0, 0.7f, 0), i % 3, s * 0.18f, false);
            }
        }

        static int StableHash(string s)
        {
            unchecked
            {
                int h = 23;
                foreach (char ch in s) h = h * 31 + ch;
                return h;
            }
        }
    }

    /// <summary>항상 카메라를 바라본다 (글자용)</summary>
    public class Billboard : MonoBehaviour
    {
        void LateUpdate()
        {
            var cam = Camera.main;
            if (cam != null) transform.rotation = cam.transform.rotation;
        }
    }

    /// <summary>위아래로 둥실거리는 장식</summary>
    public class Bobber : MonoBehaviour
    {
        public Vector3 basePos;
        public float amp = 0.3f, speed = 1f, phase;

        void Update()
        {
            transform.localPosition = basePos + new Vector3(0, Mathf.Sin(Time.time * speed + phase) * amp, 0);
        }
    }
}
