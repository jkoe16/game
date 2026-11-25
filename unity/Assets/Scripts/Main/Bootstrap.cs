using UnityEngine;

namespace PartyWorld
{
    /// <summary>
    /// 1단계 테스트: 씬 파일 없이 실행하면 바로 연습장과 캐릭터를 코드로 만든다.
    /// Unity 에서 아무 씬(새 프로젝트 기본 씬도 됨)을 열고 재생(▶)하면 된다.
    /// 조작: WASD/방향키 이동, Shift 걷기, Space 점프, 클릭하면 마우스로 카메라, Esc 마우스 풀기, 휠 줌.
    /// 휴대폰: 왼쪽 화면 조이스틱, 오른쪽 드래그 카메라, 오른쪽 아래 점프 버튼.
    /// </summary>
    public static class Bootstrap
    {
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Start()
        {
            if (Object.FindFirstObjectByType<PlayerBody>() != null) return; // 이미 배치된 씬이면 건드리지 않음

            Time.fixedDeltaTime = 1f / 60f; // 물리 60Hz (서버와 동일)
            Application.targetFrameRate = Application.isMobilePlatform ? 60 : -1;

            // 기존 카메라 정리 (새 프로젝트 기본 씬의 Main Camera)
            foreach (var c in Object.FindObjectsByType<Camera>(FindObjectsSortMode.None))
                Object.Destroy(c.gameObject);

            // 기본은 광장(로비). 주소 끝에 ?map=practice 를 붙이면 회색 연습장
            Vector3 spawn;
            float killHeight = -25f;
            if (Application.absoluteURL.Contains("map=practice"))
            {
                PracticeMap.Build();
                spawn = PracticeMap.Spawn;
            }
            else
            {
                var map = GameMap.Create<LobbyPlaza>();
                spawn = map.GetSpawnPoint(0);
                killHeight = map.killHeight;
            }

            // 플레이어
            var playerGo = new GameObject("Player");
            playerGo.layer = PartyLayers.Player;
            playerGo.AddComponent<CharacterController>();
            var body = playerGo.AddComponent<PlayerBody>();
            body.Teleport(spawn);
            body.visual = CharacterVisual.Build(new Color(1f, 0.62f, 0.55f)).transform;

            // 카메라
            var camGo = new GameObject("PlayerCamera");
            camGo.tag = "MainCamera";
            var cam = camGo.AddComponent<ThirdPersonCamera>();
            cam.target = body;
            camGo.AddComponent<AudioListener>();

            // 조작
            var ctrlGo = new GameObject("LocalPlayer");
            var ctrl = ctrlGo.AddComponent<LocalPlayerController>();
            ctrl.body = body;
            ctrl.cam = cam;
            ctrl.spawnPoint = spawn;
            ctrl.killHeight = killHeight;

            // 휴대폰·태블릿(웹 포함)에서만 터치 버튼 표시. PC 브라우저는 터치 장치가 잡혀도 키보드·마우스로.
            bool touch = Application.isMobilePlatform;
            if (touch)
            {
                cam.touchMode = Application.isMobilePlatform; // 터치 화면 노트북은 마우스도 그대로
                var tc = ctrlGo.AddComponent<TouchControls>();
                tc.controller = ctrl;
                tc.cam = cam;
            }
            ctrlGo.AddComponent<DebugHud>().body = body;
        }
    }

    /// <summary>왼쪽 위에 속도·프레임 표시 (이동 느낌 비교용)</summary>
    public class DebugHud : MonoBehaviour
    {
        public PlayerBody body;
        float _fps;

        void Update() { _fps = Mathf.Lerp(_fps, 1f / Mathf.Max(Time.unscaledDeltaTime, 0.0001f), 0.05f); }

        void OnGUI()
        {
            if (body == null) return;
            float s = Screen.height / 720f;
            var style = new GUIStyle(GUI.skin.label) { fontSize = Mathf.RoundToInt(18 * s) };
            float hs = new Vector2(body.velocity.x, body.velocity.z).magnitude;
            GUI.Label(new Rect(10 * s, 10 * s, 600 * s, 30 * s), $"speed {hs:0.00} m/s   fps {_fps:0}   floor {body.IsOnFloor}", style);
        }
    }

    /// <summary>
    /// 임시 캐릭터 모습 (Godot 판처럼 도형으로 만든 2.5등신). 나중에 모델 파일로 바꾼다.
    /// </summary>
    public static class CharacterVisual
    {
        public static GameObject Build(Color bodyColor)
        {
            var root = new GameObject("CharacterVisual");
            var mat = GameMap.Toon(bodyColor);
            var skin = GameMap.Toon(new Color(1f, 0.87f, 0.76f));

            var torso = Prim(PrimitiveType.Sphere, root.transform, new Vector3(0f, 0.45f, 0f), new Vector3(0.75f, 0.7f, 0.7f), mat);
            var head = Prim(PrimitiveType.Sphere, root.transform, new Vector3(0f, 1.15f, 0f), new Vector3(0.85f, 0.8f, 0.8f), skin);
            // 눈 (앞 = +Z)
            var eye = GameMap.Toon(new Color(0.15f, 0.12f, 0.2f));
            Prim(PrimitiveType.Sphere, head.transform, new Vector3(-0.17f, 0.05f, 0.45f), Vector3.one * 0.12f, eye);
            Prim(PrimitiveType.Sphere, head.transform, new Vector3(0.17f, 0.05f, 0.45f), Vector3.one * 0.12f, eye);
            // 새싹 모자
            var leaf = GameMap.Toon(new Color(0.45f, 0.8f, 0.4f));
            Prim(PrimitiveType.Sphere, head.transform, new Vector3(0f, 0.55f, 0f), new Vector3(0.12f, 0.2f, 0.12f), leaf);
            // 발
            Prim(PrimitiveType.Sphere, root.transform, new Vector3(-0.18f, 0.08f, 0.05f), new Vector3(0.22f, 0.16f, 0.3f), mat);
            Prim(PrimitiveType.Sphere, root.transform, new Vector3(0.18f, 0.08f, 0.05f), new Vector3(0.22f, 0.16f, 0.3f), mat);
            return root;
        }

        static GameObject Prim(PrimitiveType t, Transform parent, Vector3 localPos, Vector3 scale, Material m)
        {
            var g = GameObject.CreatePrimitive(t);
            Object.Destroy(g.GetComponent<Collider>());
            g.transform.SetParent(parent, false);
            // 자식의 scale 은 부모 scale 을 상쇄해서 지정한 크기 그대로
            Vector3 ps = parent.lossyScale;
            g.transform.localPosition = new Vector3(localPos.x / ps.x, localPos.y / ps.y, localPos.z / ps.z);
            g.transform.localScale = new Vector3(scale.x / ps.x, scale.y / ps.y, scale.z / ps.z);
            g.GetComponent<Renderer>().sharedMaterial = m;
            return g;
        }
    }
}
