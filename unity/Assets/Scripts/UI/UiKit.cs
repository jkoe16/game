using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace PartyWorld
{
    /// <summary>
    /// 화면 UI 도우미 (Godot scripts/ui/ui_style.gd 의 파스텔 카툰 스타일).
    /// 씬 파일 없이 코드로 Canvas·카드·버튼·입력칸을 만든다. 기준 화면 1280×720, 휴대폰에서도 같은 비율로 커진다.
    /// </summary>
    public static class UiKit
    {
        public static readonly Color Ink = new Color(0.32f, 0.27f, 0.48f);
        public static readonly Color InkSoft = new Color(0.52f, 0.48f, 0.66f);
        public static readonly Color Pink = new Color(1f, 0.52f, 0.66f);
        public static readonly Color Sky = new Color(0.42f, 0.68f, 1f);
        public static readonly Color Mint = new Color(0.36f, 0.82f, 0.7f);
        public static readonly Color Gold = new Color(1f, 0.8f, 0.3f);
        public static readonly Color HudBg = new Color(0.16f, 0.12f, 0.32f, 0.42f);

        /// <summary>메뉴가 열려 있으면 카메라·조작이 화면 클릭을 무시한다</summary>
        public static bool MenuOpen;

        /// <summary>마우스/손가락이 UI 위에 있는지 (그때는 카메라 잠금 클릭으로 쓰지 않음)</summary>
        public static bool PointerOverUi()
        {
            if (MenuOpen) return true;
            var es = EventSystem.current;
            if (es == null) return false;
            if (es.IsPointerOverGameObject()) return true;
#if ENABLE_LEGACY_INPUT_MANAGER
            for (int i = 0; i < Input.touchCount; i++)
                if (es.IsPointerOverGameObject(Input.GetTouch(i).fingerId)) return true;
#endif
            return false;
        }

        public static Canvas MakeCanvas(string name, int order)
        {
            var go = new GameObject(name);
            Object.DontDestroyOnLoad(go);
            var canvas = go.AddComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = order;
            var scaler = go.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1280, 720);
            scaler.screenMatchMode = CanvasScaler.ScreenMatchMode.MatchWidthOrHeight;
            scaler.matchWidthOrHeight = 0.6f;
            go.AddComponent<GraphicRaycaster>();
            EnsureEventSystem();
            return canvas;
        }

        static void EnsureEventSystem()
        {
            if (EventSystem.current != null || Object.FindFirstObjectByType<EventSystem>() != null) return;
            var es = new GameObject("EventSystem");
            Object.DontDestroyOnLoad(es);
            es.AddComponent<EventSystem>();
            es.AddComponent<FocusFreeInputModule>();
        }

        static Sprite _round;
        /// <summary>둥근 모서리 흰 사각형 (9칸 늘리기)</summary>
        public static Sprite Rounded
        {
            get
            {
                if (_round != null) return _round;
                const int n = 64, r = 28;
                var tex = new Texture2D(n, n, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Bilinear };
                var px = new Color32[n * n];
                for (int y = 0; y < n; y++)
                    for (int x = 0; x < n; x++)
                    {
                        float cx = Mathf.Clamp(x + 0.5f, r, n - r), cy = Mathf.Clamp(y + 0.5f, r, n - r);
                        float d = Vector2.Distance(new Vector2(x + 0.5f, y + 0.5f), new Vector2(cx, cy));
                        byte a = (byte)(Mathf.Clamp01(r - d + 0.5f) * 255);
                        px[y * n + x] = new Color32(255, 255, 255, a);
                    }
                tex.SetPixels32(px);
                tex.Apply();
                _round = Sprite.Create(tex, new Rect(0, 0, n, n), new Vector2(0.5f, 0.5f), 100f, 0, SpriteMeshType.FullRect, new Vector4(r, r, r, r));
                return _round;
            }
        }

        /// <summary>RectTransform 자리 잡기: 기준점(anchor) + 위치 + 크기 (기준 해상도 픽셀)</summary>
        public static RectTransform Place(GameObject go, Transform parent, Vector2 anchor, Vector2 pos, Vector2 size)
        {
            var rt = go.GetComponent<RectTransform>();
            if (rt == null) rt = go.AddComponent<RectTransform>();
            rt.SetParent(parent, false);
            rt.anchorMin = rt.anchorMax = anchor;
            rt.pivot = anchor;
            rt.anchoredPosition = pos;
            rt.sizeDelta = size;
            return rt;
        }

        /// <summary>부모를 꽉 채움</summary>
        public static RectTransform Fill(GameObject go, Transform parent)
        {
            var rt = go.GetComponent<RectTransform>();
            if (rt == null) rt = go.AddComponent<RectTransform>();
            rt.SetParent(parent, false);
            rt.anchorMin = Vector2.zero;
            rt.anchorMax = Vector2.one;
            rt.offsetMin = rt.offsetMax = Vector2.zero;
            return rt;
        }

        public static Image Panel(Transform parent, Vector2 anchor, Vector2 pos, Vector2 size, Color color, float radiusScale = 1f)
        {
            var go = new GameObject("Panel");
            Place(go, parent, anchor, pos, size);
            var img = go.AddComponent<Image>();
            img.sprite = Rounded;
            img.type = Image.Type.Sliced;
            img.pixelsPerUnitMultiplier = 1f / Mathf.Max(radiusScale, 0.05f);
            img.color = color;
            return img;
        }

        public static Text Label(Transform parent, string text, int size, Color color, TextAnchor align, Vector2 anchor, Vector2 pos, Vector2 boxSize, bool outline = false)
        {
            var go = new GameObject("Text");
            Place(go, parent, anchor, pos, boxSize);
            var t = go.AddComponent<Text>();
            t.font = GameMap.UIFont;
            t.text = text;
            t.fontSize = size;
            t.color = color;
            t.alignment = align;
            t.horizontalOverflow = HorizontalWrapMode.Wrap;
            t.verticalOverflow = VerticalWrapMode.Overflow;
            t.raycastTarget = false;
            if (outline)
            {
                var o = go.AddComponent<Outline>();
                o.effectColor = new Color(0.15f, 0.12f, 0.25f, 0.85f);
                o.effectDistance = new Vector2(2f, -2f);
            }
            return t;
        }

        /// <summary>통통한 버튼: 아래쪽 진한 그림자로 입체감</summary>
        public static Button Btn(Transform parent, string text, Color bg, Color fg, Vector2 anchor, Vector2 pos, Vector2 size, System.Action onClick, int fontSize = 24)
        {
            var img = Panel(parent, anchor, pos, size, bg, 0.7f);
            img.gameObject.name = "Button: " + text;
            var sh = img.gameObject.AddComponent<Shadow>();
            sh.effectColor = bg == Color.white ? new Color(0.84f, 0.8f, 0.95f) : Color.Lerp(bg, Color.black, 0.22f);
            sh.effectDistance = new Vector2(0, -5);
            var b = img.gameObject.AddComponent<Button>();
            b.targetGraphic = img;
            var cb = b.colors;
            cb.highlightedColor = new Color(1.08f, 1.08f, 1.08f);
            cb.pressedColor = new Color(0.9f, 0.9f, 0.9f);
            cb.selectedColor = Color.white;
            b.colors = cb;
            if (onClick != null) b.onClick.AddListener(() => onClick());
            var t = Label(img.transform, text, fontSize, fg, TextAnchor.MiddleCenter, new Vector2(0.5f, 0.5f), Vector2.zero, size);
            t.fontStyle = FontStyle.Bold;
            return b;
        }

        public static InputField Field(Transform parent, string placeholder, string value, Vector2 anchor, Vector2 pos, Vector2 size, int limit = 16)
        {
            var img = Panel(parent, anchor, pos, size, new Color(0.97f, 0.96f, 1f), 0.5f);
            img.gameObject.name = "Field";
            var outline = img.gameObject.AddComponent<Outline>();
            outline.effectColor = new Color(0.82f, 0.78f, 0.95f);
            outline.effectDistance = new Vector2(2, -2);
            var f = img.gameObject.AddComponent<InputField>();
            var inner = new Vector2(size.x - 28, size.y);
            var txt = Label(img.transform, "", 24, Ink, TextAnchor.MiddleLeft, new Vector2(0.5f, 0.5f), Vector2.zero, inner);
            txt.supportRichText = false;
            var ph = Label(img.transform, placeholder, 20, new Color(0.62f, 0.6f, 0.72f), TextAnchor.MiddleLeft, new Vector2(0.5f, 0.5f), Vector2.zero, inner);
            f.textComponent = txt;
            f.placeholder = ph;
            f.characterLimit = limit;
            f.text = value;
            f.targetGraphic = img;
            return f;
        }
    }

    /// <summary>
    /// 기본 StandaloneInputModule 은 Unity 가 "창이 포커스를 잃었다"고 여기면 UI 클릭을 통째로 무시한다.
    /// 웹(숨은 탭·iframe 에서 돌아온 직후 등)에서는 그 상태가 남아 버튼이 안 눌릴 수 있어,
    /// 포커스가 없을 때도 마우스 클릭만은 처리한다. (포커스가 있으면 원래 동작 그대로)
    /// </summary>
    public class FocusFreeInputModule : StandaloneInputModule
    {
        public override void Process()
        {
            if (eventSystem.isFocused)
            {
                base.Process();
                return;
            }
            SendUpdateEventToSelectedObject();
            if (input.mousePresent)
                ProcessMouseEvent();
        }
    }
}
