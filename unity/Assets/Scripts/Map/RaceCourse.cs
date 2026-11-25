using System.Collections.Generic;
using UnityEngine;

namespace PartyWorld
{
    /// <summary>
    /// 장애물 레이스 코스 "하늘 놀이공원 코스" (Godot scripts/gameplay/maps/race_course.gd 이식, +Z 방향으로 진행).
    ///  A 구멍 점프 + 굴러오는 공 → B 회전 망치 2개 → C 이동 발판(빠른 길) 또는 주먹 벽 좁은 다리
    ///  → D 사라지는 발판 + 점프 패드로 윗층 → E 막대 + 결승
    /// </summary>
    public class RaceCourse : GameMap
    {
        static readonly Color GROUND = C(0.98f, 0.78f, 0.55f);
        static readonly Color PATH = C(0.55f, 0.8f, 1f);
        static readonly Color UPPER = C(0.75f, 0.6f, 1f);

        public const float FinishZ = 114f;

        public struct Checkpoint { public float z, minY; public Vector3 point; }
        /// <summary>체크포인트: z를 넘으면 도달 (윗층은 y 조건 포함)</summary>
        public static readonly Checkpoint[] Checkpoints =
        {
            new Checkpoint { z = -100f, minY = -99f, point = new Vector3(0, 0.5f, -2) },
            new Checkpoint { z = 16.5f, minY = -1f, point = new Vector3(0, 0.5f, 17.4f) },
            new Checkpoint { z = 34.5f, minY = -1f, point = new Vector3(0, 0.5f, 34.9f) },
            new Checkpoint { z = 54f, minY = -1f, point = new Vector3(0, 0.5f, 55) },
            new Checkpoint { z = 76f, minY = -1f, point = new Vector3(0, 0.5f, 80) },
            new Checkpoint { z = 98f, minY = 2.5f, point = new Vector3(0, 4f, 100) },
        };

        readonly List<(Transform node, Vector3 axis, float speed)> _spin = new List<(Transform, Vector3, float)>();

