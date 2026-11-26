using System.Collections.Generic;
using UnityEngine;

namespace PartyWorld
{
    /// <summary>
    /// 플레이어 외형 + 애니메이션 (Godot scripts/player/character_visual.gd 이식).
    /// 동그란 도형으로 만든 2.5등신 캐릭터. 부위 이름(Rig/Body/Head/HandL/HandR/FootL/FootR)과 동작 이름은 Godot 판과 같다.
    /// 애니메이션도 Godot 판의 키 값을 그대로 옮겨, 코드로 섞는다:
    ///   이동(서기·걷기·뛰기, 속도로 섞기) ↔ 공중(점프·낙하) → 착지(한 번) → 감정 표현(한 번)
    /// 모델 앞쪽 = +Z. 위치·방향은 PlayerBody 가 이 오브젝트(visual)에 넣어 준다.
    /// </summary>
    public class CharacterVisual : MonoBehaviour
    {
        public static readonly string[] EmoteInputs = { "wave", "dance", "victory", "defeat", "knockdown" };
        /// <summary>걷기·뛰기 클립 공통 길이 (같아야 섞일 때 발 박자가 맞는다)</summary>
        const float GaitLen = 0.4f;
        const float WalkPeriod = 0.44f;
        const float RunPeriod = 0.32f;
        /// <summary>이동 섞기에서 걷기 클립 위치 (속도 / 걷기 최고 속도)</summary>
        const float WalkPoint = 0.45f;

        // 부위 번호
        const int Rig = 0, Body = 1, Head = 2, HandL = 3, HandR = 4, FootL = 5, FootR = 6, PartCount = 7;
        static readonly string[] PartNames = { "Rig", "Body", "Head", "HandL", "HandR", "FootL", "FootR" };
        static readonly Vector3[] Rest =
        {
            new Vector3(0, 0, 0), new Vector3(0, 0.52f, 0), new Vector3(0, 1.12f, 0),
            new Vector3(0.50f, 0.55f, 0.05f), new Vector3(-0.50f, 0.55f, 0.05f),
            new Vector3(0.20f, 0.10f, 0.02f), new Vector3(-0.20f, 0.10f, 0.02f),
        };

        /// <summary>몸 상태를 읽어 올 대상 (내 캐릭터). 다른 사람 캐릭터는 UpdateMotion 을 직접 부른다</summary>
        public PlayerBody sourceBody;
        /// <summary>내 캐릭터면 1~4 키로 감정 표현 (손 흔들기·춤·만세·시무룩)</summary>
        public bool readEmoteKeys;
        /// <summary>내 캐릭터가 감정 표현을 했을 때 (온라인이면 서버에 알린다)</summary>
        public static System.Action<int> onLocalEmote;

        readonly Transform[] _parts = new Transform[PartCount];
        readonly List<Transform> _eyes = new List<Transform>();
        float _blinkIn = 2.5f, _blinkT = -1f;
        Transform _shadow;
        Material _shadowMat;

        // ---- 애니메이션 상태
        static Dictionary<string, Clip> _clips;
        float _locoPos;          // 0 = 서기, 0.45 = 걷기, 1 = 뛰기
        float _locoScale = 1f;
        float _idleT, _walkT, _runT;
        float _airBlend;         // -1 = 낙하, 1 = 점프
        float _airT;
        float _airW;             // 0 = 땅, 1 = 공중 (0.12초 동안 섞임)
        bool _grounded = true, _wantAir;
        float _airTimer, _minAirVy;
        float _landT = -1f;
        string _emote;
        float _emoteT = -1f;
        Pose _pose, _tmpA, _tmpB;

        // ================================================================== 만들기

        public static CharacterVisual Build(int colorIndex, int hatIndex, Transform parent = null)
        {
            var go = new GameObject("CharacterVisual");
            if (parent != null) go.transform.SetParent(parent, false);
            var cv = go.AddComponent<CharacterVisual>();
            cv.BuildModel(Appearance.BodyColors[Appearance.SanitizeColor(colorIndex)], Appearance.Hats[Appearance.SanitizeHat(hatIndex)]);
            cv.BuildShadow();
            cv._blinkIn = Random.Range(1f, 4f);
            EnsureClips();
            cv._pose = new Pose();
            cv._tmpA = new Pose();
            cv._tmpB = new Pose();
            return cv;
        }

