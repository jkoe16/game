using UnityEngine;
using UnityEngine.UI;

namespace PartyWorld
{
    /// <summary>
    /// 게임 화면 HUD (Godot scripts/ui/hud.gd 이식): 위쪽 제목·남은 시간, 그 아래 진행·점수,
    /// 가운데 큰 글자(카운트다운, 톡 튀어나오는 연출), 알림, 결과 카드, 포털 입장 막대, 메뉴·나가기 버튼, 조작 안내.
    /// </summary>
    public class GameHud : MonoBehaviour
    {
        public static GameHud I;

        public System.Action onExit, onMenu;

        Text _top, _sub, _big, _rules, _banner, _help, _status, _board;
        Image _boardBg;
        Text _exitText;
        Image _topBg;
        GameObject _results;
        Text _resultTitle, _resultBody, _resultFoot;
        GameObject _hold;
        Image _holdFill;
        Text _holdText;
        Button _exit, _menu;
        float _bannerUntil, _bigPop;
        string _bigText = "";

        public static GameHud Create()
        {
            var canvas = UiKit.MakeCanvas("GameHud", 10);
            var hud = canvas.gameObject.AddComponent<GameHud>();
            I = hud;
            hud.Build(canvas.transform);
            return hud;
        }

        void Build(Transform root)
        {
            var top = new Vector2(0.5f, 1f);
            _topBg = UiKit.Panel(root, top, new Vector2(0, -10), new Vector2(520, 84), UiKit.HudBg, 0.6f);
            _top = UiKit.Label(_topBg.transform, "", 30, Color.white, TextAnchor.UpperCenter, top, new Vector2(0, -8), new Vector2(500, 40));
            _top.fontStyle = FontStyle.Bold;
            _sub = UiKit.Label(_topBg.transform, "", 22, new Color(1f, 0.95f, 0.75f), TextAnchor.UpperCenter, top, new Vector2(0, -46), new Vector2(500, 32));

            var mid = new Vector2(0.5f, 0.5f);
            _big = UiKit.Label(root, "", 120, Color.white, TextAnchor.MiddleCenter, mid, new Vector2(0, 90), new Vector2(1000, 160), true);
            _big.fontStyle = FontStyle.Bold;
            _rules = UiKit.Label(root, "", 26, Color.white, TextAnchor.UpperCenter, mid, new Vector2(0, -10), new Vector2(900, 120), true);
            _banner = UiKit.Label(root, "", 44, new Color(1f, 0.95f, 0.6f), TextAnchor.MiddleCenter, new Vector2(0.5f, 0.78f), Vector2.zero, new Vector2(1100, 70), true);
            _banner.fontStyle = FontStyle.Bold;

            // 결과 카드
            var card = UiKit.Panel(root, mid, new Vector2(0, 20), new Vector2(560, 300), new Color(1, 1, 1, 0.96f));
            _results = card.gameObject;
            _resultTitle = UiKit.Label(card.transform, "", 40, UiKit.Pink, TextAnchor.UpperCenter, top, new Vector2(0, -28), new Vector2(520, 56));
            _resultTitle.fontStyle = FontStyle.Bold;
            _resultBody = UiKit.Label(card.transform, "", 34, UiKit.Ink, TextAnchor.UpperCenter, top, new Vector2(0, -100), new Vector2(520, 120));
            _resultFoot = UiKit.Label(card.transform, "", 20, UiKit.InkSoft, TextAnchor.LowerCenter, new Vector2(0.5f, 0f), new Vector2(0, 24), new Vector2(520, 30));
            _results.SetActive(false);

            // 포털 입장 막대
            var holdBg = UiKit.Panel(root, new Vector2(0.5f, 0.3f), Vector2.zero, new Vector2(340, 20), new Color(0, 0, 0, 0.35f), 0.35f);
            _hold = holdBg.gameObject;
            _holdFill = UiKit.Panel(holdBg.transform, new Vector2(0f, 0.5f), Vector2.zero, new Vector2(0, 20), UiKit.Gold, 0.35f);
            _holdText = UiKit.Label(holdBg.transform, "", 26, Color.white, TextAnchor.LowerCenter, new Vector2(0.5f, 1f), new Vector2(0, 8), new Vector2(600, 40), true);
            _holdText.rectTransform.pivot = new Vector2(0.5f, 0f);
            _hold.SetActive(false);

            _exit = UiKit.Btn(root, "광장으로", Color.white, UiKit.Ink, new Vector2(1f, 1f), new Vector2(-14, -14), new Vector2(150, 52), () => onExit?.Invoke(), 21);
            _exitText = _exit.GetComponentInChildren<Text>();

            // 온라인: 함께 있는 사람·접속 상태 (위 가운데 아래), 점수판 (오른쪽)
            _status = UiKit.Label(root, "", 18, Color.white, TextAnchor.UpperLeft, new Vector2(0f, 1f), new Vector2(130, -24), new Vector2(760, 60), true);
            _boardBg = UiKit.Panel(root, new Vector2(1f, 1f), new Vector2(-14, -80), new Vector2(300, 40), UiKit.HudBg, 0.5f);
            _board = UiKit.Label(_boardBg.transform, "", 20, Color.white, TextAnchor.UpperLeft, new Vector2(0.5f, 1f), new Vector2(0, -10), new Vector2(270, 300));
            _boardBg.gameObject.SetActive(false);
            _menu = UiKit.Btn(root, "메뉴", Color.white, UiKit.Ink, new Vector2(0f, 1f), new Vector2(14, -14), new Vector2(100, 52), () => onMenu?.Invoke(), 21);

            bool touch = Application.isMobilePlatform;
            string help = touch ? "왼쪽: 이동 · 오른쪽 끌기: 시점 · 버튼: 점프"
                                : "WASD 이동 · Space 점프 · Shift 걷기 · 클릭: 시점 잠금 (Esc 풀기) · 1~4 감정표현";
            _help = UiKit.Label(root, help, 18, new Color(1, 1, 1, 0.85f), TextAnchor.LowerLeft, new Vector2(0f, 0f), new Vector2(16, 12), new Vector2(900, 30), true);
            SetTop("", "");
            ShowExit(false);
        }

