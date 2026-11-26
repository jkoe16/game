using System.Collections.Generic;
using UnityEngine;

namespace PartyWorld.Net
{
    /// <summary>
    /// 다른 사람 캐릭터 (Godot scripts/player/remote_interpolator.gd 이식).
    /// 서버 스냅샷을 쌓아 두고 약 100ms 과거 시점을 두 스냅샷 사이에서 보간해 보여 준다. 충돌·물리는 없다.
    /// </summary>
    public class RemotePlayer : MonoBehaviour
    {
        const int MaxBuffer = 40;
        const float TeleportDistance = 5f;

        public int peerId;
        public string nickname = "?";
        public OnlineClient client;
        public CharacterVisual visual;
        readonly List<SnapEntry> _buf = new List<SnapEntry>();

        public static RemotePlayer Spawn(OnlineClient client, int id, string nick, int color, int hat, Vector3 pos)
        {
            var go = new GameObject("Remote " + id + " " + nick);
            var rp = go.AddComponent<RemotePlayer>();
            rp.peerId = id;
            rp.nickname = nick;
            rp.client = client;
            go.transform.position = pos;
            rp.visual = CharacterVisual.Build(Appearance.SanitizeColor(color), Appearance.SanitizeHat(hat), go.transform);
            rp.visual.transform.localPosition = Vector3.zero;
            GameMap.MakeLabel(go.transform, new Vector3(0, 2.05f, 0), nick, 34);
            return rp;
        }

        public void Push(SnapEntry e)
        {
            if (_buf.Count == 0 || e.tick > _buf[_buf.Count - 1].tick)
            {
                _buf.Add(e);
                if (_buf.Count > MaxBuffer) _buf.RemoveAt(0);
            }
        }

        public void PlayEmote(int e)
        {
            if (visual != null && e >= 0 && e < Appearance.Emotes.Length) visual.PlayEmote(Appearance.Emotes[e]);
        }

        static Vector3 V(GVec3 g) => new Vector3(g.x, g.y, g.z);

        void Update()
        {
            if (_buf.Count == 0 || client == null) return;
            double rt = client.RenderTick;
            while (_buf.Count > 2 && _buf[1].tick <= rt) _buf.RemoveAt(0);
            var a = _buf[0];
            var b = _buf.Count > 1 ? _buf[1] : a;
            float t = 0f;
            long span = (long)b.tick - a.tick;
            if (span > 0) t = Mathf.Clamp01((float)((rt - a.tick) / span));
            Vector3 pa = V(a.pos), pb = V(b.pos);
            if (Vector3.Distance(pa, pb) > TeleportDistance) t = 1f; // 리스폰 등 순간이동은 보간하지 않음
            transform.position = Vector3.Lerp(pa, pb, t);
            if (visual != null)
            {
                float yaw = Mathf.LerpAngle(a.yaw * Mathf.Rad2Deg, b.yaw * Mathf.Rad2Deg, t);
                var vt = visual.transform;
                vt.rotation = Quaternion.Euler(0f, Mathf.LerpAngle(vt.eulerAngles.y, yaw, 1f - Mathf.Exp(-20f * Time.deltaTime)), 0f);
                Vector3 vel = Vector3.Lerp(V(a.vel), V(b.vel), t);
                visual.UpdateMotion(vel, (b.flags & SnapEntry.FlagGrounded) != 0, Time.deltaTime);
                bool outOfPlay = (b.flags & SnapEntry.FlagOut) != 0;
                if (visual.gameObject.activeSelf == outOfPlay) visual.gameObject.SetActive(!outOfPlay);
            }
        }
    }
}