        void BuildModel(Color color, string hat)
        {
            var bodyMat = GameMap.Toon(color);
            var bellyMat = GameMap.Toon(GameMap.Lighten(color, 0.45f));
            var limbMat = GameMap.Toon(GameMap.Darken(color, 0.12f));
            var eyeMat = GameMap.Glow(new Color(0.12f, 0.1f, 0.16f), 1f);
            var shineMat = GameMap.Glow(new Color(1, 1, 1), 1f);
            var cheekMat = GameMap.Glow(new Color(1f, 0.6f, 0.66f), 1f);
            var mouthMat = GameMap.Glow(new Color(0.35f, 0.16f, 0.2f), 1f);

            var rig = new GameObject("Rig").transform;
            rig.SetParent(transform, false);
            _parts[Rig] = rig;
            for (int i = 1; i < PartCount; i++)
            {
                var t = new GameObject(PartNames[i]).transform;
                t.SetParent(rig, false);
                t.localPosition = Rest[i];
                _parts[i] = t;
            }

            var body = _parts[Body];
            Sphere(body, 0.42f, Vector3.zero, new Vector3(1, 1, 0.92f), bodyMat);
            Sphere(body, 0.28f, new Vector3(0, -0.05f, 0.25f), new Vector3(1, 1, 0.45f), bellyMat);

            var head = _parts[Head];
            Sphere(head, 0.46f, Vector3.zero, new Vector3(1, 0.92f, 0.95f), bodyMat);
            foreach (float side in new[] { -1f, 1f })
            {
                // 큰 눈 + 반짝임 두 개
                var eye = Sphere(head, 0.075f, new Vector3(0.155f * side, 0.03f, 0.39f), new Vector3(1, 1.35f, 0.6f), eyeMat);
                _eyes.Add(eye);
                Sphere(eye, 0.028f, new Vector3(0.025f, 0.032f, 0.06f), new Vector3(1, 0.85f, 1), shineMat);
                Sphere(eye, 0.012f, new Vector3(-0.02f, -0.035f, 0.065f), Vector3.one, shineMat);
                // 볼터치
                Sphere(head, 0.07f, new Vector3(0.255f * side, -0.075f, 0.345f), new Vector3(1.2f, 0.65f, 0.35f), cheekMat);
            }
            // 웃는 입: 작은 구슬을 호 모양으로
            for (int i = 0; i < 5; i++)
            {
                float t = (i - 2) / 2f;
                Sphere(head, 0.017f, new Vector3(t * 0.045f, -0.09f - 0.022f * (1f - t * t), 0.43f - 0.01f * t * t), Vector3.one, mouthMat);
            }
            BuildHat(head, hat, color);

            Sphere(_parts[HandL], 0.13f, Vector3.zero, Vector3.one, bodyMat);
            Sphere(_parts[HandR], 0.13f, Vector3.zero, Vector3.one, bodyMat);
            Sphere(_parts[FootL], 0.16f, Vector3.zero, new Vector3(1, 0.6f, 1.3f), limbMat);
            Sphere(_parts[FootR], 0.16f, Vector3.zero, new Vector3(1, 0.6f, 1.3f), limbMat);
        }

