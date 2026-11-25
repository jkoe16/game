using UnityEngine;

namespace PartyWorld
{
    /// <summary>
    /// 레이싱 트랙 "구름 서킷" (Godot scripts/gameplay/maps/race_track.gd 이식). 꺾이는 순환 코스 (폭 8m, 한 바퀴 약 176m).
    /// 북동쪽 난간 없는 대각선 다리 = 지름길. 30초부터 굴러오는 공, 60초부터 밀어내는 벽, 남쪽 망치는 점점 빨라짐.
    /// 체크포인트 4개를 순서대로 통과 (0 = 출발/결승선).
    /// </summary>
    public class RaceTrack : GameMap
    {
        static readonly Color TRACK = C(0.45f, 0.47f, 0.55f);
        static readonly Color BRIDGE = C(0.95f, 0.75f, 0.45f);
        public const float Stage2Sec = 30f;
        public const float Stage3Sec = 60f;

        static readonly (Vector3 c, Vector3 s)[] Pieces =
        {
            (new Vector3(-20, -0.5f, 0), new Vector3(8, 1, 56)),
            (new Vector3(-4, -0.5f, 24), new Vector3(24, 1, 8)),
            (new Vector3(4, -0.5f, 12), new Vector3(8, 1, 16)),
            (new Vector3(12, -0.5f, 8), new Vector3(8, 1, 8)),
            (new Vector3(20, -0.5f, -8), new Vector3(8, 1, 40)),
            (new Vector3(0, -0.5f, -24), new Vector3(32, 1, 8)),
        };

        public static readonly (Vector3 center, Vector3 half)[] Checkpoints =
        {
            (new Vector3(-20, 1, -12), new Vector3(4, 2.5f, 1f)),
            (new Vector3(-8, 1, 24), new Vector3(1f, 2.5f, 4)),
            (new Vector3(20, 1, 0), new Vector3(4, 2.5f, 1f)),
            (new Vector3(0, 1, -24), new Vector3(1f, 2.5f, 4)),
        };

        protected override void BuildMap()
        {
            mapId = "race_track";
            displayName = "구름 서킷";
            killHeight = -10f;
            SetupEnvironment(C(0.35f, 0.6f, 0.95f), C(0.85f, 0.92f, 1f), new Vector3(-50, 40, 0));
            foreach (var pc in Pieces) AddBox(pc.c, pc.s, TRACK);
            AddBox(new Vector3(0, -2, 0), new Vector3(32, 1, 40), C(0.5f, 0.85f, 0.5f), Vector3.zero, false); // 안쪽 잔디(장식)
            AddChecker(new Vector3(-20, 0, -12), 8, 1.2f, 0.8f);
            AddLabel(new Vector3(-20, 6.2f, -12), "출발 / 결승", 80, C(1, 0.95f, 0.5f));

            AddPad("boost", new Vector3(-20, 0, 8), new Vector3(2.5f, 0.3f, 2));
            // 북쪽: 낮은 벽 (점프로도 넘지만 점프대가 더 빠름)
            AddPad("jump", new Vector3(-3, 0, 24), new Vector3(1.2f, 0.3f, 3.5f), 11f);
            AddBox(new Vector3(1, 0.6f, 24), new Vector3(0.8f, 1.2f, 8), C(1f, 0.55f, 0.45f));
            // 지름길: 북쪽 끝 → 동쪽 직선 위쪽으로 가는 난간 없는 좁은 대각선 다리
            var a = new Vector3(7.6f, 0, 23f);
            var b = new Vector3(19f, 0, 11.6f);
            var mid = (a + b) * 0.5f;
            AddBox(new Vector3(mid.x, -0.3f, mid.z), new Vector3(1.4f, 0.6f, Vector3.Distance(a, b) + 1f), BRIDGE,
                new Vector3(0, Mathf.Atan2(b.x - a.x, b.z - a.z) * Mathf.Rad2Deg, 0));
            AddLabel(new Vector3(mid.x, 2.6f, mid.z), "지름길!", 56, C(1, 0.85f, 0.4f));
            // 골목: 30초부터 앞에서 공이 굴러온다
            AddRoller(new Vector3(2.2f, 0.7f, 5f), new Vector3(2.2f, 0.7f, 19.5f), 0.7f, 2.6f, 0f, Stage2Sec);
            AddRoller(new Vector3(5.8f, 0.7f, 5f), new Vector3(5.8f, 0.7f, 19.5f), 0.7f, 2.6f, 0.5f, Stage2Sec);
            AddPad("boost", new Vector3(12, 0, 8), new Vector3(2f, 0.3f, 2f));
            // 동쪽 직선: 60초부터 양옆에서 벽이 튀어나온다
            AddPusher(new Vector3(24.8f, 0.6f, -8), new Vector3(1.6f, 1.2f, 2.4f), new Vector3(-1, 0, 0), 4.6f, 2.4f, 0f, Stage3Sec);
            AddPusher(new Vector3(15.2f, 0.6f, -14), new Vector3(1.6f, 1.2f, 2.4f), new Vector3(1, 0, 0), 4.6f, 2.4f, 0.5f, Stage3Sec);
            AddPad("boost", new Vector3(20, 0, -20), new Vector3(2.5f, 0.3f, 2));
            // 남쪽 직선: 회전 망치 → 바로 뒤 부스터
            AddSweeper(new Vector3(6, 0, -24), 3.6f, 0.5f, 95f, 0f, 1.2f, 1, 0.4f, C(0.45f, 0.6f, 1f), true);
            AddSweeper(new Vector3(-7, 0, -24), 3.6f, 0.5f, -80f, 90f, 0f, 1, 0.4f, C(1f, 0.6f, 0.3f), true);
            AddPad("boost", new Vector3(-13, 0, -24), new Vector3(1.6f, 0.3f, 2.5f));
            for (int i = 0; i < 8; i++)
                spawnPoints.Add(new Vector3(-22.5f + (i % 4) * 1.7f, 0.5f, -7.5f + (i / 4) * 1.8f));
            Decorate();
        }

