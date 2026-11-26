using UnityEngine;

namespace PartyWorld
{
    /// <summary>
    /// 지금 어떤 맵·미니게임에 있는지 관리 (혼자 하기). 광장 포털 위에 1.5초 서 있으면 그 미니게임으로,
    /// 끝나면 다시 광장으로. 온라인 단계에서는 이 역할을 서버가 맡는다.
    /// </summary>
    public class GameSession : MonoBehaviour
    {
        /// <summary>포털 위에 이만큼 서 있으면 입장 (Godot LobbyMode.HOLD_TICKS)</summary>
        const int HoldTicks = 90;

        public PlayerBody body;
        public LocalPlayerController ctrl;
        public GameMap map;
        public SoloMode mode;

        string _holdMode = "";
        int _holdTicks;
        Vector3 _spawn;

        /// <summary>시작할 때 주소의 ?mode=obstacle_race 처럼 바로 미니게임으로 갈 수도 있다</summary>
        public void Begin(string startMode)
        {
            if (GameHud.I != null) GameHud.I.onExit = LoadLobby;
            if (!string.IsNullOrEmpty(startMode) && StartMode(startMode)) return;
            LoadLobby();
        }

        void ClearMap()
        {
            if (mode != null) Destroy(mode);
            mode = null;
            if (map != null) Destroy(map.gameObject);
            map = null;
            body.frozen = false;
            _holdMode = "";
            _holdTicks = 0;
        }

        public void LoadLobby()
        {
            ClearMap();
            map = GameMap.Create<LobbyPlaza>();
            _spawn = map.GetSpawnPoint(Random.Range(0, 12));
            ctrl.killHeight = map.killHeight;
            body.Teleport(_spawn);
        }

        /// <summary>미니게임 시작. 아직 옮기지 않은 것은 false</summary>
        public bool StartMode(string modeId)
        {
            switch (modeId)
            {
                case "obstacle_race":
                    ClearMap();
                    map = GameMap.Create<RaceCourse>();
                    mode = gameObject.AddComponent<ObstacleRaceSolo>();
                    break;
                case "survival":
                    ClearMap();
                    map = GameMap.Create<SurvivalArena>();
                    mode = gameObject.AddComponent<SurvivalSolo>();
                    break;
                case "racing":
                    ClearMap();
                    map = GameMap.Create<RaceTrack>();
                    mode = gameObject.AddComponent<RacingSolo>();
                    break;
                case "coop":
                    ClearMap();
                    map = GameMap.Create<CoopRooms>();
                    mode = gameObject.AddComponent<CoopSolo>();
                    break;
                case "party":
                    ClearMap();
                    map = GameMap.Create<CoinArena>();
                    mode = gameObject.AddComponent<PartyCoinsSolo>();
                    break;
                default:
                    return false;
            }
            ctrl.killHeight = map.killHeight;
            mode.session = this;
            mode.map = map;
            mode.Begin(ctrl.tick);
            return true;
        }

        /// <summary>온라인: 서버가 알려 준 맵을 연다 (규칙·점수는 서버가 맡으므로 SoloMode 없이)</summary>
        public bool LoadOnlineMap(string mapId)
        {
            ClearMap();
            switch (mapId)
            {
                case "lobby_plaza": map = GameMap.Create<LobbyPlaza>(); break;
                case "race_course": map = GameMap.Create<RaceCourse>(); break;
                case "survival_arena": map = GameMap.Create<SurvivalArena>(); break;
                case "race_track": map = GameMap.Create<RaceTrack>(); break;
                case "coop_rooms": map = GameMap.Create<CoopRooms>(); break;
                case "coin_arena": map = GameMap.Create<CoinArena>(); break;
                default: return false;
            }
            ctrl.killHeight = map.killHeight;
            return true;
        }

        public Vector3 RespawnPoint() => mode != null ? mode.OnFell() : _spawn;

        /// <summary>매 물리 틱, 이동이 끝난 뒤</summary>
        public void OnTick(int tick)
        {
            if (ctrl.online != null) return; // 온라인: 포털·규칙은 서버가
            if (mode != null)
            {
                mode.Tick(tick, body);
                return;
            }
            if (map is LobbyPlaza lobby) LobbyPortals(lobby);
        }

        void LobbyPortals(LobbyPlaza lobby)
        {
            Vector3 pos = body.transform.position;
            string inside = "";
            foreach (var p in lobby.portals)
                if (new Vector2(pos.x - p.center.x, pos.z - p.center.z).magnitude <= p.radius && pos.y < 1.5f)
                {
                    inside = p.mode;
                    break;
                }
            if (inside != _holdMode)
            {
                _holdMode = inside;
                _holdTicks = 0;
                return;
            }
            if (inside == "") return;
            _holdTicks++;
            if (_holdTicks == HoldTicks && !StartMode(inside))
                Hud.Banner("이 게임은 아직 옮기는 중이에요!", 2.5f);
        }

        void Update()
        {
            var hud = GameHud.I;
            if (hud == null || ctrl.online != null) return; // 온라인 화면은 OnlineClient 가 그린다
            // 포털 입장 대기 막대
            if (_holdMode != "" && _holdTicks < HoldTicks && mode == null)
            {
                string name = _holdMode;
                foreach (var m in LobbyPlaza.ModePortals) if (m.mode == _holdMode) name = m.name;
                hud.SetHold(name, (float)_holdTicks / HoldTicks);
            }
            else hud.SetHold("", -1f);
            // 미니게임 중: 광장으로 나가기 버튼 (휴대폰에서도 누를 수 있게)
            hud.ShowExit(mode != null && mode.phase != "results");
        }
    }
}