        void BuildHat(Transform head, string hat, Color color)
        {
            switch (hat)
            {
                case "cat":
                {
                    var ear = GameMap.Toon(GameMap.Darken(color, 0.05f));
                    var inner = GameMap.Toon(new Color(1f, 0.7f, 0.76f));
                    foreach (float side in new[] { -1f, 1f })
                    {
                        var e = Cylinder(head, 0f, 0.16f, 0.28f, new Vector3(0.25f * side, 0.4f, 0f), ear);
                        e.localRotation = Quaternion.Euler(-5, 0, -22 * side);
                        e.localScale = new Vector3(1, 1, 0.6f);
                        var ie = Cylinder(e, 0f, 0.1f, 0.18f, new Vector3(0, -0.03f, 0.09f), inner);
                        ie.localScale = new Vector3(1, 1, 0.4f);
                    }
                    break;
                }
                case "bunny":
                {
                    var ear = GameMap.Toon(GameMap.Lighten(color, 0.1f));
                    var inner = GameMap.Toon(new Color(1f, 0.7f, 0.76f));
                    foreach (float side in new[] { -1f, 1f })
                    {
                        var e = Sphere(head, 0.09f, new Vector3(0.13f * side, 0.56f, -0.02f), new Vector3(0.8f, 2.4f, 0.5f), ear);
                        e.localRotation = Quaternion.Euler(0, 0, -10f * side);
                        Sphere(e, 0.06f, new Vector3(0, 0, 0.04f), new Vector3(0.7f, 0.9f, 0.4f), inner);
                    }
                    break;
                }
                case "flower":
                {
                    var petal = GameMap.Toon(new Color(1f, 0.95f, 0.98f));
                    var center = GameMap.Toon(new Color(1f, 0.8f, 0.3f));
                    var pin = new GameObject("FlowerPin").transform;
                    pin.SetParent(head, false);
                    pin.localPosition = new Vector3(0.28f, 0.3f, 0.2f);
                    pin.localRotation = Quaternion.Euler(-25, 35, -20);
                    pin.localScale = Vector3.one * 1.35f;
                    for (int i = 0; i < 5; i++)
                    {
                        float ang = Mathf.PI * 2f * i / 5f;
                        Sphere(pin, 0.06f, new Vector3(Mathf.Sin(ang) * 0.07f, Mathf.Cos(ang) * 0.07f, 0), new Vector3(1, 1, 0.45f), petal);
                    }
                    Sphere(pin, 0.045f, new Vector3(0, 0, 0.02f), new Vector3(1, 1, 0.6f), center);
                    break;
                }
                case "sprout":
                {
                    var green = GameMap.Toon(new Color(0.4f, 0.8f, 0.35f));
                    Cylinder(head, 0.02f, 0.02f, 0.16f, new Vector3(0, 0.48f, 0), green);
                    foreach (float side in new[] { -1f, 1f })
                    {
                        var leaf = Sphere(head, 0.09f, new Vector3(0.08f * side, 0.57f, 0), new Vector3(1, 0.25f, 0.55f), green);
                        leaf.localRotation = Quaternion.Euler(0, 0, -25f * side);
                    }
                    break;
                }
                case "cap":
                {
                    var red = GameMap.Toon(new Color(0.9f, 0.3f, 0.3f));
                    Cylinder(head, 0.33f, 0.38f, 0.16f, new Vector3(0, 0.36f, 0), red);
                    var brim = Cylinder(head, 0.26f, 0.26f, 0.03f, new Vector3(0, 0.3f, 0.25f), red);
                    brim.localScale = new Vector3(1, 1, 0.8f);
                    break;
                }
                case "crown":
                {
                    var gold = GameMap.Toon(new Color(1f, 0.82f, 0.25f));
                    Cylinder(head, 0.24f, 0.2f, 0.18f, new Vector3(0, 0.46f, 0), gold);
                    for (int i = 0; i < 5; i++)
                    {
                        float ang = Mathf.PI * 2f * i / 5f;
                        Sphere(head, 0.045f, new Vector3(Mathf.Sin(ang) * 0.22f, 0.57f, Mathf.Cos(ang) * 0.22f), Vector3.one, gold);
                    }
                    break;
                }
                case "bow":
                {
                    var pink = GameMap.Toon(new Color(1f, 0.45f, 0.65f));
                    foreach (float side in new[] { -1f, 1f })
                        Sphere(head, 0.11f, new Vector3(0.12f * side, 0.4f, 0.08f), new Vector3(1, 0.7f, 0.45f), pink);
                    Sphere(head, 0.05f, new Vector3(0, 0.4f, 0.1f), Vector3.one, pink);
                    break;
                }
            }
        }

