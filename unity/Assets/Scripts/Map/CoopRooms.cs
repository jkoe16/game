using System.Collections.Generic;
using UnityEngine;

namespace PartyWorld
{
    /// <summary>
    /// 협동 미션 "하늘 신전" (Godot scripts/gameplay/maps/coop_rooms.gd 이식).
    /// 방 3개 + 목표 방이 +Z로 이어지고, 방 사이를 문이 막는다. 각 방에 발판 4개.
    /// 필요한 인원만큼 동시에 밟으면 다음 문이 열린다.
    /// </summary>
    public class CoopRooms : GameMap
    {
        public const float PlateRadius = 1.2f;
        public const float RoomLen = 20f;
        static readonly Color PLATE_IDLE = C(0.95f, 0.55f, 0.35f);
        static readonly Color PLATE_ON = C(0.45f, 0.95f, 0.5f);

        public readonly List<Vector3[]> stagePlates = new List<Vector3[]>();
        readonly List<MeshRenderer[]> _plateMeshes = new List<MeshRenderer[]>();

        protected override void BuildMap()
        {
            mapId = "coop_rooms";
            displayName = "협동 미션: 하늘 신전";
            killHeight = -10f;
            SetupEnvironment(C(0.45f, 0.7f, 0.9f), C(0.95f, 0.95f, 0.85f), new Vector3(-65, 20, 0));
            float floorLen = RoomLen * 4f;
            AddBox(new Vector3(0, -0.5f, floorLen * 0.5f - 10f), new Vector3(16, 1, floorLen), C(0.9f, 0.85f, 0.7f));
            foreach (float side in new[] { -1f, 1f })
                AddBox(new Vector3(8.5f * side, 2, floorLen * 0.5f - 10f), new Vector3(1, 4, floorLen), C(0.9f, 0.8f, 0.65f));
            AddBox(new Vector3(0, 2, -10.5f), new Vector3(18, 4, 1), C(0.9f, 0.8f, 0.65f));

            for (int s = 0; s < 3; s++)
            {
                float cz = s * RoomLen;
                Vector3[] plates = { new Vector3(-4, 0, cz - 3), new Vector3(4, 0, cz - 3), new Vector3(-4, 0, cz + 4), new Vector3(4, 0, cz + 4) };
                var meshes = new MeshRenderer[plates.Length];
                for (int k = 0; k < plates.Length; k++)
                {
                    var t = NewDynamic("Plate", plates[k] + new Vector3(0, 0.04f, 0));
                    meshes[k] = AddMesh(Cyl(PlateRadius, PlateRadius, 0.08f, 32), Vector3.zero, Toon(PLATE_IDLE), Vector3.zero, Vector3.one, t);
                }
                stagePlates.Add(plates);
                _plateMeshes.Add(meshes);
                AddGate(new Vector3(0, 2, cz + 9.5f), new Vector3(16, 4, 1));
                AddLabel(new Vector3(0, 5.2f, cz + 9.5f), $"{s + 1}번 문", 64);
            }
            AddLabel(new Vector3(0, 3, 3 * RoomLen), "목표 도착!", 96, C(1, 0.95f, 0.5f));

            for (int i = 0; i < 8; i++)
                spawnPoints.Add(new Vector3(-5.25f + i * 1.5f, 0.5f, -7f));
            // 2번 방은 낮은 회전 막대, 3번 방은 반대로 도는 막대 (발판 위에서 점프하며 버티기)
            AddSweeper(new Vector3(0, 0, RoomLen + 0.5f), 6.2f, 0.5f, 55f, 0f, 0f, 2, 0.4f, C(1f, 0.55f, 0.4f));
            AddSweeper(new Vector3(0, 0, 2 * RoomLen + 0.5f), 6.2f, 0.5f, -70f, 45f, 0f, 2, 0.4f, C(0.55f, 0.6f, 1f));
            Decorate();
        }

        void Decorate()
        {
            float floorLen = RoomLen * 4f;
            Color[] rugCols = { C(0.75f, 0.85f, 1f), C(1f, 0.82f, 0.88f), C(0.82f, 0.95f, 0.78f), C(1f, 0.92f, 0.65f) };
            for (int s = 0; s < 4; s++)
            {
                float cz = s * RoomLen;
                AddMesh(MeshFactory.Box(), new Vector3(0, 0.015f, cz + 0.5f), rugCols[s], Vector3.zero, new Vector3(13f, 0.03f, 15f));
                AddMesh(MeshFactory.Box(), new Vector3(0, 0.02f, cz + 0.5f), Lighten(rugCols[s], 0.35f), Vector3.zero, new Vector3(11.8f, 0.035f, 13.8f));
                foreach (float sx in new[] { -1f, 1f })
                {
                    foreach (float pz in new[] { cz - 7f, cz + 7f })
                    {
                        AddMesh(Cyl(0.42f, 0.32f, 0.6f, 12), new Vector3(6.9f * sx, 0.3f, pz), C(0.9f, 0.6f, 0.45f));
                        AddBush(new Vector3(6.9f * sx, 0.5f, pz), 0.55f);
                    }
                    AddMesh(Cyl(0.08f, 0.06f, 0.7f, 8), new Vector3(7.75f * sx, 2.6f, cz), C(0.5f, 0.35f, 0.28f), new Vector3(0, 0, -20 * sx), Vector3.one);
                    AddMesh(Sph(0.22f, 10), new Vector3(7.62f * sx, 3f, cz), Glow(C(1f, 0.65f, 0.3f), 2.2f), Vector3.zero, new Vector3(1, 1.5f, 1));
                    foreach (float pz in new[] { cz - 9.5f, cz + 9.5f })
                    {
                        AddMesh(Cyl(0.42f, 0.48f, 4f, 14), new Vector3(7.6f * sx, 2f, pz), C(0.95f, 0.88f, 0.75f));
                        AddMesh(MeshFactory.Box(), new Vector3(7.6f * sx, 4.05f, pz), C(0.98f, 0.92f, 0.8f), Vector3.zero, new Vector3(1.1f, 0.25f, 1.1f));
                    }
                }
            }
            foreach (float sx in new[] { -1f, 1f })
                AddMesh(MeshFactory.Box(), new Vector3(8.5f * sx, 4.1f, floorLen * 0.5f - 10f), C(0.85f, 0.88f, 1f), Vector3.zero, new Vector3(1.3f, 0.25f, floorLen));
            float gz = 3 * RoomLen;
            AddMesh(Cyl(1.3f, 1.5f, 0.6f, 24), new Vector3(0, 0.3f, gz + 5f), C(0.95f, 0.9f, 0.85f));
            AddMesh(Sph(0.7f, 18), new Vector3(0, 1.4f, gz + 5f), Glow(C(1f, 0.85f, 0.3f), 1.8f), Vector3.zero, Vector3.one);
            AddFlowers(new Vector3(0, 0, gz + 5f), 2.6f, 30, 77);
        }

        public Vector3 StageStart(int stage) => new Vector3(0, 0.5f, Mathf.Clamp(stage, 0, 3) * RoomLen - 6f);

        /// <summary>발판 색: 지난 단계와 지금 밟힌 발판은 초록</summary>
        public void ShowPlates(int stage, bool[] occupied)
        {
            for (int s = 0; s < _plateMeshes.Count; s++)
                for (int k = 0; k < _plateMeshes[s].Length; k++)
                {
                    bool on = s < stage || (s == stage && occupied != null && k < occupied.Length && occupied[k]);
                    _plateMeshes[s][k].sharedMaterial = Toon(on ? PLATE_ON : PLATE_IDLE);
                }
        }
    }
}
