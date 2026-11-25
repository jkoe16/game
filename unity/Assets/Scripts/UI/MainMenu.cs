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
        InputField _nick;
        Text _look;
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
            var card = UiKit.Panel(root, new Vector2(1f, 0.5f), new Vector2(-60, -30), new Vector2(500, 430), new Color(1, 1, 1, 0.96f));
            var t = card.transform;
            var top = new Vector2(0.5f, 1f);
            UiKit.Label(t, "닉네임", 20, UiKit.InkSoft, TextAnchor.MiddleLeft, top, new Vector2(0, -26), new Vector2(440, 28));
            string saved = PlayerPrefs.GetString("nick", "");
            _nick = UiKit.Field(t, "닉네임 (2~16자)", saved != "" ? saved : "Player" + Random.Range(0, 1000), top, new Vector2(0, -60), new Vector2(440, 56));

            UiKit.Label(t, "외형", 20, UiKit.InkSoft, TextAnchor.MiddleLeft, top, new Vector2(0, -132), new Vector2(440, 28));
            _look = UiKit.Label(t, "", 24, UiKit.Ink, TextAnchor.MiddleLeft, top, new Vector2(-50, -166), new Vector2(340, 50));
            _look.fontStyle = FontStyle.Bold;
            UiKit.Btn(t, "색상", Color.white, UiKit.Ink, top, new Vector2(110, -164), new Vector2(96, 48), () => { _color = (_color + 1) % Appearance.BodyColors.Length; ApplyLook(); }, 20);
            UiKit.Btn(t, "모자", Color.white, UiKit.Ink, top, new Vector2(200, -164), new Vector2(76, 48), () => { _hat = (_hat + 1) % Appearance.Hats.Length; ApplyLook(); }, 20);

            UiKit.Btn(t, "광장으로 놀러 가기", UiKit.Pink, Color.white, top, new Vector2(0, -242), new Vector2(440, 66), () => Play(""), 26);
            UiKit.Btn(t, "레이스 연습", Color.white, UiKit.Ink, top, new Vector2(-112, -326), new Vector2(216, 56), () => Play("obstacle_race"), 21);
            UiKit.Btn(t, "레이싱 연습", Color.white, UiKit.Ink, top, new Vector2(112, -326), new Vector2(216, 56), () => Play("racing"), 21);
            UiKit.Label(t, "친구와 함께하는 온라인 플레이는 곧 열려요 (지금은 혼자 연습)", 16, UiKit.InkSoft, TextAnchor.MiddleCenter, new Vector2(0.5f, 0f), new Vector2(0, 18), new Vector2(460, 26));

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