        static Transform Sphere(Transform parent, float radius, Vector3 pos, Vector3 scl, Material mat) =>
            MeshNode(parent, MeshFactory.Sphere(radius, 24), pos, scl, mat);

        static Transform Cylinder(Transform parent, float top, float bottom, float height, Vector3 pos, Material mat) =>
            MeshNode(parent, MeshFactory.Cylinder(top, bottom, height, 20), pos, Vector3.one, mat);

        static Transform MeshNode(Transform parent, Mesh mesh, Vector3 pos, Vector3 scl, Material mat)
        {
            var go = new GameObject(mesh.name);
            go.transform.SetParent(parent, false);
            go.transform.localPosition = pos;
            go.transform.localScale = scl;
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterial = mat;
            return go.transform;
        }

        /// <summary>발밑 원형 그림자: 땅에 붙어 있는 느낌과 점프 높이를 알려 준다</summary>
        void BuildShadow()
        {
            var go = new GameObject("BlobShadow");
            go.AddComponent<MeshFilter>().sharedMesh = MeshFactory.Quad(1.3f, 1.3f);
            go.transform.rotation = Quaternion.Euler(90f, 0f, 0f); // 세로 사각형을 눕혀 바닥에
            var mr = go.AddComponent<MeshRenderer>();
            _shadowMat = new Material(Shader.Find("PartyWorld/BlobShadow"));
            mr.sharedMaterial = _shadowMat;
            mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            mr.receiveShadows = false;
            _shadow = go.transform; // 부모 없음 (Godot top_level): 캐릭터 회전과 상관없이 바닥에
        }

        void OnDestroy()
        {
            if (_shadow != null) Destroy(_shadow.gameObject);
        }

        void UpdateShadow()
        {
            if (_shadow == null) return;
            Vector3 from = transform.position + new Vector3(0, 0.4f, 0);
            int mask = ~(1 << PartyLayers.Player);
            if (!Physics.Raycast(from, Vector3.down, out var hit, 30f, mask, QueryTriggerInteraction.Ignore))
            {
                _shadow.gameObject.SetActive(false);
                return;
            }
            float h = from.y - 0.4f - hit.point.y;
            _shadow.gameObject.SetActive(true);
            _shadow.position = hit.point + new Vector3(0, 0.03f, 0);
            float k = Mathf.Clamp(1f - h / 6f, 0.35f, 1f);
            _shadow.localScale = new Vector3(k, k, 1);
            _shadowMat.SetFloat("_Alpha", k);
        }

        /// <summary>2~5초마다 눈을 깜빡인다</summary>
        void UpdateBlink(float dt)
        {
            if (_eyes.Count == 0) return;
            if (_blinkT >= 0f)
            {
                _blinkT += dt;
                float k = Mathf.Abs(_blinkT / 0.07f - 1f);
                foreach (var e in _eyes) e.localScale = new Vector3(1, 1.35f * Mathf.Max(k, 0.08f), 0.6f);
                if (_blinkT >= 0.14f)
                {
                    _blinkT = -1f;
                    foreach (var e in _eyes) e.localScale = new Vector3(1, 1.35f, 0.6f);
                }
            }
            else
            {
                _blinkIn -= dt;
                if (_blinkIn <= 0f)
                {
                    _blinkT = 0f;
                    _blinkIn = Random.Range(2f, 5f);
                }
            }
        }

        // ================================================================== 매 프레임

        void Update()
        {
            float dt = Time.deltaTime;
            if (sourceBody != null)
                UpdateMotion(sourceBody.velocity, sourceBody.IsOnFloor, dt);
            if (readEmoteKeys)
            {
                int e = InputReader.EmotePressed();
                if (e >= 0)
                {
                    PlayEmote(Appearance.Emotes[e]);
                    onLocalEmote?.Invoke(e);
                }
            }
            Animate(dt);
            UpdateBlink(dt);
        }

        void LateUpdate() => UpdateShadow();

