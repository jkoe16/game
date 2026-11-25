using UnityEngine;

namespace PartyWorld
{
    /// <summary>캐릭터 외형 카탈로그 (Godot scripts/systems/appearance.gd). 외형은 번호로만 주고받는다.</summary>
    public static class Appearance
    {
        public static readonly Color[] BodyColors =
        {
            new Color(1.00f, 0.66f, 0.74f),  // 딸기우유
            new Color(0.55f, 0.80f, 1.00f),  // 하늘
            new Color(1.00f, 0.85f, 0.40f),  // 바나나
            new Color(0.60f, 0.90f, 0.60f),  // 민트
            new Color(0.78f, 0.65f, 1.00f),  // 라벤더
            new Color(1.00f, 0.62f, 0.40f),  // 귤
            new Color(0.95f, 0.95f, 0.95f),  // 구름
            new Color(0.45f, 0.45f, 0.55f),  // 먹구름
            new Color(0.95f, 0.38f, 0.45f),  // 체리
            new Color(0.40f, 0.86f, 0.86f),  // 소다
            new Color(0.66f, 0.47f, 0.36f),  // 초코
            new Color(0.80f, 0.94f, 0.40f),  // 라임
        };
        public static readonly string[] ColorNames = { "딸기우유", "하늘", "바나나", "민트", "라벤더", "귤", "구름", "먹구름", "체리", "소다", "초코", "라임" };
        /// <summary>새 항목은 뒤에만 추가 (저장된 프로필이 번호로 가리킴)</summary>
        public static readonly string[] Hats = { "sprout", "none", "cap", "crown", "bow", "cat", "bunny", "flower" };
        public static readonly string[] HatNames = { "새싹", "없음", "캡모자", "왕관", "리본", "고양이 귀", "토끼 귀", "꽃 핀" };
        public static readonly string[] Emotes = { "wave", "dance", "victory", "defeat" };

        public static int SanitizeColor(int c) => c >= 0 && c < BodyColors.Length ? c : 0;
        public static int SanitizeHat(int h) => h >= 0 && h < Hats.Length ? h : 0;
    }
}
