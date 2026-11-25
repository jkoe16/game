using UnityEngine;

namespace PartyWorld
{
    /// <summary>
    /// 한 물리 틱 동안의 플레이어 입력 (Godot scripts/networking/player_input.gd 이식).
    /// 이동값은 -127..127 정수로 양자화되어 클라이언트 예측과 서버 시뮬레이션이 같은 값을 쓴다.
    /// 좌표: Unity 기준 +X 오른쪽, +Z 앞. (Godot은 -Z가 앞이었다.)
    /// </summary>
    public struct PlayerInput
    {
        public const int FlagJump = 1;
        public const int FlagInteract = 2;
        public const int ValidFlags = FlagJump | FlagInteract;
        public const int Quant = 127;

        public uint seq;
        public sbyte moveX;
        public sbyte moveZ;
        public bool jump;
        public bool interact;

        public void SetMove(Vector2 v)
        {
            Vector2 m = Vector2.ClampMagnitude(v, 1f);
            moveX = (sbyte)Mathf.Clamp(Mathf.RoundToInt(m.x * Quant), -Quant, Quant);
            moveZ = (sbyte)Mathf.Clamp(Mathf.RoundToInt(m.y * Quant), -Quant, Quant);
        }

        /// <summary>항상 길이 1 이하 (위조된 값도 여기서 제한됨). x = 월드 X, y = 월드 Z.</summary>
        public Vector2 GetMove()
        {
            return Vector2.ClampMagnitude(new Vector2(moveX / (float)Quant, moveZ / (float)Quant), 1f);
        }

        public byte Flags => (byte)((jump ? FlagJump : 0) | (interact ? FlagInteract : 0));
    }
}