        protected override void BuildMap()
        {
            mapId = "race_course";
            displayName = "하늘 놀이공원 코스";
            killHeight = -15f;
            SetupEnvironment(C(0.4f, 0.65f, 0.98f), C(0.9f, 0.95f, 1f), new Vector3(-55, 25, 0));

            // 출발 + A: 구멍 점프 → 긴 비탈길에서 공 3개가 굴러온다
            AddBox(new Vector3(0, -0.5f, 0), new Vector3(14, 1, 12), GROUND);
            AddBox(new Vector3(0, -0.5f, 10), new Vector3(10, 1, 8), PATH);
            AddBox(new Vector3(0, -0.5f, 25.25f), new Vector3(10, 1, 17.5f), GROUND);
            for (int i = 0; i < 3; i++)
            {
                float x = -3f + i * 3f;
                AddRoller(new Vector3(x, 0.7f, 33.5f), new Vector3(x, 0.7f, 19.2f), 0.7f, 2.8f, i * 0.37f);
            }
            AddLabel(new Vector3(0, 3.2f, 17.5f), "공을 점프로 넘어요!", 48, C(1, 0.7f, 0.8f));
            AddLabel(new Vector3(0, 5.6f, 5), "출발!", 96, C(1, 0.9f, 0.4f));

            // B: 넓은 무대 + 낮은 회전 망치 2개
            AddBox(new Vector3(0, -0.5f, 44), new Vector3(14, 1, 20), PATH);
            AddSweeper(new Vector3(-3.5f, 0, 40), 4.5f, 0.5f, 100f, 0f, 0f, 1, 0.4f, C(1f, 0.45f, 0.4f), true);
            // 후반 패턴: 점점 느려지다 30초쯤 멈춘 뒤 반대 방향으로 빨라진다
            AddSweeper(new Vector3(3.5f, 0, 48), 4.5f, 0.5f, -120f, 90f, 4f, 1, 0.4f, C(1f, 0.6f, 0.3f), true);
            AddPad("boost", new Vector3(-5f, 0, 52f), new Vector3(1.6f, 0.3f, 1.4f));

            // C: 빠른 길(이동 발판 3개) / 쉬운 길(오른쪽 좁은 다리)
            AddBox(new Vector3(0, -0.5f, 55), new Vector3(14, 1, 2), GROUND);
            for (int i = 0; i < 3; i++)
            {
                float z = 60f + i * 6f;
                AddMover(new Vector3(-5, -0.3f, z), new Vector3(2, -0.3f, z), new Vector3(4, 0.6f, 4), 4f, i * 0.33f);
            }
            Color bridge = C(0.85f, 0.7f, 0.5f);
            AddBox(new Vector3(6.5f, -0.5f, 66), new Vector3(1.6f, 1, 20), bridge);
            // 쉬운 길도 공짜는 아니다: 오른쪽 벽에서 주먹이 튀어나온다 (떨리면 곧 나온다)
            AddBox(new Vector3(8.4f, 0.6f, 66), new Vector3(0.8f, 2.2f, 20), Darken(bridge, 0.2f));
            AddPusher(new Vector3(8.6f, 0.6f, 62f), new Vector3(1.2f, 1.2f, 2.2f), new Vector3(-1, 0, 0), 2.2f, 2.6f, 0f);
            AddPusher(new Vector3(8.6f, 0.6f, 70f), new Vector3(1.2f, 1.2f, 2.2f), new Vector3(-1, 0, 0), 2.2f, 2.6f, 0.5f);
            AddLabel(new Vector3(6.5f, 2.5f, 58), "쉬운 길", 56);
            AddLabel(new Vector3(-1.5f, 2.5f, 57), "빠른 길", 56);

            // D: 착지 무대 → 깜빡이다 사라지는 발판 3줄 → 점프 패드로 윗층
            AddBox(new Vector3(0, -0.5f, 79), new Vector3(14, 1, 6), GROUND);
            for (int row = 0; row < 3; row++)
                for (int col = 0; col < 3; col++)
                {
                    float ph = Mathf.Repeat(-row * 0.22f + col * 0.4f, 1f); // 앞줄일수록 늦게 사라짐
                    AddBlinker(new Vector3(-4.6f + col * 4.6f, -0.5f, 83.6f + row * 3.25f), new Vector3(4.4f, 1, 3.05f), 3.4f, ph, 0.64f);
                }
            AddLabel(new Vector3(0, 3f, 82.5f), "빨갛게 깜빡이면 사라져요!", 48, C(0.7f, 0.9f, 1));
            AddBox(new Vector3(0, -0.5f, 93.75f), new Vector3(14, 1, 4.5f), GROUND);
            AddPad("jump", new Vector3(0, 0, 93.5f), new Vector3(2f, 0.3f, 1.2f), 15f);
            AddPad("boost", new Vector3(4.5f, 0, 81f), new Vector3(1.6f, 0.3f, 1.4f));
            AddBox(new Vector3(0, 1.75f, 105), new Vector3(14, 3.5f, 14), Darken(UPPER, 0.25f));
            AddBox(new Vector3(0, 3.25f, 105), new Vector3(14, 0.5f, 14), UPPER);

            // E: 윗층 막대(양쪽 팔, 점점 빨라짐) + 결승
            AddSweeper(new Vector3(0, 3.5f, 105), 6f, 4f, 75f, 0f, 1.5f, 2);
            AddBox(new Vector3(0, 3f, 117), new Vector3(14, 1, 10), C(1f, 0.9f, 0.5f));
            AddChecker(new Vector3(0, 3.5f, FinishZ), 14, 1.4f);
            AddLabel(new Vector3(0, 9f, FinishZ), "결승선", 110, C(1, 0.95f, 0.5f));

            for (int i = 0; i < 8; i++)
                spawnPoints.Add(new Vector3(-5.25f + i * 1.5f, 0.5f, -3f));
            Decorate();
        }

