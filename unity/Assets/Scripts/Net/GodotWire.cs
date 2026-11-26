using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace PartyWorld.Net
{
    /// <summary>
    /// Godot 4.7 SceneMultiplayer 의 패킷 형식 (modules/multiplayer/scene_rpc_interface.cpp, scene_cache_interface.cpp).
    /// 지금 서버(Godot 전용 서버)와 그대로 말하려고 RPC 패킷을 직접 만들고 읽는다.
    ///
    /// 연결 순서 (WebSocketMultiplayerPeer): 웹소켓이 열리면 서버가 먼저 4바이트(int32)로 내 피어 번호를 보낸다.
    /// 그 뒤의 웹소켓 메시지 하나 = SceneMultiplayer 패킷 하나.
    ///   첫 바이트: 하위 3비트 = 명령 (0 RPC, 1 경로 알림, 2 경로 확인 ...), 4~5비트 = 노드 번호 크기,
    ///              6비트 = 메서드 번호 크기, 7비트 = "인자가 바이트 배열 하나뿐"
    /// 모든 RPC 는 /root/Net (network_manager.gd) 노드에 있고, 메서드 번호는 이름을 정렬한 순서다.
    /// </summary>
    public class GodotWire
    {
        public const byte CmdRemoteCall = 0, CmdSimplifyPath = 1, CmdConfirmPath = 2;

        public const string NetPath = "/root/Net";

        /// <summary>network_manager.gd 의 @rpc 함수 이름 (정렬된 순서 = 메서드 번호)</summary>
        public static readonly string[] Methods =
        {
            "c_emote", "c_hello", "c_input", "c_leave",
            "s_emote", "s_mode_state", "s_notice", "s_player_joined", "s_player_left",
            "s_reject", "s_snapshot", "s_transfer", "s_welcome",
        };

        public static int MethodId(string name)
        {
            int i = Array.IndexOf(Methods, name);
            if (i < 0) throw new ArgumentException("unknown rpc " + name);
            return i;
        }

        /// <summary>서버가 알려 준 노드 번호 → 경로</summary>
        readonly Dictionary<uint, string> _paths = new Dictionary<uint, string>();

        public struct Rpc
        {
            public string method;
            public object[] args;
        }

        // ------------------------------------------------------------------ 보내기

        /// <summary>
        /// /root/Net 의 RPC 호출 패킷. 노드는 항상 전체 경로로 보낸다 (경로 캐시를 쓰지 않음: 서버는 둘 다 받아 준다).
        /// </summary>
        public static byte[] BuildRpc(string method, params object[] args)
        {
            int id = MethodId(method);
            var ms = new MemoryStream(64);
            var w = new BinaryWriter(ms);
            bool byteOnly = args.Length == 0 || (args.Length == 1 && args[0] is byte[]);
            const int nodeComp32 = 2;
            w.Write((byte)(CmdRemoteCall | (nodeComp32 << 4) | (0 << 6) | (byteOnly ? 0x80 : 0)));
            w.Write(0u); // 노드 자리: 나중에 경로 위치로 채움
            w.Write((byte)id);
            if (byteOnly)
            {
                if (args.Length == 1) w.Write((byte[])args[0]);
            }
            else
            {
                w.Write((byte)args.Length);
                foreach (var a in args) GodotVariant.EncodeCompressed(a, w);
            }
            int pathOfs = (int)ms.Position;
            byte[] path = Encoding.UTF8.GetBytes(NetPath);
            w.Write(path);
            w.Write((byte)0);
            w.Flush();
            byte[] pkt = ms.ToArray();
            uint target = 0x80000000u | (uint)pathOfs;
            BitConverter.GetBytes(target).CopyTo(pkt, 1);
            return pkt;
        }

        // ------------------------------------------------------------------ 받기

        /// <summary>
        /// 서버 패킷 하나 처리. RPC 면 rpc 에 담아 true. 경로 알림이면 reply 에 확인 패킷을 담는다 (보내야 함).
        /// </summary>
        public bool Parse(byte[] p, out Rpc rpc, out byte[] reply)
        {
            rpc = default;
            reply = null;
            if (p == null || p.Length < 1) return false;
            int cmd = p[0] & 7;
            if (cmd == CmdSimplifyPath)
            {
                // [cmd][md5 32글자 + 0][id u32][경로 utf8]
                if (p.Length < 38) return false;
                uint pid = BitConverter.ToUInt32(p, 34);
                string path = Encoding.UTF8.GetString(p, 38, p.Length - 38).TrimEnd('\0');
                _paths[pid] = path;
                reply = new byte[6];
                reply[0] = CmdConfirmPath;
                reply[1] = 1; // 메서드 목록 체크섬이 같다고 답함 (서버는 로그만 남김)
                BitConverter.GetBytes(pid).CopyTo(reply, 2);
                return false;
            }
            if (cmd != CmdRemoteCall) return false;

            int nodeComp = (p[0] >> 4) & 3;
            int nameComp = (p[0] >> 6) & 1;
            bool byteOnly = (p[0] & 0x80) != 0;
            int ofs = 1;
            uint node;
            switch (nodeComp)
            {
                case 0: if (p.Length < ofs + 1) return false; node = p[ofs]; ofs += 1; break;
                case 1: if (p.Length < ofs + 2) return false; node = BitConverter.ToUInt16(p, ofs); ofs += 2; break;
                case 2: if (p.Length < ofs + 4) return false; node = BitConverter.ToUInt32(p, ofs); ofs += 4; break;
                default: return false;
            }
            int method;
            if (nameComp == 0) { if (p.Length < ofs + 1) return false; method = p[ofs]; ofs += 1; }
            else { if (p.Length < ofs + 2) return false; method = BitConverter.ToUInt16(p, ofs); ofs += 2; }

            int end = p.Length;
            string nodePath;
            if ((node & 0x80000000u) != 0)
            {
                int pathOfs = (int)(node & 0x7FFFFFFF);
                if (pathOfs > p.Length) return false;
                nodePath = Encoding.UTF8.GetString(p, pathOfs, p.Length - pathOfs).TrimEnd('\0');
                end = pathOfs;
            }
            else if (!_paths.TryGetValue(node, out nodePath)) return false;
            if (!nodePath.EndsWith("Net")) return false;
            if ((method & 0x8000) != 0 || method >= Methods.Length) return false;

            object[] args;
            if (byteOnly)
            {
                if (ofs < end)
                {
                    var b = new byte[end - ofs];
                    Buffer.BlockCopy(p, ofs, b, 0, b.Length);
                    args = new object[] { b };
                }
                else args = new object[0];
            }
            else
            {
                if (ofs >= end) return false;
                int argc = p[ofs++];
                args = new object[argc];
                for (int i = 0; i < argc; i++) args[i] = GodotVariant.DecodeCompressed(p, ref ofs, end);
            }
            rpc = new Rpc { method = Methods[method], args = args };
            return true;
        }

        public void Reset() => _paths.Clear();
    }
}