        void Decorate()
        {
            AddArch(new Vector3(-20, 0, -12), 9.2f, 4.6f, C(1f, 0.55f, 0.7f));
            foreach (var pc in Pieces) AddEdgeTrim(pc.c, pc.s, C(1f, 0.5f, 0.55f));
            float g = -1.5f;
            foreach (var p in new[] { new Vector3(-10, g, -14), new Vector3(6, g, -12), new Vector3(-9, g, 4), new Vector3(-4, g, 14), new Vector3(-11, g, 16), new Vector3(10, g, -4) })
                AddTree(p, (int)Mathf.Abs(p.z) % 3, 1f, false);
            foreach (var p in new[] { new Vector3(0, g, -12), new Vector3(-6, g, 8), new Vector3(-6, g, -4), new Vector3(8, g, -16), new Vector3(12, g, 20) })
            {
                AddFlowers(p, 2.4f, 26, (int)(p.z * 3 + 50));
                AddBush(p + new Vector3(2.5f, 0, 1.5f), 0.9f);
            }
            Color[] flagCols = { C(1f, 0.5f, 0.6f), C(1f, 0.8f, 0.3f), C(0.45f, 0.75f, 1f), C(0.6f, 0.9f, 0.5f) };
            int k = 0;
            foreach (var c in new[] { new Vector3(-24.5f, 0, -28.5f), new Vector3(24.5f, 0, -28.5f), new Vector3(-24.5f, 0, 28.5f), new Vector3(8.5f, 0, 28.5f), new Vector3(24.5f, 0, 12.5f) })
            {
                AddFlag(c, flagCols[k % 4], 45f * k);
                k++;
            }
        }

        public bool InCheckpoint(Vector3 pos, int i)
        {
            Vector3 d = pos - Checkpoints[i].center, h = Checkpoints[i].half;
            return Mathf.Abs(d.x) <= h.x && Mathf.Abs(d.y) <= h.y && Mathf.Abs(d.z) <= h.z;
        }

        public Vector3 CheckpointPoint(int i) => Checkpoints[i].center + new Vector3(0, -0.5f, 0);
    }
}
