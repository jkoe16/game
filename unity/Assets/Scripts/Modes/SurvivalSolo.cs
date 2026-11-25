using UnityEngine;

namespace PartyWorld
{
    /// <summary>
    /// 최후의 생존자 혼자 연습 (Godot scripts/modes/survival_mode.gd 이식).
    /// 무너지는 섬에서 2분 버티기. 목숨 2개: 처음 떨어지면 가운데로 돌아오고, 두 번째에 탈락.
    /// </summary>
    public class SurvivalSolo : SoloMode
    {
        const int Lives = 2;
        static readonly int[] StageTimes = { 27, 55, 72 };
        static readonly string[] StageText = { "섬 가장자리가 무너지기 시작해요!", "막대가 더 빨라져요! 집중!", "안쪽 타일도 무너져요! 가운데로!" };

        int _lives;
        int _stage;
        int _gustWarned = -1;
        int _outTick = -1;
        static float _best = -1f;

        public override string Title => "최후의 생존자";
        public override string RulesText => "섬이 무너져요! 흔들리는 타일을 피하고, 돌풍엔 반대로 걸어 버텨요. 빨간 막대는 점프·파란 막대는 점프 금지! 목숨 2개";

        SurvivalArena Arena => (SurvivalArena)map;

        public override void Begin(int nowTick)
        {
            roundTicks = 120 * 60;
            _lives = Lives;
            _stage = 0;
            _outTick = -1;
            Arena.crumbleStart = 0;
            base.Begin(nowTick);
        }

        protected override void OnRoundStart() => Arena.crumbleStart = roundStartTick;

        protected override void ModeTick(PlayerBody body)
        {
            int g = Arena.NextGustTick(tick);
            if (g > 0 && g - tick <= 120 && g != _gustWarned)
            {
                _gustWarned = g;
                Hud.Banner("2초 뒤 돌풍! 바람 반대쪽으로 걸어요", 2f);
            }
            if (_stage < StageTimes.Length && tick - roundStartTick >= StageTimes[_stage] * 60)
            {
                Hud.Banner(StageText[_stage], 2.5f);
                _stage++;
            }
        }

        protected override bool IsOver() => _outTick >= 0;

        public override Vector3 OnFell()
        {
            if (phase != "playing") return map.GetSpawnPoint(0);
            _lives--;
            if (_lives > 0)
            {
                Hud.Banner($"목숨 {_lives}개 남았어요", 2f);
                return SafeRespawn();
            }
            _outTick = tick - roundStartTick;
            float sec = _outTick / 60f;
            if (_best < 0f || sec > _best) _best = sec;
            return Arena.SpectatorPoint;
        }

        /// <summary>가운데 원판 위, 두 막대에서 가장 먼 지점</summary>
        Vector3 SafeRespawn()
        {
            Vector3 best = new Vector3(0, 0.5f, 3f);
            float bestD = -1f;
            for (int i = 0; i < 8; i++)
            {
                float a = Mathf.PI * 2f * i / 8f;
                var p = new Vector3(Mathf.Sin(a) * 3.2f, 0.5f, Mathf.Cos(a) * 3.2f);
                float d = float.PositiveInfinity;
                foreach (var s in map.sweepers)
                {
                    float da = map.SweeperAngle(s, tick + 30) - Mathf.Atan2(p.x, p.z);
                    d = Mathf.Min(d, Mathf.Abs(Mathf.DeltaAngle(0, da * Mathf.Rad2Deg)));
                    if (s.arms == 2) d = Mathf.Min(d, Mathf.Abs(Mathf.DeltaAngle(0, da * Mathf.Rad2Deg + 180f)));
                }
                if (d > bestD) { bestD = d; best = p; }
            }
            return best;
        }

        protected override string ResultText()
        {
            if (_outTick < 0) return $"생존 성공! 목숨 {_lives}개 남음";
            return $"탈락! {_outTick / 60f:0.0}초 버팀\n최고 기록 {_best:0.0}초";
        }

        protected override string SubText => $"목숨 {new string('♥', Mathf.Max(_lives, 0))}";
    }
}
