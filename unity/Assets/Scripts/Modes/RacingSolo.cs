using UnityEngine;

namespace PartyWorld
{
    /// <summary>
    /// 레이싱 혼자 연습 (Godot scripts/modes/racing_mode.gd 이식). 순환 트랙 3바퀴.
    /// 체크포인트를 순서대로 통과해야 바퀴가 인정된다(지름길 방지). 30초·60초에 새 장애물.
    /// </summary>
    public class RacingSolo : SoloMode
    {
        const int Laps = 3;
        int _lap;
        int _nextCp;
        int _finishTick = -1;
        static float _best = -1f;

        public override string Title => "레이싱";
        public override string RulesText => $"트랙 {Laps}바퀴! 부스터·점프대·지름길 다리를 노려요. 시간이 지나면 장애물이 늘어나요";

        RaceTrack Track => (RaceTrack)map;

        public override void Begin(int nowTick)
        {
            roundTicks = 180 * 60;
            _lap = 0;
            _nextCp = 1;
            _finishTick = -1;
            base.Begin(nowTick);
        }

        protected override void ModeTick(PlayerBody body)
        {
            int el = tick - roundStartTick;
            if (el == (int)(RaceTrack.Stage2Sec * 60)) Hud.Banner("2단계! 골목에서 공이 굴러와요", 2.5f);
            else if (el == (int)(RaceTrack.Stage3Sec * 60)) Hud.Banner("3단계! 동쪽 직선에 밀어내는 벽 등장", 2.5f);
            if (_finishTick >= 0 || !Track.InCheckpoint(body.transform.position, _nextCp)) return;
            if (_nextCp == 0)
            {
                _lap++;
                if (_lap >= Laps)
                {
                    _finishTick = el;
                    float sec = el / 60f;
                    if (_best < 0f || sec < _best) _best = sec;
                }
                else if (_lap == Laps - 1) Hud.Banner("마지막 바퀴!", 2f);
                else Hud.Banner($"{_lap + 1}바퀴째", 2f);
            }
            _nextCp = (_nextCp + 1) % RaceTrack.Checkpoints.Length;
        }

        protected override bool IsOver() => _finishTick >= 0;

        public override Vector3 OnFell()
        {
            int n = RaceTrack.Checkpoints.Length;
            return Track.CheckpointPoint(((_nextCp - 1) % n + n) % n);
        }

        protected override string ResultText()
        {
            if (_finishTick < 0) return $"시간 초과! {Mathf.Min(_lap + 1, Laps)}/{Laps} 바퀴";
            return $"완주 {_finishTick / 60f:0.0}초\n최고 기록 {_best:0.0}초";
        }

        protected override void OnGUI()
        {
            base.OnGUI();
            if (phase != "playing") return;
            float s = Screen.height / 720f;
            Hud.Shadowed(new Rect(0, 48 * s, Screen.width, 36 * s), $"{ElapsedSec:0.0}초   {Mathf.Min(_lap + 1, Laps)}/{Laps} 바퀴",
                Hud.Style(Mathf.RoundToInt(22 * s), TextAnchor.UpperCenter));
        }
    }
}
