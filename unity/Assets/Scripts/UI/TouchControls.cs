using System.Collections.Generic;
using UnityEngine;
#if ENABLE_INPUT_SYSTEM
using UnityEngine.InputSystem;
#endif

namespace PartyWorld
{
    /// <summary>
    /// 모바일 터치 조작 (Godot scripts/ui/touch_controls.gd 이식).
    ///  - 화면 왼쪽 절반 아무 곳이나 누르면 그 자리에 가상 조이스틱 (기울기 = 속도, 최대 1)
    ///  - 오른쪽 화면 드래그 = 카메라 회전, 두 손가락 벌리기/모으기 = 줌
    ///  - 오른쪽 아래 큰 점프 버튼
    /// 크기는 화면 높이에 맞춰 비율로 정한다 (Godot 판 기준 높이 720px).
    /// </summary>
    public class TouchControls : MonoBehaviour
    {
        const float JoyRadiusRef = 110f;
        const float DeadZone = 0.12f;
        const float ButtonRadiusRef = 70f;

        public LocalPlayerController controller;
        public ThirdPersonCamera cam;

        int _joyId = -1;
        Vector2 _joyCenter, _joyPos;
        readonly Dictionary<int, Vector2> _camTouches = new Dictionary<int, Vector2>();
        float _pinchDist;
        Texture2D _circle;

        float Scale => Screen.height / 720f;
        float JoyRadius => JoyRadiusRef * Scale;
        float ButtonRadius => ButtonRadiusRef * Scale;
        // 화면 좌표(아래가 0)
        Vector2 JumpCenter => new Vector2(Screen.width - 130f * Scale, 150f * Scale);

        struct T { public int id; public Vector2 pos; public bool began, ended; }

        void Awake()
        {
            _circle = MakeCircle(128);
        }

        List<T> ReadTouches()
        {
            var list = new List<T>();
#if ENABLE_INPUT_SYSTEM
            var ts = Touchscreen.current;
            if (ts == null) return list;
            foreach (var t in ts.touches)
            {
                var ph = t.phase.ReadValue();
                if (ph == UnityEngine.InputSystem.TouchPhase.None) continue;
                list.Add(new T
                {
                    id = t.touchId.ReadValue(),
                    pos = t.position.ReadValue(),
                    began = ph == UnityEngine.InputSystem.TouchPhase.Began,
                    ended = ph == UnityEngine.InputSystem.TouchPhase.Ended || ph == UnityEngine.InputSystem.TouchPhase.Canceled,
                });
            }
#else
            foreach (var t in Input.touches)
                list.Add(new T
                {
                    id = t.fingerId, pos = t.position,
                    began = t.phase == UnityEngine.TouchPhase.Began,
                    ended = t.phase == UnityEngine.TouchPhase.Ended || t.phase == UnityEngine.TouchPhase.Canceled,
                });
#endif
            return list;
        }

        void Update()
        {
            if (UiKit.MenuOpen) return;
            foreach (var t in ReadTouches())
            {
                if (t.began)
                {
                    if (Vector2.Distance(t.pos, JumpCenter) < ButtonRadius * 1.3f)
                    {
                        if (controller) controller.externalJump = true;
                    }
                    else if (t.pos.x < Screen.width * 0.5f && _joyId < 0)
                    {
                        _joyId = t.id;
                        _joyCenter = _joyPos = t.pos;
                    }
                    else if (t.pos.x >= Screen.width * 0.5f)
                    {
                        _camTouches[t.id] = t.pos;
                        _pinchDist = 0f;
                    }
                    continue;
                }
                if (t.ended)
                {
                    if (t.id == _joyId) { _joyId = -1; }
                    _camTouches.Remove(t.id);
                    _pinchDist = 0f;
                    continue;
                }
                if (t.id == _joyId)
                {
                    _joyPos = t.pos;
                }
                else if (_camTouches.TryGetValue(t.id, out Vector2 last))
                {
                    if (_camTouches.Count == 1 && cam)
                    {
                        Vector2 d = t.pos - last;
                        // 화면 좌표는 위가 +y → Godot 픽셀 방향(아래가 +y)으로 맞춘다
                        cam.RotateBy(new Vector2(d.x, -d.y) / Scale, cam.touchSensitivity);
                    }
                    _camTouches[t.id] = t.pos;
                }
            }

            if (_camTouches.Count == 2 && cam)
            {
                var e = _camTouches.Values.GetEnumerator();
                e.MoveNext(); Vector2 a = e.Current; e.MoveNext(); Vector2 b = e.Current;
                float dist = Vector2.Distance(a, b);
                if (_pinchDist > 0f) cam.Zoom((_pinchDist - dist) * 0.02f / Scale);
                _pinchDist = dist;
            }

            Vector2 move = Vector2.zero;
            if (_joyId >= 0)
            {
                Vector2 off = (_joyPos - _joyCenter) / JoyRadius;
                if (off.magnitude > DeadZone) move = Vector2.ClampMagnitude(off, 1f);
            }
            if (controller) controller.externalMove = move; // 화면 위 = 앞
        }

        void OnGUI()
        {
            if (UiKit.MenuOpen) return;
            // GUI 좌표는 위가 0 → y 뒤집기
            Color old = GUI.color;
            Vector2 jc = JumpCenter;
            GUI.color = new Color(1f, 1f, 1f, 0.35f);
            DrawCircle(new Vector2(jc.x, Screen.height - jc.y), ButtonRadius);
            if (_joyId >= 0)
            {
                DrawCircle(new Vector2(_joyCenter.x, Screen.height - _joyCenter.y), JoyRadius);
                Vector2 knob = _joyCenter + Vector2.ClampMagnitude(_joyPos - _joyCenter, JoyRadius);
                GUI.color = new Color(1f, 1f, 1f, 0.7f);
                DrawCircle(new Vector2(knob.x, Screen.height - knob.y), JoyRadius * 0.4f);
            }
            GUI.color = old;
        }

        void DrawCircle(Vector2 center, float r)
        {
            GUI.DrawTexture(new Rect(center.x - r, center.y - r, r * 2f, r * 2f), _circle);
        }

        static Texture2D MakeCircle(int size)
        {
            var tex = new Texture2D(size, size, TextureFormat.RGBA32, false);
            float r = size * 0.5f;
            for (int y = 0; y < size; y++)
                for (int x = 0; x < size; x++)
                {
                    float d = Vector2.Distance(new Vector2(x + 0.5f, y + 0.5f), new Vector2(r, r));
                    tex.SetPixel(x, y, new Color(1f, 1f, 1f, Mathf.Clamp01(r - d)));
                }
            tex.Apply();
            return tex;
        }
    }
}