        /// <summary>시각 장식: 출발·결승 아치, 깃발, 발판 테두리, 꽃, 놀이기구</summary>
        void Decorate()
        {
            AddArch(new Vector3(0, 0, 5), 11f, 4.4f, C(1f, 0.55f, 0.7f));
            AddArch(new Vector3(0, 3.5f, FinishZ), 14.6f, 4.6f, C(1f, 0.78f, 0.3f));
            (Vector3 p, Vector3 s)[] trims =
            {
                (new Vector3(0, -0.5f, 0), new Vector3(14, 1, 12)), (new Vector3(0, -0.5f, 44), new Vector3(14, 1, 20)), (new Vector3(0, -0.5f, 79), new Vector3(14, 1, 6)),
                (new Vector3(0, -0.5f, 93.75f), new Vector3(14, 1, 4.5f)), (new Vector3(0, 3.25f, 105), new Vector3(14, 0.5f, 14)), (new Vector3(0, 3f, 117), new Vector3(14, 1, 10)),
                (new Vector3(0, -0.5f, 25.25f), new Vector3(10, 1, 17.5f)),
            };
            foreach (var b in trims) AddEdgeTrim(b.p, b.s, Color.white);
            Color[] flagCols = { C(1f, 0.5f, 0.6f), C(1f, 0.8f, 0.3f), C(0.45f, 0.75f, 1f), C(0.6f, 0.9f, 0.5f) };
            int fi = 0;
            foreach (float z in new[] { -4f, 36f, 52f, 78f, 94f })
                foreach (float sx in new[] { -1f, 1f })
                {
                    AddFlag(new Vector3(6.6f * sx, 0, z), flagCols[fi % 4], sx < 0 ? 0f : 180f);
                    fi++;
                }
            foreach (float sx in new[] { -1f, 1f })
            {
                AddFlag(new Vector3(6.6f * sx, 3.5f, 120.5f), flagCols[fi % 4], sx < 0 ? 0f : 180f);
                fi++;
                AddFlowers(new Vector3(5.8f * sx, 0, -4.5f), 0.9f, 14, 40 + fi);
                AddBush(new Vector3(6f * sx, 0, 3.5f), 0.7f);
                AddFlowers(new Vector3(5.8f * sx, 3.5f, 120f), 0.9f, 12, 60 + fi);
            }
            BuildFerrisWheel(new Vector3(-30, -2, 62));
            BuildCarousel(new Vector3(22, -3, 30));
            Color[] tentCols = { C(1f, 0.5f, 0.6f), C(0.5f, 0.7f, 1f), C(1f, 0.8f, 0.35f), C(0.65f, 0.9f, 0.55f) };
            for (int i = 0; i < 4; i++)
            {
                var p = new Vector3(i % 2 == 0 ? -17f : 17f, -2.5f, 12f + i * 26f);
                AddMesh(Cyl(3.2f, 3.2f, 1f, 24), p, C(0.55f, 0.85f, 0.5f));
                AddIslandUnderside(p + new Vector3(0, -0.5f, 0), 3.1f, 4f);
                BuildTent(p + new Vector3(0, 0.5f, 0), tentCols[i]);
            }
        }

        void Update()
        {
            foreach (var s in _spin) s.node.Rotate(s.axis, s.speed * Mathf.Rad2Deg * Time.deltaTime, Space.Self);
        }

        /// <summary>대관람차 (천천히 돈다)</summary>
        void BuildFerrisWheel(Vector3 pos)
        {
            AddMesh(Cyl(5f, 6f, 1.5f, 24), pos + new Vector3(0, -0.75f, 0), C(0.55f, 0.85f, 0.5f));
            AddIslandUnderside(pos + new Vector3(0, -1.5f, 0), 5.8f, 7f);
            Color white = C(0.95f, 0.95f, 1f);
            foreach (float sz in new[] { -1f, 1f })
            {
                AddMesh(Cyl(0.35f, 0.5f, 13f, 10), pos + new Vector3(-3f, 6f, sz), white, new Vector3(0, 0, -14), Vector3.one);
                AddMesh(Cyl(0.35f, 0.5f, 13f, 10), pos + new Vector3(3f, 6f, sz), white, new Vector3(0, 0, 14), Vector3.one);
            }
            var wheel = NewDynamic("FerrisWheel", pos + new Vector3(0, 12f, 0));
            AddMesh(MeshFactory.Torus(9.4f, 10f, 48, 8), Vector3.zero, C(1f, 0.55f, 0.7f), new Vector3(90, 0, 0), Vector3.one, wheel);
            AddMesh(Sph(1f, 14), Vector3.zero, C(1f, 0.85f, 0.35f), Vector3.zero, Vector3.one, wheel);
            Color[] cols = { C(1f, 0.55f, 0.6f), C(0.5f, 0.75f, 1f), C(1f, 0.82f, 0.35f), C(0.6f, 0.9f, 0.55f), C(0.8f, 0.65f, 1f) };
            for (int k = 0; k < 10; k++)
            {
                float a = Mathf.PI * 2f * k / 10f;
                var dir = new Vector3(Mathf.Cos(a), Mathf.Sin(a), 0);
                AddMesh(Cyl(0.12f, 0.12f, 9.6f, 6), dir * 4.8f, Color.white, new Vector3(0, 0, a * Mathf.Rad2Deg - 90f), Vector3.one, wheel);
                AddMesh(MeshFactory.Box(), dir * 9.7f, cols[k % 5], Vector3.zero, new Vector3(1.4f, 1.2f, 1.4f), wheel);
            }
            _spin.Add((wheel, Vector3.back, 0.15f)); // Godot Vector3.FORWARD = -Z
        }

