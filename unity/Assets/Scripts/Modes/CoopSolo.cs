using UnityEngine;

namespace PartyWorld
{
    /// <summary>
    /// 협동 미션 혼자 연습 (Godot scripts/modes/coop_mode.gd 이식).
    /// 발판을 필요한 수만큼 동시에 밟고 버티면 문이 열린다. 혼자면 1개 (여럿이면 인원 수, 최대 4).
    /// 방이 깊어질수록 더 오래 버텨야 한다 (1초 → 1.5초 → 2초). 3단계 클리어 = 성공.
    /// </summary>
    public class CoopSolo : SoloMode
    {
        const int HoldTicks = 60;
        const int Required = 1;
        int _stage;
        int _hold;
        bool _success;
        int _clearTick;
        readonly bool[] _occ = new bool[4];

        public override string Title => "협동 미션";
        public override string RulesText => $"주황 발판 {Required}개를 밟고 버티면 문이 열려요! 2·3번 방은 막대를 점프로 넘으며 버티기";

        CoopRooms Rooms => (CoopRooms)map;

        public override void Begin(int nowTick)
        {
            roundTicks = 180 * 60;
            _stage = 0;
            _hold = 0;
            _success = false;
            for (int i = 0; i < Rooms.gates.Count; i++) Rooms.SetGateOpen(i, false);
            Rooms.ShowPlates(0, null);
            base.Begin(nowTick);
        }

        protected override void ModeTick(PlayerBody body)
        {
            if (_stage >= Rooms.stagePlates.Count) return;
            var plates = Rooms.stagePlates[_stage];
            Vector3 pos = body.transform.position;
            int count = 0;
            for (int k = 0; k < plates.Length; k++)
            {
                Vector3 p = plates[k];
                // 발판 위에서 점프해도 인정
                _occ[k] = new Vector2(pos.x - p.x, pos.z - p.z).magnitude <= CoopRooms.PlateRadius && pos.y - p.y > -0.5f && pos.y - p.y < 2.5f;
                if (_occ[k]) count++;
            }
            Rooms.ShowPlates(_stage, _occ);
            _hold = count >= Required ? _hold + 1 : 0;
            if (_hold >= HoldTicks + _stage * 30)
            {
                Rooms.SetGateOpen(_stage, true);
                _stage++;
                _hold = 0;
                Rooms.ShowPlates(_stage, null);
                if (_stage >= Rooms.stagePlates.Count)
                {
                    _success = true;
                    _clearTick = tick - roundStartTick;
                }
                else Hud.Banner($"{_stage}번 문 열림! 다음 방으로", 2f);
            }
        }

        protected override bool IsOver() => _success;

        public override Vector3 OnFell() => Rooms.StageStart(_stage);

        protected override string ResultText() => _success ? $"성공! {_clearTick / 60f:0}초" : $"시간 초과! {_stage}/3 단계";

        protected override string SubText
        {
            get
            {
                if (_stage >= 3) return "";
                int need = HoldTicks + _stage * 30;
                return _hold > 0 ? $"{_stage + 1}번 방   버티기 {(need - _hold) / 60f:0.0}초" : $"{_stage + 1}번 방";
            }
        }
    }
}