        // ------------------------------------------------------------------ 바깥에서 쓰는 API

        public void SetTop(string title, string sub)
        {
            _top.text = title;
            _sub.text = sub;
            _topBg.gameObject.SetActive(!string.IsNullOrEmpty(title));
            _topBg.rectTransform.sizeDelta = new Vector2(520, string.IsNullOrEmpty(sub) ? 52 : 84);
        }

        /// <summary>가운데 큰 글자. 바뀔 때마다 톡 튀어나온다</summary>
        public void SetBig(string text, string rules = "")
        {
            if (text != _bigText)
            {
                _bigText = text;
                _big.text = text;
                _bigPop = 1f;
            }
            _rules.text = rules;
        }

        public void Banner(string text, float seconds)
        {
            _banner.text = text;
            _bannerUntil = Time.time + seconds;
            _banner.rectTransform.localScale = Vector3.one * 1.25f;
        }

        public void ShowResults(string title, string body, string foot)
        {
            _results.SetActive(true);
            _resultTitle.text = title;
            _resultBody.text = body;
            _resultFoot.text = foot;
        }

        public void HideResults() => _results.SetActive(false);

        /// <summary>포털 입장 대기 (frac &lt; 0 이면 숨김)</summary>
        public void SetHold(string name, float frac)
        {
            bool show = frac >= 0f;
            if (_hold.activeSelf != show) _hold.SetActive(show);
            if (!show) return;
            _holdFill.rectTransform.sizeDelta = new Vector2(340 * Mathf.Clamp01(frac), 20);
            _holdText.text = $"{name} 입장 중…";
        }

        public void ShowExit(bool show) => ShowExit(show, "광장으로");

        public void ShowExit(bool show, string label)
        {
            if (_exit.gameObject.activeSelf != show) _exit.gameObject.SetActive(show);
            if (_exitText != null && _exitText.text != label) _exitText.text = label;
        }

        /// <summary>왼쪽 위 작은 글자 (온라인 접속 상태, 함께 있는 사람)</summary>
        public void SetStatus(string text)
        {
            if (_status.text != text) _status.text = text;
        }

        /// <summary>오른쪽 점수판 (빈 문자열이면 숨김)</summary>
        public void SetBoard(string text)
        {
            bool show = !string.IsNullOrEmpty(text);
            if (_boardBg.gameObject.activeSelf != show) _boardBg.gameObject.SetActive(show);
            if (!show || _board.text == text) return;
            _board.text = text;
            int lines = text.Split('\n').Length;
            _boardBg.rectTransform.sizeDelta = new Vector2(300, 20 + lines * 26);
        }

        public void SetVisible(bool show) => gameObject.GetComponent<Canvas>().enabled = show;

        void Update()
        {
            bool bannerOn = Time.time < _bannerUntil;
            if (_banner.enabled != bannerOn) _banner.enabled = bannerOn;
            if (bannerOn)
                _banner.rectTransform.localScale = Vector3.Lerp(_banner.rectTransform.localScale, Vector3.one, 1f - Mathf.Exp(-12f * Time.deltaTime));
            if (_bigPop > 0f)
            {
                _bigPop = Mathf.Max(0f, _bigPop - Time.deltaTime * 4f);
                _big.rectTransform.localScale = Vector3.one * (1f + 0.45f * _bigPop * _bigPop);
            }
        }
    }

    /// <summary>모드 코드에서 쓰는 짧은 알림 (가운데 위)</summary>
    public static class Hud
    {
        public static void Banner(string text, float seconds = 2f)
        {
            if (GameHud.I != null) GameHud.I.Banner(text, seconds);
        }
    }
}
