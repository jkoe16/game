using System.Collections.Generic;
using UnityEngine;

namespace PartyWorld
{
    /// <summary>
    /// 보물 수집 혼자 연습 (Godot scripts/modes/party_coins_mode.gd 이식). 2분 동안 점수 모으기.
    /// 금화 1 · 보석 3(발판 위) · 황금 별 5(가운데, 30초마다 10초간) · 전설 상자 10(숨은 곳, 35초부터 40초마다 14초간).
    /// 높은 발판 = 2배 구역. 마지막 20초는 모두 2배. 다 주우면 다음 웨이브(배치 모양이 바뀜).
    /// </summary>
    public class PartyCoinsSolo : SoloMode
    {
        const int WaveCoins = 14;
        const float PickRadius = 1.3f;
        const int StarEvery = 30, StarLifetime = 10, BonusLast = 20, ChestFirst = 35, ChestEvery = 40, ChestLifetime = 14;

        readonly List<CoinArena.Coin> _coins = new List<CoinArena.Coin>();
        System.Random _rng;
        int _wave, _score;
        int _nextStar, _starUntil, _nextChest, _chestUntil;
        bool _bonus;
        static int _best = -1;

        public override string Title => "보물 수집";
        public override string RulesText => "금화 1 · 보석 3 · 가운데 별 5 · 숨은 전설 상자 10점! 높은 발판은 2배 구역, 마지막 20초는 모두 2배";

        CoinArena Arena => (CoinArena)map;

        public override void Begin(int nowTick)
        {
            roundTicks = 120 * 60;
            _score = 0;
            _coins.Clear();
            Arena.RenderCoins(_coins);
            base.Begin(nowTick);
        }

        protected override void OnRoundStart()
        {
            _rng = new System.Random(System.Environment.TickCount);
            _wave = 0;
            _bonus = false;
            _nextStar = tick + StarEvery * 60;
            _starUntil = 0;
            _nextChest = tick + ChestFirst * 60;
            _chestUntil = 0;
            SpawnWave();
        }

        void SpawnWave()
        {
            _wave++;
            _coins.Clear();
            foreach (var p in Arena.RandomCoinPoints(_rng, WaveCoins, (_wave - 1) % 3))
                _coins.Add(new CoinArena.Coin { pos = p, value = 1 });
            foreach (var pl in CoinArena.Platforms) // 발판마다 보석 1개
                _coins.Add(new CoinArena.Coin { pos = new Vector3(pl.center.x, pl.top + 1f, pl.center.z), value = 3 });
        }

        protected override void ModeTick(PlayerBody body)
        {
            int left = phaseEndTick - tick;
            if (!_bonus && left <= BonusLast * 60)
            {
                _bonus = true;
                Hud.Banner("보너스 타임! 이제부터 점수 2배", 2.5f);
            }
            if (tick >= _nextStar && left > StarLifetime * 60)
            {
                _nextStar = tick + StarEvery * 60;
                _starUntil = tick + StarLifetime * 60;
                _coins.Add(new CoinArena.Coin { pos = new Vector3(0, 1.2f, 0), value = 5 });
                Hud.Banner("가운데에 황금 별 등장! (5점)", 2.5f);
            }
            if (_starUntil > 0 && tick >= _starUntil)
            {
                _starUntil = 0;
                foreach (var c in _coins) if (c.value == 5) c.alive = false;
            }
            if (tick >= _nextChest && left > ChestLifetime * 60)
            {
                _nextChest = tick + ChestEvery * 60;
                _chestUntil = tick + ChestLifetime * 60;
                _coins.Add(new CoinArena.Coin { pos = CoinArena.HiddenSpots[_rng.Next(CoinArena.HiddenSpots.Length)], value = 10 });
                Hud.Banner($"어딘가에 전설 보물상자 등장! (10점, {ChestLifetime}초)", 2.5f);
            }
            if (_chestUntil > 0 && tick >= _chestUntil)
            {
                _chestUntil = 0;
                foreach (var c in _coins) if (c.value == 10) c.alive = false;
            }

            Vector3 pos = body.transform.position + new Vector3(0, 0.8f, 0);
            bool anyAlive = false;
            foreach (var c in _coins)
            {
                if (!c.alive) continue;
                if (Vector3.Distance(pos, c.pos) <= PickRadius)
                {
                    c.alive = false;
                    int zone = c.pos.y > 3.5f && c.value < 10 ? 2 : 1; // 높은 발판 = 보너스 구역
                    int pts = c.value * (_bonus ? 2 : 1) * zone;
                    _score += pts;
                    if (c.value >= 3 || pts > 1) Hud.Banner($"+{pts}점!", 1f);
                }
                if (c.alive && c.value < 5) anyAlive = true;
            }
            if (!anyAlive) SpawnWave();
            Arena.RenderCoins(_coins);
            if (_score > _best) _best = _score;
        }

        protected override bool IsOver() => false;

        public override Vector3 OnFell() => map.GetSpawnPoint(Random.Range(0, 8));

        protected override string ResultText() => $"{_score}점!\n최고 기록 {Mathf.Max(_best, 0)}점";

        protected override string SubText => $"{_score}점{(_bonus ? "  (2배!)" : "")}";
    }
}
