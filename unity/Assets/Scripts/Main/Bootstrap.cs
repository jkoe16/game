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
        /// <summary>웹 주소의 ?이름=숫자 값 (없거나 잘못되면 기본값)</summary>
        static int UrlInt(string key, int def)
        {
            string url = Application.absoluteURL;
            int q = url.IndexOf('?');
            if (q < 0) return def;
            foreach (var part in url.Substring(q + 1).Split('&'))
            {
                var kv = part.Split('=');
                if (kv.Length == 2 && kv[0] == key && int.TryParse(kv[1], out int v)) return v;
            }
            return def;
        }

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
            // 외형: 주소 끝 ?color=번호&hat=번호 (없으면 딸기우유 + 새싹, Godot 기본값과 같음)
            var look = CharacterVisual.Build(UrlInt("color", 0), UrlInt("hat", 0));
            look.sourceBody = body;
            look.readEmoteKeys = true;
            body.visual = look.transform;

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
}
