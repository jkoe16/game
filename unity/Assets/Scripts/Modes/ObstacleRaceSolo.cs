using UnityEngine;

namespace PartyWorld
{
    /// <summary>
    /// 장애물 레이스 혼자 연습 (Godot scripts/modes/obstacle_race_mode.gd 이식).
    /// 결승선을 통과하면 완주 시간 기록. 떨어지면 마지막 체크포인트에서 재출발(벌칙 없음).
    /// ? 상자(방해 아이템)는 여러 명이 함께하는 온라인 단계에서 붙인다.
    /// </summary>
    public class ObstacleRaceSolo : SoloMode
    {
        int _checkpoint;
        float _progress;
        int _finishTick = -1;
        static float _best = -1f;

        public override string Title => "장애물 레이스";
        public override string RulesText => "공은 점프로 넘고, 주먹 벽과 사라지는 발판을 조심! 떨어지면 체크포인트부터";

        RaceCourse Course => (RaceCourse)map;

        public override void Begin(int nowTick)
        {
            _checkpoint = 0;
            _progress = 0f;
            _finishTick = -1;
            base.Begin(nowTick);
        }

        protected override void ModeTick(PlayerBody body)
        {
            Vector3 pos = body.transform.position;
            int cp = Course.CheckpointIndexAt(pos);
            if (cp > _checkpoint)
            {
                _checkpoint = cp;
                Hud.Banner($"체크포인트 {cp}/{RaceCourse.Checkpoints.Length - 1}", 1.5f);
            }
            _progress = Mathf.Max(_progress, Mathf.Clamp01(pos.z / RaceCourse.FinishZ));
            if (_finishTick < 0 && Course.IsFinished(pos))
            {
                _finishTick = tick - roundStartTick;
                _progress = 1f;
                float sec = _finishTick / 60f;
                if (_best < 0f || sec < _best) _best = sec;
            }
        }

        protected override bool IsOver() => _finishTick >= 0;

        public override Vector3 OnFell() => Course.CheckpointPoint(_checkpoint);

        protected override string ResultText()
        {
            if (_finishTick < 0) return $"시간 초과! 진행 {(int)(_progress * 100)}%";
            return $"완주 {_finishTick / 60f:0.0}초\n최고 기록 {_best:0.0}초";
        }

        protected override string SubText => $"{ElapsedSec:0.0}초   진행 {(int)(_progress * 100)}%";
    }
}
