using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace PartyWorld.Net
{
    /// <summary>Godot 의 Vector3 (float 3개). UnityEngine 없이도 쓰려고 따로 둔다.</summary>
    public struct GVec3
    {
        public float x, y, z;
        public GVec3(float x, float y, float z) { this.x = x; this.y = y; this.z = z; }
        public override string ToString() => $"({x}, {y}, {z})";
    }

    /// <summary>
    /// Godot 4 의 Variant 직렬화 (core/io/marshalls.cpp + MultiplayerAPI 압축 규칙) 를 C# 으로 옮긴 것.
    /// RPC 인자를 주고받을 때 쓴다. 지원 형식: null, bool, int(long), float(double), string, Vector2/3, Color,
    /// StringName, Dictionary(Dictionary&lt;object,object&gt;), Array(List&lt;object&gt;), PackedByteArray(byte[]),
    /// PackedInt32/Int64/Float32/Float64/String/Vector3Array.
    /// 받은 값은 int 는 long, float 는 double, Vector3 는 GVec3 로 나온다.
    /// </summary>
    public static class GodotVariant
    {
        public const int NIL = 0, BOOL = 1, INT = 2, FLOAT = 3, STRING = 4, VECTOR2 = 5, VECTOR2I = 6,
            VECTOR3 = 9, VECTOR3I = 10, COLOR = 20, STRING_NAME = 21, DICTIONARY = 27, ARRAY = 28,
            PACKED_BYTE_ARRAY = 29, PACKED_INT32_ARRAY = 30, PACKED_INT64_ARRAY = 31, PACKED_FLOAT32_ARRAY = 32,
            PACKED_FLOAT64_ARRAY = 33, PACKED_STRING_ARRAY = 34, PACKED_VECTOR2_ARRAY = 35, PACKED_VECTOR3_ARRAY = 36,
            VARIANT_MAX = 39;

        const int Flag64 = 1 << 16;

        // ------------------------------------------------------------------ 압축 (RPC 인자 하나)

        /// <summary>MultiplayerAPI::encode_and_compress_variant: bool/int 는 짧게, 나머지는 일반 형식 + 첫 바이트 = 형식</summary>
        public static void EncodeCompressed(object v, BinaryWriter w)
        {
            if (v is bool b)
            {
                w.Write((byte)((b ? 0x80 : 0) | BOOL));
                return;
            }
            if (IsInteger(v))
            {
                long val = Convert.ToInt64(v);
                if (val >= sbyte.MinValue && val <= sbyte.MaxValue) { w.Write((byte)(0 << 6 | INT)); w.Write((sbyte)val); }
                else if (val >= short.MinValue && val <= short.MaxValue) { w.Write((byte)(1 << 6 | INT)); w.Write((short)val); }
                else if (val >= int.MinValue && val <= int.MaxValue) { w.Write((byte)(2 << 6 | INT)); w.Write((int)val); }
                else { w.Write((byte)(3 << 6 | INT)); w.Write(val); }
                return;
            }
            // 일반 형식의 헤더 첫 바이트가 곧 형식 번호라 그대로 쓰면 된다
            Encode(v, w);
        }

        public static object DecodeCompressed(byte[] buf, ref int ofs, int end)
        {
            if (ofs >= end) throw new InvalidDataException("variant: empty");
            int meta = buf[ofs];
            int type = meta & 0x3F;
            int mode = meta & 0xC0;
            if (type == BOOL) { ofs += 1; return (meta & 0x80) != 0; }
            if (type == INT)
            {
                ofs += 1;
                switch (mode >> 6)
                {
                    case 0: Need(buf, ofs, 1, end); return (long)(sbyte)buf[ofs++];
                    case 1: Need(buf, ofs, 2, end); { long r = BitConverter.ToInt16(buf, ofs); ofs += 2; return r; }
                    case 2: Need(buf, ofs, 4, end); { long r = BitConverter.ToInt32(buf, ofs); ofs += 4; return r; }
                    default: Need(buf, ofs, 8, end); { long r = BitConverter.ToInt64(buf, ofs); ofs += 8; return r; }
                }
            }
            return Decode(buf, ref ofs, end, 0);
        }

        // ------------------------------------------------------------------ 일반 형식 (encode_variant)

        public static void Encode(object v, BinaryWriter w)
        {
            switch (v)
            {
                case null: w.Write((uint)NIL); return;
                case bool b: w.Write((uint)BOOL); w.Write(b ? 1u : 0u); return;
                case string s: w.Write((uint)STRING); WriteString(w, s); return;
                case float f: w.Write((uint)FLOAT); w.Write(f); return;
                case double d:
                    if ((double)(float)d == d) { w.Write((uint)FLOAT); w.Write((float)d); }
                    else { w.Write((uint)(FLOAT | Flag64)); w.Write(d); }
                    return;
                case GVec3 g: w.Write((uint)VECTOR3); w.Write(g.x); w.Write(g.y); w.Write(g.z); return;
                case byte[] bytes:
                    w.Write((uint)PACKED_BYTE_ARRAY); w.Write(bytes.Length); w.Write(bytes);
                    Pad(w, bytes.Length);
                    return;
                case Dictionary<object, object> dict:
                    w.Write((uint)DICTIONARY); w.Write(dict.Count);
                    foreach (var kv in dict) { Encode(kv.Key, w); Encode(kv.Value, w); }
                    return;
                case Dictionary<string, object> sdict:
                    w.Write((uint)DICTIONARY); w.Write(sdict.Count);
                    foreach (var kv in sdict) { Encode(kv.Key, w); Encode(kv.Value, w); }
                    return;
                case System.Collections.IList list:
                    w.Write((uint)ARRAY); w.Write(list.Count);
                    foreach (var e in list) Encode(e, w);
                    return;
            }
            if (IsInteger(v))
            {
                long val = Convert.ToInt64(v);
                if (val >= int.MinValue && val <= int.MaxValue) { w.Write((uint)INT); w.Write((int)val); }
                else { w.Write((uint)(INT | Flag64)); w.Write(val); }
                return;
            }
            throw new NotSupportedException("variant encode: " + v.GetType().Name);
        }

        public static object Decode(byte[] buf, ref int ofs, int end, int depth)
        {
            if (depth > 64) throw new InvalidDataException("variant: too deep");
            Need(buf, ofs, 4, end);
            uint header = BitConverter.ToUInt32(buf, ofs);
            ofs += 4;
            int type = (int)(header & 0xFF);
            bool is64 = (header & Flag64) != 0;
            switch (type)
            {
                case NIL: return null;
                case BOOL: Need(buf, ofs, 4, end); { bool r = BitConverter.ToUInt32(buf, ofs) != 0; ofs += 4; return r; }
                case INT:
                    if (is64) { Need(buf, ofs, 8, end); long r = BitConverter.ToInt64(buf, ofs); ofs += 8; return r; }
                    else { Need(buf, ofs, 4, end); long r = BitConverter.ToInt32(buf, ofs); ofs += 4; return r; }
                case FLOAT:
                    if (is64) { Need(buf, ofs, 8, end); double r = BitConverter.ToDouble(buf, ofs); ofs += 8; return r; }
                    else { Need(buf, ofs, 4, end); double r = BitConverter.ToSingle(buf, ofs); ofs += 4; return r; }
                case STRING:
                case STRING_NAME:
                    return ReadString(buf, ref ofs, end);
                case VECTOR2: { double x = Real(buf, ref ofs, end, is64), y = Real(buf, ref ofs, end, is64); return new List<object> { x, y }; }
                case VECTOR2I: { Need(buf, ofs, 8, end); long x = BitConverter.ToInt32(buf, ofs), y = BitConverter.ToInt32(buf, ofs + 4); ofs += 8; return new List<object> { x, y }; }
                case VECTOR3:
                {
                    float x = (float)Real(buf, ref ofs, end, is64), y = (float)Real(buf, ref ofs, end, is64), z = (float)Real(buf, ref ofs, end, is64);
                    return new GVec3(x, y, z);
                }
                case VECTOR3I: { Need(buf, ofs, 12, end); var g = new GVec3(BitConverter.ToInt32(buf, ofs), BitConverter.ToInt32(buf, ofs + 4), BitConverter.ToInt32(buf, ofs + 8)); ofs += 12; return g; }
                case COLOR:
                {
                    Need(buf, ofs, 16, end);
                    var c = new List<object> { (double)BitConverter.ToSingle(buf, ofs), (double)BitConverter.ToSingle(buf, ofs + 4), (double)BitConverter.ToSingle(buf, ofs + 8), (double)BitConverter.ToSingle(buf, ofs + 12) };
                    ofs += 16;
                    return c;
                }
                case DICTIONARY:
                {
                    SkipContainerType(buf, ref ofs, end, (int)((header >> 16) & 3));
                    SkipContainerType(buf, ref ofs, end, (int)((header >> 18) & 3));
                    Need(buf, ofs, 4, end);
                    int count = (int)(BitConverter.ToUInt32(buf, ofs) & 0x7FFFFFFF);
                    ofs += 4;
                    var d = new Dictionary<object, object>();
                    for (int i = 0; i < count; i++)
                    {
                        object k = Decode(buf, ref ofs, end, depth + 1);
                        object val = Decode(buf, ref ofs, end, depth + 1);
                        d[k ?? "<null>"] = val;
                    }
                    return d;
                }
                case ARRAY:
                {
                    SkipContainerType(buf, ref ofs, end, (int)((header >> 16) & 3));
                    Need(buf, ofs, 4, end);
                    int count = (int)(BitConverter.ToUInt32(buf, ofs) & 0x7FFFFFFF);
                    ofs += 4;
                    var list = new List<object>(Math.Min(count, 4096));
                    for (int i = 0; i < count; i++) list.Add(Decode(buf, ref ofs, end, depth + 1));
                    return list;
                }
                case PACKED_BYTE_ARRAY:
                {
                    int n = Count(buf, ref ofs, end, 1);
                    var r = new byte[n];
                    Buffer.BlockCopy(buf, ofs, r, 0, n);
                    ofs += n + PadLen(n);
                    return r;
                }
                case PACKED_INT32_ARRAY:
                {
                    int n = Count(buf, ref ofs, end, 4);
                    var r = new List<object>(n);
                    for (int i = 0; i < n; i++) { r.Add((long)BitConverter.ToInt32(buf, ofs)); ofs += 4; }
                    return r;
                }
                case PACKED_INT64_ARRAY:
                {
                    int n = Count(buf, ref ofs, end, 8);
                    var r = new List<object>(n);
                    for (int i = 0; i < n; i++) { r.Add(BitConverter.ToInt64(buf, ofs)); ofs += 8; }
                    return r;
                }
                case PACKED_FLOAT32_ARRAY:
                {
                    int n = Count(buf, ref ofs, end, 4);
                    var r = new List<object>(n);
                    for (int i = 0; i < n; i++) { r.Add((double)BitConverter.ToSingle(buf, ofs)); ofs += 4; }
                    return r;
                }
                case PACKED_FLOAT64_ARRAY:
                {
                    int n = Count(buf, ref ofs, end, 8);
                    var r = new List<object>(n);
                    for (int i = 0; i < n; i++) { r.Add(BitConverter.ToDouble(buf, ofs)); ofs += 8; }
                    return r;
                }
                case PACKED_STRING_ARRAY:
                {
                    Need(buf, ofs, 4, end);
                    int n = BitConverter.ToInt32(buf, ofs);
                    ofs += 4;
                    if (n < 0 || n > end - ofs) throw new InvalidDataException("variant: bad count");
                    var r = new List<object>(n);
                    for (int i = 0; i < n; i++) r.Add(ReadString(buf, ref ofs, end));
                    return r;
                }
                case PACKED_VECTOR3_ARRAY:
                {
                    int n = Count(buf, ref ofs, end, is64 ? 24 : 12);
                    var r = new List<object>(n);
                    for (int i = 0; i < n; i++)
                    {
                        float x = (float)Real(buf, ref ofs, end, is64), y = (float)Real(buf, ref ofs, end, is64), z = (float)Real(buf, ref ofs, end, is64);
                        r.Add(new GVec3(x, y, z));
                    }
                    return r;
                }
            }
            throw new NotSupportedException("variant decode: type " + type);
        }

        // ------------------------------------------------------------------ 도우미

        static bool IsInteger(object v) => v is int || v is long || v is short || v is sbyte || v is byte || v is ushort || v is uint;

        static void Need(byte[] buf, int ofs, int n, int end)
        {
            if (ofs < 0 || n < 0 || ofs + n > end || end > buf.Length) throw new InvalidDataException("variant: truncated");
        }

        static int Count(byte[] buf, ref int ofs, int end, int elem)
        {
            Need(buf, ofs, 4, end);
            int n = BitConverter.ToInt32(buf, ofs);
            ofs += 4;
            if (n < 0 || (long)n * elem > end - ofs) throw new InvalidDataException("variant: bad count");
            return n;
        }

        static double Real(byte[] buf, ref int ofs, int end, bool is64)
        {
            if (is64) { Need(buf, ofs, 8, end); double d = BitConverter.ToDouble(buf, ofs); ofs += 8; return d; }
            Need(buf, ofs, 4, end);
            double f = BitConverter.ToSingle(buf, ofs);
            ofs += 4;
            return f;
        }

        static void SkipContainerType(byte[] buf, ref int ofs, int end, int kind)
        {
            if (kind == 0) return;
            if (kind == 1) { Need(buf, ofs, 4, end); ofs += 4; return; }
            ReadString(buf, ref ofs, end); // 클래스 이름 / 스크립트 경로
        }

        static int PadLen(int n) => (4 - n % 4) % 4;

        static void Pad(BinaryWriter w, int n)
        {
            for (int i = PadLen(n); i > 0; i--) w.Write((byte)0);
        }

        static void WriteString(BinaryWriter w, string s)
        {
            byte[] u = Encoding.UTF8.GetBytes(s);
            w.Write(u.Length);
            w.Write(u);
            Pad(w, u.Length);
        }

        static string ReadString(byte[] buf, ref int ofs, int end)
        {
            Need(buf, ofs, 4, end);
            int n = BitConverter.ToInt32(buf, ofs);
            ofs += 4;
            if (n < 0 || n + PadLen(n) > end - ofs) throw new InvalidDataException("variant: bad string");
            string s = Encoding.UTF8.GetString(buf, ofs, n);
            ofs += n + PadLen(n);
            return s;
        }

        // ------------------------------------------------------------------ 받은 값 읽기 도우미

        public static Dictionary<object, object> Dict(object v) => v as Dictionary<object, object> ?? new Dictionary<object, object>();
        public static List<object> List(object v) => v as List<object> ?? new List<object>();

        public static object Get(Dictionary<object, object> d, string key) => d != null && d.TryGetValue(key, out var v) ? v : null;

        public static long Int(object v, long fallback = 0)
        {
            switch (v)
            {
                case long l: return l;
                case double d: return (long)d;
                case bool b: return b ? 1 : 0;
                case string s when long.TryParse(s, out var p): return p;
            }
            return fallback;
        }

        public static double Num(object v, double fallback = 0)
        {
            switch (v)
            {
                case double d: return d;
                case long l: return l;
            }
            return fallback;
        }

        public static string Str(object v, string fallback = "") => v == null ? fallback : v as string ?? Convert.ToString(v, System.Globalization.CultureInfo.InvariantCulture);
        public static bool Bool(object v) => v is bool b ? b : Int(v) != 0;
    }
}
