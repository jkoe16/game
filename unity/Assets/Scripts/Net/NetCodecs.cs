using System;
using System.Collections.Generic;
using System.IO;

namespace PartyWorld.Net
{
    /// <summary>네트워크 공용 상수 (Godot scripts/networking/net_config.gd 와 같아야 함)</summary>
    public static class NetConst
    {
        public const int ProtocolVersion = 3;
        public const int TickRate = 60;
        public const int InputRedundancy = 16;
        public const int InterpDelayTicks = 6;
        public const int SnapshotSilenceMs = 4000;
        public const int ReconnectGraceMs = 30000;
    }

    /// <summary>입력 한 틱 (Godot PlayerInput 과 같은 값)</summary>
    public struct WireInput
    {
        public uint seq;
        public sbyte moveX, moveZ;
        public byte flags;
    }

    /// <summary>입력 패킷: [count:u8] + count * [seq:u32, move_x:s8, move_z:s8, flags:u8] (input_codec.gd)</summary>
    public static class InputCodec
    {
        public const int MaxInputsPerPacket = 16;

        public static byte[] Encode(IList<WireInput> inputs, int start, int count)
        {
            count = Math.Min(count, MaxInputsPerPacket);
            var b = new byte[1 + count * 7];
            b[0] = (byte)count;
            int o = 1;
            for (int i = 0; i < count; i++)
            {
                var inp = inputs[start + i];
                BitConverter.GetBytes(inp.seq).CopyTo(b, o);
                b[o + 4] = (byte)inp.moveX;
                b[o + 5] = (byte)inp.moveZ;
                b[o + 6] = inp.flags;
                o += 7;
            }
            return b;
        }
    }

    /// <summary>스냅샷 속 플레이어 한 명 (snapshot_codec.gd)</summary>
    public struct SnapEntry
    {
        public const int FlagGrounded = 1, FlagFrozen = 2, FlagOut = 4;
        public int id;
        public GVec3 pos, vel;
        public float yaw, air, stun, boost, jumpBoost, shield;
        public byte flags;
        public sbyte mover;
        public uint ack, ackTick;
        public uint tick;
    }

    /// <summary>[tick:u32, count:u8] + count * 62바이트 (snapshot_codec.gd). 형식이 틀리면 null</summary>
    public static class SnapshotCodec
    {
        public const int HeaderBytes = 5, BytesPerPlayer = 62;

        public static List<SnapEntry> Decode(byte[] b, out uint tick)
        {
            tick = 0;
            if (b == null || b.Length < HeaderBytes) return null;
            tick = BitConverter.ToUInt32(b, 0);
            int count = b[4];
            if (count > 64 || b.Length != HeaderBytes + count * BytesPerPlayer) return null;
            var list = new List<SnapEntry>(count);
            int o = HeaderBytes;
            for (int i = 0; i < count; i++)
            {
                var e = new SnapEntry();
                e.id = BitConverter.ToInt32(b, o); o += 4;
                e.pos = new GVec3(F(b, ref o), F(b, ref o), F(b, ref o));
                e.vel = new GVec3(F(b, ref o), F(b, ref o), F(b, ref o));
                e.yaw = F(b, ref o);
                e.air = F(b, ref o);
                e.stun = F(b, ref o);
                e.boost = F(b, ref o);
                e.jumpBoost = F(b, ref o);
                e.shield = F(b, ref o);
                e.flags = b[o++];
                e.mover = (sbyte)b[o++];
                e.ack = BitConverter.ToUInt32(b, o); o += 4;
                e.ackTick = BitConverter.ToUInt32(b, o); o += 4;
                e.tick = tick;
                list.Add(e);
            }
            return list;
        }

        static float F(byte[] b, ref int o)
        {
            float f = BitConverter.ToSingle(b, o);
            o += 4;
            return f;
        }
    }
}
