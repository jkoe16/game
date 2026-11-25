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

        public Vector3 RespawnPoint() => mode != null ? mode.OnFell() : _spawn;

        /// <summary>매 물리 틱, 이동이 끝난 뒤</summary>
        public void OnTick(int tick)
        {
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

        void OnGUI()
        {
            float s = Screen.height / 720f;
            // 포털 입장 대기 막대
            if (_holdMode != "" && _holdTicks < HoldTicks && mode == null)
            {
                string name = _holdMode;
                foreach (var m in LobbyPlaza.ModePortals) if (m.mode == _holdMode) name = m.name;
                float w = 320 * s, h = 18 * s;
                var r = new Rect((Screen.width - w) / 2, Screen.height * 0.68f, w, h);
                GUI.DrawTexture(r, Texture2D.whiteTexture, ScaleMode.StretchToFill, false, 0, new Color(0, 0, 0, 0.35f), 0, 9 * s);
                GUI.DrawTexture(new Rect(r.x, r.y, w * _holdTicks / HoldTicks, h), Texture2D.whiteTexture, ScaleMode.StretchToFill, false, 0, new Color(1f, 0.85f, 0.4f), 0, 9 * s);
                Hud.Shadowed(new Rect(0, r.y - 44 * s, Screen.width, 40 * s), $"{name} 입장 중…", Hud.Style(Mathf.RoundToInt(26 * s), TextAnchor.MiddleCenter));
            }
            Hud.DrawBanner();
            // 미니게임 중: 광장으로 나가기 (휴대폰에서도 누를 수 있게 버튼으로)
            if (mode != null && mode.phase != "results")
            {
                var st = new GUIStyle(GUI.skin.button) { font = GameMap.UIFont, fontSize = Mathf.RoundToInt(20 * s) };
                if (GUI.Button(new Rect(Screen.width - 150 * s, 12 * s, 138 * s, 44 * s), "광장으로", st))
                    LoadLobby();
            }
        }
    }
}
