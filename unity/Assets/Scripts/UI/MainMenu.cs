using UnityEngine;
using UnityEngine.UI;

namespace PartyWorld
{
    /// <summary>
    /// 시작 메뉴 (Godot scripts/ui/main_menu.gd 이식). 뒤에는 광장이 그대로 보이고, 가운데 흰 카드에서
    /// 닉네임·외형(색상·모자)을 고른 뒤 놀러 간다. 고른 값은 이 브라우저에 저장된다.
    /// 온라인(방 만들기·빠른 매칭)과 로그인은 다음 단계에서 이 카드에 붙인다.
    /// </summary>
    public class MainMenu : MonoBehaviour
    {
        public static MainMenu I;

        public PlayerBody body;
        public ThirdPersonCamera cam;
        public System.Action<string> onPlay; // 모드 id ("" = 광장)

        Canvas _canvas;
        InputField _nick, _room;
        Text _look, _note, _notice;
        /// <summary>온라인 버튼 (Bootstrap 이 연결)</summary>
        public System.Action onQuickMatch, onCreateRoom;
        public System.Action<string> onJoinRoom;
        int _color, _hat;

        public string Nickname => Clean(_nick != null ? _nick.text : "");
        public int ColorIndex => _color;
        public int HatIndex => _hat;

        public static MainMenu Create(PlayerBody body, ThirdPersonCamera cam)
        {
            var canvas = UiKit.MakeCanvas("MainMenu", 20);
            var m = canvas.gameObject.AddComponent<MainMenu>();
            I = m;
            m._canvas = canvas;
            m.body = body;
            m.cam = cam;
            m.Load();
            m.Build(canvas.transform);
            m.ApplyLook();
            return m;
        }

        void Load()
        {
            _color = Appearance.SanitizeColor(PlayerPrefs.GetInt("color", 0));
            _hat = Appearance.SanitizeHat(PlayerPrefs.GetInt("hat", 0));
        }

        void Save()
        {
            PlayerPrefs.SetString("nick", Nickname);
            PlayerPrefs.SetInt("color", _color);
            PlayerPrefs.SetInt("hat", _hat);
            PlayerPrefs.Save();
        }

