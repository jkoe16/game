using UnityEngine;

namespace PartyWorld
{
    /// <summary>
    /// 혼자 연습하는 미니게임의 공통 흐름 (Godot game_mode.gd 의 라운드 흐름을 1인용으로 줄임).
    /// countdown(출발선, 이동 금지 3초) → playing → results(결과 표시 후 광장으로).
    /// 온라인 단계에서 서버 모드로 바뀌어도 맵·판정 코드는 그대로 쓴다.
    /// </summary>
    public abstract class SoloMode : MonoBehaviour
    {
        public const int CountdownTicks = 3 * 60;
        public const int ResultsTicks = 6 * 60;

        public GameSession session;
        public GameMap map;
        public string phase = "countdown";
        public int phaseEndTick;
        public int roundStartTick;
        protected int tick;
        protected int roundTicks = 150 * 60;

        public abstract string Title { get; }
        public abstract string RulesText { get; }
        /// <summary>결과 화면 한 줄 (예: "완주 42.3초")</summary>
        protected abstract string ResultText();
        protected abstract void ModeTick(PlayerBody body);
        protected abstract bool IsOver();
        /// <summary>떨어졌을 때 다시 나올 곳</summary>
        public abstract Vector3 OnFell();

        /// <summary>카운트다운이 끝나고 달리기 시작하는 순간</summary>
        protected virtual void OnRoundStart() { }

        public virtual void Begin(int nowTick)
        {
            tick = nowTick;
            phase = "countdown";
            phaseEndTick = nowTick + CountdownTicks;
            // 라운드 시작 틱을 미리 정해 두면 가속 장애물이 처음부터 정확하다
            roundStartTick = phaseEndTick;
            map.roundStartTick = roundStartTick;
            session.body.Teleport(map.GetStartPoint(0));
            session.body.frozen = true;
            Hud.Banner(Title, 3f);
        }

        public void Tick(int t, PlayerBody body)
        {
            tick = t;
            switch (phase)
            {
                case "countdown":
                    body.frozen = true;
                    if (t >= phaseEndTick)
                    {
                        phase = "playing";
                        phaseEndTick = t + roundTicks;
                        body.frozen = false;
                        Hud.Banner("출발!", 1.2f);
                        OnRoundStart();
                    }
                    break;
                case "playing":
                    ModeTick(body);
                    if (IsOver() || t >= phaseEndTick) EndRound(body);
                    break;
                case "results":
                    if (t >= phaseEndTick) session.LoadLobby();
                    break;
            }
        }

        void EndRound(PlayerBody body)
        {
            phase = "results";
            phaseEndTick = tick + ResultsTicks;
            body.frozen = true;
        }

        /// <summary>남은 시간(초) 또는 카운트다운 숫자</summary>
        public float SecondsLeft => Mathf.Max(0, phaseEndTick - tick) / 60f;
        public float ElapsedSec => Mathf.Max(0, tick - roundStartTick) / 60f;

        protected virtual void OnGUI()
        {
            float s = Screen.height / 720f;
            var big = Hud.Style(Mathf.RoundToInt(96 * s), TextAnchor.MiddleCenter);
            var mid = Hud.Style(Mathf.RoundToInt(26 * s), TextAnchor.UpperCenter);
            if (phase == "countdown")
            {
                int n = Mathf.CeilToInt(SecondsLeft);
                Hud.Shadowed(new Rect(0, Screen.height * 0.3f, Screen.width, 140 * s), n > 0 ? n.ToString() : "", big);
                Hud.Shadowed(new Rect(Screen.width * 0.1f, Screen.height * 0.3f + 140 * s, Screen.width * 0.8f, 80 * s), RulesText, mid);
            }
            else if (phase == "playing")
            {
                int left = Mathf.CeilToInt(SecondsLeft);
                Hud.Shadowed(new Rect(0, 12 * s, Screen.width, 40 * s), $"{Title}   {left / 60}:{left % 60:00}", mid);
            }
            else if (phase == "results")
            {
                Hud.Shadowed(new Rect(0, Screen.height * 0.32f, Screen.width, 120 * s), ResultText(), Hud.Style(Mathf.RoundToInt(64 * s), TextAnchor.MiddleCenter));
                Hud.Shadowed(new Rect(0, Screen.height * 0.32f + 120 * s, Screen.width, 50 * s), $"{Mathf.CeilToInt(SecondsLeft)}초 뒤 광장으로 돌아가요", mid);
            }
        }
    }

    /// <summary>화면 글자 도우미 (한글 글꼴 사용). 가운데 위 알림도 여기서.</summary>
    public static class Hud
    {
        static string _banner;
        static float _bannerUntil;

        public static void Banner(string text, float seconds = 2f)
        {
            _banner = text;
            _bannerUntil = Time.time + seconds;
        }

        public static GUIStyle Style(int size, TextAnchor anchor)
        {
            var st = new GUIStyle(GUI.skin.label) { font = GameMap.UIFont, fontSize = size, alignment = anchor, wordWrap = true, fontStyle = FontStyle.Bold };
            st.normal.textColor = Color.white;
            return st;
        }

        public static void Shadowed(Rect r, string text, GUIStyle st)
        {
            if (string.IsNullOrEmpty(text)) return;
            var c = st.normal.textColor;
            st.normal.textColor = new Color(0.15f, 0.12f, 0.25f, 0.85f);
            float o = Mathf.Max(2f, st.fontSize * 0.06f);
            GUI.Label(new Rect(r.x + o, r.y + o, r.width, r.height), text, st);
            st.normal.textColor = c;
            GUI.Label(r, text, st);
        }

        /// <summary>가운데 위 알림 (GameSession 의 OnGUI 가 그린다)</summary>
        public static void DrawBanner()
        {
            if (_banner == null || Time.time > _bannerUntil) return;
            float s = Screen.height / 720f;
            Shadowed(new Rect(0, Screen.height * 0.16f, Screen.width, 80 * s), _banner, Style(Mathf.RoundToInt(48 * s), TextAnchor.MiddleCenter));
        }
    }
}