        /// <summary>회전목마</summary>
        void BuildCarousel(Vector3 pos)
        {
            AddMesh(Cyl(5.5f, 5.5f, 1.2f, 32), pos, C(0.55f, 0.85f, 0.5f));
            AddIslandUnderside(pos + new Vector3(0, -0.6f, 0), 5.4f, 6f);
            var spin = NewDynamic("Carousel", pos + new Vector3(0, 0.6f, 0));
            AddMesh(Cyl(4f, 4.2f, 0.5f, 32), new Vector3(0, 0.25f, 0), C(1f, 0.92f, 0.75f), Vector3.zero, Vector3.one, spin);
            AddMesh(Cyl(0.4f, 0.4f, 4.5f, 12), new Vector3(0, 2.5f, 0), C(1f, 0.85f, 0.4f), Vector3.zero, Vector3.one, spin);
            for (int k = 0; k < 8; k++) // 줄무늬 지붕
            {
                float a = Mathf.PI * 2f * k / 8f;
                AddMesh(Cyl(0f, 2.2f, 1.6f, 3), new Vector3(Mathf.Sin(a) * 2.2f, 5.3f, Mathf.Cos(a) * 2.2f), k % 2 == 0 ? C(1f, 0.5f, 0.65f) : Color.white,
                    new Vector3(0, a * Mathf.Rad2Deg, 0), new Vector3(1, 1, 0.9f), spin);
            }
            AddMesh(Cyl(0.05f, 4.3f, 1.8f, 24), new Vector3(0, 5.4f, 0), C(1f, 0.6f, 0.75f), Vector3.zero, Vector3.one, spin);
            Color[] cols = { C(1f, 0.7f, 0.8f), C(0.7f, 0.85f, 1f), C(1f, 0.9f, 0.6f), C(0.75f, 0.95f, 0.7f) };
            for (int k = 0; k < 6; k++)
            {
                float a = Mathf.PI * 2f * k / 6f;
                var p = new Vector3(Mathf.Sin(a) * 3f, 0, Mathf.Cos(a) * 3f);
                AddMesh(Cyl(0.06f, 0.06f, 3.8f, 6), p + new Vector3(0, 2.4f, 0), C(1f, 0.85f, 0.4f), Vector3.zero, Vector3.one, spin);
                AddMesh(Sph(0.55f, 12), p + new Vector3(0, 1.4f, 0), cols[k % 4], Vector3.zero, new Vector3(0.7f, 0.8f, 1.4f), spin);
            }
            _spin.Add((spin, Vector3.up, 0.5f));
        }

        /// <summary>줄무늬 천막</summary>
        void BuildTent(Vector3 pos, Color c)
        {
            AddMesh(Cyl(1.8f, 1.8f, 1.8f, 16), pos + new Vector3(0, 0.9f, 0), Color.white);
            for (int k = 0; k < 8; k++)
            {
                float a = Mathf.PI * 2f * k / 8f;
                AddMesh(Cyl(0f, 1.35f, 1.7f, 3), pos + new Vector3(Mathf.Sin(a) * 0.95f, 2.6f, Mathf.Cos(a) * 0.95f), k % 2 == 0 ? c : Color.white, new Vector3(0, a * Mathf.Rad2Deg, 0), Vector3.one);
            }
            AddMesh(Sph(0.2f, 8), pos + new Vector3(0, 3.55f, 0), C(1f, 0.85f, 0.35f));
            AddFlag(pos + new Vector3(0, 3.5f, 0), c, 0f, 1f);
        }

        public int CheckpointIndexAt(Vector3 pos)
        {
            int best = 0;
            for (int i = 0; i < Checkpoints.Length; i++)
                if (pos.z >= Checkpoints[i].z && pos.y >= Checkpoints[i].minY) best = i;
            return best;
        }

        public Vector3 CheckpointPoint(int i, int peerId = 0)
        {
            Vector3 p = Checkpoints[Mathf.Clamp(i, 0, Checkpoints.Length - 1)].point;
            int k = ((peerId % 5) + 5) % 5;
            return p + new Vector3((k - 2) * 1.2f, 0, 0);
        }

        public bool IsFinished(Vector3 pos) => pos.z >= FinishZ && pos.y > 2.5f;
    }
}