        /// <summary>걷기·뛰기 재생 속도: 서 있을 땐 1, 걷기 지점까지는 걷기 박자, 그 위로는 뛰기 박자로 매끄럽게</summary>
        static float GaitTimeScale(float hs)
        {
            float walkScale = GaitLen / WalkPeriod;
            if (hs <= WalkPoint) return Mathf.Lerp(1f, walkScale, Mathf.Clamp01(hs / WalkPoint));
            float t = Mathf.Clamp01((hs - WalkPoint) / (1f - WalkPoint));
            return GaitLen / Mathf.Lerp(WalkPeriod, RunPeriod, t);
        }

        public void UpdateMotion(Vector3 vel, bool grounded, float dt)
        {
            float hs = new Vector2(vel.x, vel.z).magnitude / PlayerBody.WalkSpeed;
            _locoPos = Mathf.Clamp01(hs);
            _locoScale = GaitTimeScale(hs);
            _airBlend = Mathf.Clamp(vel.y / 8f, -1f, 1f);
            if (grounded)
            {
                if (!_grounded)
                {
                    _wantAir = false;
                    if (_minAirVy < -5f) _landT = 0f;
                }
                _grounded = true;
                _airTimer = 0f;
                _minAirVy = 0f;
            }
            else
            {
                _airTimer += dt;
                _minAirVy = Mathf.Min(_minAirVy, vel.y);
                // 작은 턱에서 깜빡이지 않도록 짧은 공중 상태는 무시 (점프로 위로 뜰 때는 즉시 전환)
                if (_grounded && (_airTimer > 0.08f || vel.y > 2f))
                {
                    _wantAir = true;
                    _airT = 0f; // Godot 전환 노드처럼 공중 동작을 처음부터
                    _grounded = false;
                }
            }
        }

        public void PlayEmote(string emoteName)
        {
            if (System.Array.IndexOf(EmoteInputs, emoteName) < 0) return;
            _emote = emoteName;
            _emoteT = 0f;
        }

        void Animate(float dt)
        {
            // 이동: 세 클립 모두 시간을 흘려 발 박자를 맞춰 둔다 (Godot blend space sync)
            float sdt = dt * _locoScale;
            _idleT += sdt; _walkT += sdt; _runT += sdt;
            Clip idle = _clips["idle"], walk = _clips["walk"], run = _clips["run"];
            if (_locoPos <= WalkPoint)
            {
                idle.Sample(_idleT, _tmpA);
                walk.Sample(_walkT, _tmpB);
                Pose.Lerp(_tmpA, _tmpB, _locoPos / WalkPoint, _pose);
            }
            else
            {
                walk.Sample(_walkT, _tmpA);
                run.Sample(_runT, _tmpB);
                Pose.Lerp(_tmpA, _tmpB, (_locoPos - WalkPoint) / (1f - WalkPoint), _pose);
            }

            // 공중 (0.12초 섞기)
            _airW = Mathf.MoveTowards(_airW, _wantAir ? 1f : 0f, dt / 0.12f);
            _airT += dt;
            if (_airW > 0.001f)
            {
                var air = new Pose();
                _clips["fall"].Sample(_airT, _tmpA);
                _clips["jump"].Sample(_airT, _tmpB);
                Pose.Lerp(_tmpA, _tmpB, (_airBlend + 1f) * 0.5f, air);
                Pose.Lerp(_pose, air, _airW, _pose);
            }

            // 착지 (한 번, 0.02초 들어가고 0.1초 빠짐)
            if (_landT >= 0f)
            {
                var land = _clips["land"];
                _landT += dt;
                float w = OneShotWeight(_landT, land.length, 0.02f, 0.1f);
                land.Sample(_landT, _tmpA);
                Pose.Lerp(_pose, _tmpA, w, _pose);
                if (_landT >= land.length) _landT = -1f;
            }

            // 감정 표현 (한 번, 0.15초 들어가고 0.2초 빠짐)
            if (_emoteT >= 0f && _emote != null)
            {
                var clip = _clips[_emote];
                _emoteT += dt;
                float w = OneShotWeight(_emoteT, clip.length, 0.15f, 0.2f);
                clip.Sample(_emoteT, _tmpA);
                Pose.Lerp(_pose, _tmpA, w, _pose);
                if (_emoteT >= clip.length) _emoteT = -1f;
            }

            for (int i = 0; i < PartCount; i++)
            {
                _parts[i].localPosition = _pose.pos[i];
                _parts[i].localRotation = _pose.rot[i];
                _parts[i].localScale = _pose.scl[i];
            }
        }