        void Build(Transform root)
        {
            // 배경을 살짝 덮어 글자가 잘 보이게 (광장은 뒤에 그대로 보임)
            var dim = new GameObject("Dim");
            UiKit.Fill(dim, root);
            dim.AddComponent<Image>().color = new Color(0.45f, 0.4f, 0.75f, 0.18f);

            var c = new Vector2(0.5f, 0.5f);
            var title = UiKit.Label(root, "3D PARTY WORLD", 64, UiKit.Pink, TextAnchor.MiddleCenter, new Vector2(0.5f, 1f), new Vector2(0, -40), new Vector2(1000, 80));
            title.fontStyle = FontStyle.Bold;
            var o = title.gameObject.AddComponent<Outline>();
            o.effectColor = Color.white;
            o.effectDistance = new Vector2(4, -4);
            var sh = title.gameObject.AddComponent<Shadow>();
            sh.effectColor = new Color(0.3f, 0.2f, 0.55f, 0.35f);
            sh.effectDistance = new Vector2(0, -8);
            UiKit.Label(root, "친구들과 함께하는 하늘 위 파티 게임", 22, Color.white, TextAnchor.MiddleCenter, new Vector2(0.5f, 1f), new Vector2(0, -122), new Vector2(1000, 34), true);

            // 카드는 오른쪽에 두어 왼쪽의 내 캐릭터가 보이게
            var card = UiKit.Panel(root, new Vector2(1f, 0.5f), new Vector2(-60, -50), new Vector2(500, 540), new Color(1, 1, 1, 0.96f));
            var t = card.transform;
            var top = new Vector2(0.5f, 1f);
            UiKit.Label(t, "닉네임", 20, UiKit.InkSoft, TextAnchor.MiddleLeft, top, new Vector2(0, -22), new Vector2(440, 28));
            string saved = PlayerPrefs.GetString("nick", "");
            _nick = UiKit.Field(t, "닉네임 (2~16자, 한글/영문/숫자/_)", saved != "" ? saved : "Player" + Random.Range(0, 1000), top, new Vector2(0, -54), new Vector2(440, 54));

            UiKit.Label(t, "외형", 20, UiKit.InkSoft, TextAnchor.MiddleLeft, top, new Vector2(0, -120), new Vector2(440, 28));
            _look = UiKit.Label(t, "", 24, UiKit.Ink, TextAnchor.MiddleLeft, top, new Vector2(-50, -150), new Vector2(340, 50));
            _look.fontStyle = FontStyle.Bold;
            UiKit.Btn(t, "색상", Color.white, UiKit.Ink, top, new Vector2(110, -150), new Vector2(96, 48), () => { _color = (_color + 1) % Appearance.BodyColors.Length; ApplyLook(); }, 20);
            UiKit.Btn(t, "모자", Color.white, UiKit.Ink, top, new Vector2(200, -150), new Vector2(76, 48), () => { _hat = (_hat + 1) % Appearance.Hats.Length; ApplyLook(); }, 20);

            // 온라인: 빠른 매칭 / 방 만들기 / 코드로 입장
            UiKit.Btn(t, "친구들과 온라인 (빠른 매칭)", UiKit.Pink, Color.white, top, new Vector2(0, -222), new Vector2(440, 62), () => Go(() => onQuickMatch?.Invoke()), 24);
            UiKit.Btn(t, "방 만들기", UiKit.Sky, Color.white, top, new Vector2(-150, -300), new Vector2(140, 52), () => Go(() => onCreateRoom?.Invoke()), 20);
            string invited = InvitedRoom();
            _room = UiKit.Field(t, "방 코드", invited, top, new Vector2(0, -300), new Vector2(140, 52), 8);
            _room.textComponent.alignment = TextAnchor.MiddleCenter;
            UiKit.Btn(t, "입장", UiKit.Sky, Color.white, top, new Vector2(150, -300), new Vector2(140, 52), JoinPressed, 20);
            _note = UiKit.Label(t, invited != "" ? $"초대받은 방: {invited} → \"입장\"을 눌러 주세요" : "방을 만들면 나오는 코드를 친구에게 알려 주세요",
                15, UiKit.InkSoft, TextAnchor.MiddleCenter, top, new Vector2(0, -350), new Vector2(460, 24));

            UiKit.Btn(t, "혼자 광장 놀기", Color.white, UiKit.Ink, top, new Vector2(0, -396), new Vector2(440, 52), () => Play(""), 21);
            UiKit.Btn(t, "레이스 연습", Color.white, UiKit.Ink, top, new Vector2(-112, -462), new Vector2(216, 50), () => Play("obstacle_race"), 20);
            UiKit.Btn(t, "레이싱 연습", Color.white, UiKit.Ink, top, new Vector2(112, -462), new Vector2(216, 50), () => Play("racing"), 20);
            _notice = UiKit.Label(t, "", 16, new Color(0.85f, 0.3f, 0.35f), TextAnchor.MiddleCenter, new Vector2(0.5f, 0f), new Vector2(0, 12), new Vector2(460, 24));

            UiKit.Label(root, "Unity 판 (옮기는 중)", 14, new Color(1, 1, 1, 0.75f), TextAnchor.LowerRight, new Vector2(1f, 0f), new Vector2(-14, 10), new Vector2(400, 24), true);
        }

        void ApplyLook()
        {
            _look.text = $"{Appearance.ColorNames[_color]} / {Appearance.HatNames[_hat]}";
            _look.color = GameMap.Darken(Appearance.BodyColors[_color], 0.3f);
            SetLook(body, _color, _hat);
        }

        /// <summary>캐릭터 모습을 새로 만든다 (색·모자가 바뀌었을 때)</summary>
        public static void SetLook(PlayerBody body, int color, int hat)
        {
            if (body == null) return;
            Quaternion rot = body.visual != null ? body.visual.rotation : Quaternion.identity;
            if (body.visual != null) Destroy(body.visual.gameObject);
            var look = CharacterVisual.Build(color, hat);
            look.sourceBody = body;
            look.readEmoteKeys = true;
            look.transform.SetPositionAndRotation(body.InterpolatedPosition, rot);
            body.visual = look.transform;
        }