        static float OneShotWeight(float t, float len, float fadeIn, float fadeOut) =>
            Mathf.Clamp01(Mathf.Min(t / fadeIn, (len - t) / fadeOut));

        // ================================================================== 애니메이션 데이터 (Godot 키 값 그대로)

        class Pose
        {
            public readonly Vector3[] pos = new Vector3[PartCount];
            public readonly Quaternion[] rot = new Quaternion[PartCount];
            public readonly Vector3[] scl = new Vector3[PartCount];

            public void SetRest()
            {
                for (int i = 0; i < PartCount; i++)
                {
                    pos[i] = Rest[i];
                    rot[i] = Quaternion.identity;
                    scl[i] = Vector3.one;
                }
            }

            public static void Lerp(Pose a, Pose b, float t, Pose o)
            {
                for (int i = 0; i < PartCount; i++)
                {
                    o.pos[i] = Vector3.Lerp(a.pos[i], b.pos[i], t);
                    o.rot[i] = Quaternion.Slerp(a.rot[i], b.rot[i], t);
                    o.scl[i] = Vector3.Lerp(a.scl[i], b.scl[i], t);
                }
            }
        }

        class Track
        {
            public int part, kind; // kind 0 = 위치, 1 = 회전, 2 = 크기
            public float[] times;
            public Vector3[] vals;
            public Quaternion[] quats;
        }

        class Clip
        {
            public float length;
            public bool loop;
            public readonly List<Track> tracks = new List<Track>();

            /// <summary>키 사이를 직선으로 섞는다. 없는 부위는 기본 자세(Godot RESET)</summary>
            public void Sample(float t, Pose o)
            {
                o.SetRest();
                if (loop) t = Mathf.Repeat(t, length);
                else t = Mathf.Min(t, length);
                foreach (var tr in tracks)
                {
                    int n = tr.times.Length;
                    int k = 0;
                    while (k < n - 1 && tr.times[k + 1] <= t) k++;
                    float w = 0f;
                    if (k < n - 1 && t > tr.times[k])
                        w = (t - tr.times[k]) / Mathf.Max(tr.times[k + 1] - tr.times[k], 0.0001f);
                    int k2 = Mathf.Min(k + 1, n - 1);
                    if (t <= tr.times[0]) { k = k2 = 0; w = 0f; }
                    switch (tr.kind)
                    {
                        case 0: o.pos[tr.part] = Vector3.Lerp(tr.vals[k], tr.vals[k2], w); break;
                        case 1: o.rot[tr.part] = Quaternion.Slerp(tr.quats[k], tr.quats[k2], w); break;
                        default: o.scl[tr.part] = Vector3.Lerp(tr.vals[k], tr.vals[k2], w); break;
                    }
                }
            }

            /// <summary>위치 키: [시간, 기본 자세 기준 오프셋]</summary>
            public Clip Pos(int part, params (float t, Vector3 v)[] keys)
            {
                var tr = new Track { part = part, kind = 0, times = new float[keys.Length], vals = new Vector3[keys.Length] };
                for (int i = 0; i < keys.Length; i++) { tr.times[i] = keys[i].t; tr.vals[i] = Rest[part] + keys[i].v; }
                tracks.Add(tr);
                return this;
            }

            /// <summary>회전 키: [시간, 오일러 각도(도)]</summary>
            public Clip Rot(int part, params (float t, Vector3 v)[] keys)
            {
                var tr = new Track { part = part, kind = 1, times = new float[keys.Length], quats = new Quaternion[keys.Length] };
                for (int i = 0; i < keys.Length; i++) { tr.times[i] = keys[i].t; tr.quats[i] = Quaternion.Euler(keys[i].v); }
                tracks.Add(tr);
                return this;
            }

            public Clip Scl(int part, params (float t, Vector3 v)[] keys)
            {
                var tr = new Track { part = part, kind = 2, times = new float[keys.Length], vals = new Vector3[keys.Length] };
                for (int i = 0; i < keys.Length; i++) { tr.times[i] = keys[i].t; tr.vals[i] = keys[i].v; }
                tracks.Add(tr);
                return this;
            }
        }

        static Vector3 V(float x, float y, float z) => new Vector3(x, y, z);
        static readonly Vector3 Z = Vector3.zero;
        static readonly Vector3 One = Vector3.one;

        static void EnsureClips()
        {
            if (_clips != null) return;
            _clips = new Dictionary<string, Clip>
            {
                ["idle"] = new Clip { length = 1.6f, loop = true }
                    .Scl(Rig, (0f, One), (0.8f, V(1.03f, 0.97f, 1.03f)), (1.6f, One))
                    .Rot(Head, (0f, Z), (0.8f, V(0, 0, 3)), (1.6f, Z))
                    .Pos(HandL, (0f, Z), (0.8f, V(0, -0.02f, 0)), (1.6f, Z))
                    .Pos(HandR, (0f, Z), (0.8f, V(0, -0.02f, 0)), (1.6f, Z)),
                ["walk"] = Gait(GaitLen, 0.2f, 0.1f, 0.06f, 0.14f, 4f, 3f),
                ["run"] = Gait(GaitLen, 0.3f, 0.16f, 0.10f, 0.22f, 12f, 4f),
                ["jump"] = new Clip { length = 0.25f }
                    .Scl(Rig, (0f, V(0.85f, 1.2f, 0.85f)), (0.25f, V(0.95f, 1.05f, 0.95f)))
                    .Pos(HandL, (0f, V(0.05f, 0.3f, 0)))
                    .Pos(HandR, (0f, V(-0.05f, 0.3f, 0)))
                    .Pos(FootL, (0f, V(0, 0.05f, -0.05f)))
                    .Pos(FootR, (0f, V(0, 0.08f, 0.05f))),
                ["fall"] = new Clip { length = 0.4f, loop = true }
                    .Pos(HandL, (0f, V(0.1f, 0.35f, 0)), (0.2f, V(0.14f, 0.45f, 0)), (0.4f, V(0.1f, 0.35f, 0)))
                    .Pos(HandR, (0f, V(-0.14f, 0.45f, 0)), (0.2f, V(-0.1f, 0.35f, 0)), (0.4f, V(-0.14f, 0.45f, 0)))
                    .Pos(FootL, (0f, V(0, 0.04f, 0.06f)), (0.2f, V(0, 0.08f, -0.06f)), (0.4f, V(0, 0.04f, 0.06f)))
                    .Pos(FootR, (0f, V(0, 0.08f, -0.06f)), (0.2f, V(0, 0.04f, 0.06f)), (0.4f, V(0, 0.08f, -0.06f))),
                ["land"] = new Clip { length = 0.25f }
                    .Scl(Rig, (0f, V(1.25f, 0.75f, 1.25f)), (0.1f, V(0.94f, 1.07f, 0.94f)), (0.25f, One)),
                ["wave"] = Wave(),
                ["dance"] = Dance(),
                ["victory"] = Victory(),
                ["defeat"] = new Clip { length = 1.8f }
                    .Rot(Head, (0f, Z), (0.3f, V(25, 0, 0)), (1.5f, V(25, 0, 5)), (1.8f, Z))
                    .Rot(Rig, (0f, Z), (0.3f, V(10, 0, 0)), (1.5f, V(10, 0, 0)), (1.8f, Z))
                    .Scl(Rig, (0f, One), (0.3f, V(1.05f, 0.9f, 1.05f)), (1.5f, V(1.05f, 0.9f, 1.05f)), (1.8f, One))
                    .Pos(HandL, (0f, Z), (0.3f, V(-0.1f, -0.15f, 0.12f)), (1.5f, V(-0.1f, -0.15f, 0.12f)), (1.8f, Z))
                    .Pos(HandR, (0f, Z), (0.3f, V(0.1f, -0.15f, 0.12f)), (1.5f, V(0.1f, -0.15f, 0.12f)), (1.8f, Z)),
                ["knockdown"] = new Clip { length = 1.4f }
                    .Rot(Rig, (0f, Z), (0.25f, V(-80, 0, 0)), (1f, V(-80, 0, 0)), (1.4f, Z))
                    .Pos(Rig, (0f, Z), (0.25f, V(0, 0.4f, -0.3f)), (1f, V(0, 0.4f, -0.3f)), (1.4f, Z)),
            };
        }