        static string Clean(string s)
        {
            s = (s ?? "").Trim();
            if (s.Length > 16) s = s.Substring(0, 16);
            return s.Length >= 2 ? s : "Player";
        }

        public bool IsOpen => _canvas.enabled;

        public void Open()
        {
            _canvas.enabled = true;
            UiKit.MenuOpen = true;
            if (body != null) body.frozen = true;
            if (GameHud.I != null) GameHud.I.SetVisible(false);
            // 내 캐릭터 얼굴이 보이게 카메라를 앞쪽으로
            if (cam != null && body != null)
            {
                cam.yaw = body.facingYaw + Mathf.PI * 0.82f;
                cam.pitch = -0.12f;
            }
        }

        /// <summary>메뉴만 닫기 (게임 진행은 그대로)</summary>
        public void Close()
        {
            _canvas.enabled = false;
            UiKit.MenuOpen = false;
            if (GameHud.I != null) GameHud.I.SetVisible(true);
        }

        /// <summary>주소의 ?room=코드 (초대 링크로 들어온 경우)</summary>
        static string InvitedRoom()
        {
            string url = Application.absoluteURL;
            int q = url.IndexOf('?');
            if (q < 0) return "";
            foreach (var part in url.Substring(q + 1).Split('&'))
            {
                var kv = part.Split('=');
                if (kv.Length == 2 && kv[0] == "room") return PartyWorld.Net.OnlineClient.NormalizeRoomCode(kv[1]);
            }
            return "";
        }

        void JoinPressed()
        {
            string code = PartyWorld.Net.OnlineClient.NormalizeRoomCode(_room.text);
            if (code == "")
            {
                SetNote("방 코드는 영문/숫자 4~8자예요", true);
                return;
            }
            Go(() => onJoinRoom?.Invoke(code));
        }

        public void SetNote(string text, bool error)
        {
            _note.text = text;
            _note.color = error ? new Color(0.85f, 0.3f, 0.35f) : UiKit.InkSoft;
        }

        /// <summary>메뉴 아래쪽 빨간 안내 (온라인이 끝난 이유 등). 빈 문자열이면 지움</summary>
        public void ShowNotice(string text) => _notice.text = text;

        /// <summary>온라인으로 가기: 닉네임 확인 후 메뉴를 닫고 실행</summary>
        void Go(System.Action action)
        {
            if (!ValidNick(Nickname))
            {
                ShowNotice("닉네임은 2~16자 한글/영문/숫자/_ 만 쓸 수 있어요");
                return;
            }
            ShowNotice("");
            Save();
            _canvas.enabled = false;
            UiKit.MenuOpen = false;
            if (body != null) body.frozen = false;
            if (GameHud.I != null) GameHud.I.SetVisible(true);
            if (cam != null && body != null) { cam.yaw = body.facingYaw; cam.pitch = -0.32f; }
            action();
        }

        /// <summary>서버와 같은 규칙 (Godot validation.gd): 2~16자, 한글·영문·숫자·_</summary>
        public static bool ValidNick(string s)
        {
            if (s == null || s.Length < 2 || s.Length > 16) return false;
            foreach (char ch in s)
            {
                bool ok = (ch >= '0' && ch <= '9') || (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || ch == '_' || (ch >= '\uAC00' && ch <= '\uD7A3');
                if (!ok) return false;
            }
            return true;
        }

        void Play(string mode)
        {
            Save();
            _canvas.enabled = false;
            UiKit.MenuOpen = false;
            if (body != null) body.frozen = false;
            if (GameHud.I != null) GameHud.I.SetVisible(true);
            if (cam != null && body != null) { cam.yaw = body.facingYaw; cam.pitch = -0.32f; }
            onPlay?.Invoke(mode);
        }
    }
}