        static Clip Gait(float length, float stride, float lift, float bob, float swing, float pitch, float roll)
        {
            float q = length / 4f;
            return new Clip { length = length, loop = true }
                .Pos(FootL, (0f, V(0, 0, stride)), (q, V(0, lift, 0)), (2 * q, V(0, 0, -stride)), (3 * q, Z), (length, V(0, 0, stride)))
                .Pos(FootR, (0f, V(0, 0, -stride)), (q, Z), (2 * q, V(0, 0, stride)), (3 * q, V(0, lift, 0)), (length, V(0, 0, -stride)))
                .Pos(Rig, (0f, Z), (q, V(0, bob, 0)), (2 * q, Z), (3 * q, V(0, bob, 0)), (length, Z))
                .Pos(HandL, (0f, V(0, 0, -swing)), (2 * q, V(0, 0.03f, swing)), (length, V(0, 0, -swing)))
                .Pos(HandR, (0f, V(0, 0.03f, swing)), (2 * q, V(0, 0, -swing)), (length, V(0, 0.03f, swing)))
                .Rot(Rig, (0f, V(pitch, 0, roll)), (2 * q, V(pitch, 0, -roll)), (length, V(pitch, 0, roll)));
        }

        static Clip Wave()
        {
            var up = V(0.05f, 0.55f, 0.1f);
            var side = V(0.2f, 0.55f, 0.1f);
            return new Clip { length = 1.5f }
                .Pos(HandL, (0f, Z), (0.2f, up), (0.4f, side), (0.6f, up), (0.8f, side), (1f, up), (1.3f, up), (1.5f, Z))
                .Rot(Head, (0f, Z), (0.3f, V(0, 0, 8)), (1.2f, V(0, 0, 8)), (1.5f, Z));
        }

        static Clip Dance()
        {
            var rk = new (float, Vector3)[9];
            var pk = new (float, Vector3)[9];
            var hl = new (float, Vector3)[9];
            var hr = new (float, Vector3)[9];
            for (int i = 0; i < 9; i++)
            {
                float t = i * 0.25f;
                float s = i % 2 == 0 ? 0f : (i % 4 == 1 ? 1f : -1f);
                rk[i] = (t, V(0, 25f * s, 8f * s));
                pk[i] = (t, V(0, i % 2 == 0 ? 0f : 0.12f, 0));
                hl[i] = (t, i % 4 < 2 ? V(0.05f, 0.5f, 0) : V(0.05f, 0f, 0.1f));
                hr[i] = (t, i % 4 < 2 ? V(-0.05f, 0f, 0.1f) : V(-0.05f, 0.5f, 0));
            }
            return new Clip { length = 2f }.Rot(Rig, rk).Pos(Rig, pk).Pos(HandL, hl).Pos(HandR, hr);
        }

        static Clip Victory()
        {
            var pk = new (float, Vector3)[9];
            for (int i = 0; i < 9; i++)
                pk[i] = (i * 0.2f, i % 2 == 1 && i < 8 ? V(0, 0.45f, 0) : Z);
            return new Clip { length = 1.6f }
                .Pos(Rig, pk)
                .Pos(HandL, (0f, Z), (0.15f, V(0.1f, 0.55f, 0)), (1.4f, V(0.1f, 0.55f, 0)), (1.6f, Z))
                .Pos(HandR, (0f, Z), (0.15f, V(-0.1f, 0.55f, 0)), (1.4f, V(-0.1f, 0.55f, 0)), (1.6f, Z));
        }
    }
}
