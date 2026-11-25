using System.Collections.Generic;
using UnityEngine;

namespace PartyWorld
{
    /// <summary>
    /// 코드로 만드는 기본 메시 (Godot BoxMesh / CylinderMesh / SphereMesh / TorusMesh / QuadMesh 대응).
    /// 같은 모양은 한 번만 만들어 재사용한다. 모두 읽기 가능 메시라 정적 합치기(static batching)가 된다.
    /// 크기 규칙은 Godot 과 같다: 상자 = 한 변 1, 원기둥 = 높이 방향 Y·가운데 기준, 구 = 반지름 r.
    /// </summary>
    public static class MeshFactory
    {
        static readonly Dictionary<string, Mesh> Cache = new Dictionary<string, Mesh>();

        static Mesh Cached(string key, System.Func<Mesh> make)
        {
            if (!Cache.TryGetValue(key, out Mesh m))
            {
                m = make();
                m.name = key;
                Cache[key] = m;
            }
            return m;
        }

        /// <summary>한 변 1 상자 (크기는 스케일로)</summary>
        public static Mesh Box() => Cached("box", () =>
        {
            var verts = new List<Vector3>();
            var norms = new List<Vector3>();
            var uvs = new List<Vector2>();
            var tris = new List<int>();
            Vector3[] dirs = { Vector3.right, Vector3.left, Vector3.up, Vector3.down, Vector3.forward, Vector3.back };
            foreach (var n in dirs)
            {
                Vector3 a = n.x != 0 ? Vector3.up : Vector3.right;
                Vector3 b = Vector3.Cross(n, a);
                int s = verts.Count;
                for (int k = 0; k < 4; k++)
                {
                    float u = (k == 1 || k == 2) ? 1 : 0, w = (k >= 2) ? 1 : 0;
                    verts.Add(n * 0.5f + a * (u - 0.5f) + b * (w - 0.5f));
                    norms.Add(n);
                    uvs.Add(new Vector2(u, w));
                }
                // 바깥에서 볼 때 시계 방향 (Unity 앞면)
                if (Vector3.Dot(Vector3.Cross(a, b), n) > 0)
                    tris.AddRange(new[] { s, s + 2, s + 1, s, s + 3, s + 2 });
                else
                    tris.AddRange(new[] { s, s + 1, s + 2, s, s + 2, s + 3 });
            }
            return Build(verts, norms, uvs, tris);
        });

        /// <summary>원기둥·원뿔 (top/bottom 반지름 다르면 원뿔대). 높이 Y, 가운데 기준</summary>
        public static Mesh Cylinder(float top, float bottom, float h, int seg = 20) =>
            Cached($"cyl/{top:0.###}/{bottom:0.###}/{h:0.###}/{seg}", () =>
            {
                var verts = new List<Vector3>();
                var norms = new List<Vector3>();
                var uvs = new List<Vector2>();
                var tris = new List<int>();
                float hy = h * 0.5f;
                float slope = (bottom - top) / Mathf.Max(h, 0.0001f);
                // 옆면 (각 꼭짓점을 따로 두어 부드러운 법선)
                for (int i = 0; i <= seg; i++)
                {
                    float a = i * Mathf.PI * 2f / seg;
                    float c = Mathf.Cos(a), s = Mathf.Sin(a);
                    Vector3 n = new Vector3(c, slope, s).normalized;
                    verts.Add(new Vector3(c * top, hy, s * top)); norms.Add(n); uvs.Add(new Vector2((float)i / seg, 1));
                    verts.Add(new Vector3(c * bottom, -hy, s * bottom)); norms.Add(n); uvs.Add(new Vector2((float)i / seg, 0));
                }
                for (int i = 0; i < seg; i++)
                {
                    int t0 = i * 2, b0 = t0 + 1, t1 = t0 + 2, b1 = t0 + 3;
                    tris.AddRange(new[] { t0, t1, b0, b0, t1, b1 });
                }
                Cap(verts, norms, uvs, tris, top, hy, seg, true);
                Cap(verts, norms, uvs, tris, bottom, -hy, seg, false);
                return Build(verts, norms, uvs, tris);
            });

        static void Cap(List<Vector3> verts, List<Vector3> norms, List<Vector2> uvs, List<int> tris, float r, float y, int seg, bool up)
        {
            if (r <= 0.0001f) return;
            Vector3 n = up ? Vector3.up : Vector3.down;
            int c = verts.Count;
            verts.Add(new Vector3(0, y, 0)); norms.Add(n); uvs.Add(new Vector2(0.5f, 0.5f));
            for (int i = 0; i <= seg; i++)
            {
                float a = i * Mathf.PI * 2f / seg;
                verts.Add(new Vector3(Mathf.Cos(a) * r, y, Mathf.Sin(a) * r)); norms.Add(n);
                uvs.Add(new Vector2(0.5f + Mathf.Cos(a) * 0.5f, 0.5f + Mathf.Sin(a) * 0.5f));
            }
            for (int i = 0; i < seg; i++)
            {
                if (up) tris.AddRange(new[] { c, c + 2 + i, c + 1 + i });
                else tris.AddRange(new[] { c, c + 1 + i, c + 2 + i });
            }
        }

        /// <summary>구 (반지름 r)</summary>
        public static Mesh Sphere(float r, int seg = 20) => Cached($"sph/{r:0.###}/{seg}", () =>
        {
            int rings = Mathf.Max(6, seg / 2);
            var verts = new List<Vector3>();
            var norms = new List<Vector3>();
            var uvs = new List<Vector2>();
            var tris = new List<int>();
            for (int y = 0; y <= rings; y++)
            {
                float v = (float)y / rings;
                float phi = v * Mathf.PI;
                for (int x = 0; x <= seg; x++)
                {
                    float u = (float)x / seg;
                    float th = u * Mathf.PI * 2f;
                    Vector3 n = new Vector3(Mathf.Sin(phi) * Mathf.Cos(th), Mathf.Cos(phi), Mathf.Sin(phi) * Mathf.Sin(th));
                    verts.Add(n * r); norms.Add(n); uvs.Add(new Vector2(u, 1 - v));
                }
            }
            for (int y = 0; y < rings; y++)
                for (int x = 0; x < seg; x++)
                {
                    int a = y * (seg + 1) + x, b = a + seg + 1;
                    tris.AddRange(new[] { a, a + 1, b, b, a + 1, b + 1 });
                }
            return Build(verts, norms, uvs, tris);
        });

        /// <summary>도넛 (Godot TorusMesh: 안쪽·바깥 반지름, 축 Y)</summary>
        public static Mesh Torus(float inner, float outer, int rings = 40, int ringSeg = 12) =>
            Cached($"torus/{inner:0.###}/{outer:0.###}/{rings}/{ringSeg}", () =>
            {
                float R = (inner + outer) * 0.5f, rr = (outer - inner) * 0.5f;
                var verts = new List<Vector3>();
                var norms = new List<Vector3>();
                var uvs = new List<Vector2>();
                var tris = new List<int>();
                for (int i = 0; i <= rings; i++)
                {
                    float a = i * Mathf.PI * 2f / rings;
                    Vector3 c = new Vector3(Mathf.Cos(a), 0, Mathf.Sin(a));
                    for (int j = 0; j <= ringSeg; j++)
                    {
                        float b = j * Mathf.PI * 2f / ringSeg;
                        Vector3 n = c * Mathf.Cos(b) + Vector3.up * Mathf.Sin(b);
                        verts.Add(c * R + n * rr); norms.Add(n); uvs.Add(new Vector2((float)i / rings, (float)j / ringSeg));
                    }
                }
                for (int i = 0; i < rings; i++)
                    for (int j = 0; j < ringSeg; j++)
                    {
                        int a = i * (ringSeg + 1) + j, b = a + ringSeg + 1;
                        tris.AddRange(new[] { a, b, a + 1, a + 1, b, b + 1 });
                    }
                return Build(verts, norms, uvs, tris);
            });

        /// <summary>XY 평면 사각형 (양면 셰이더용), 크기 w×h</summary>
        public static Mesh Quad(float w, float h) => Cached($"quad/{w:0.###}/{h:0.###}", () =>
        {
            var verts = new List<Vector3> { new Vector3(-w / 2, -h / 2), new Vector3(w / 2, -h / 2), new Vector3(w / 2, h / 2), new Vector3(-w / 2, h / 2) };
            var norms = new List<Vector3> { Vector3.back, Vector3.back, Vector3.back, Vector3.back };
            var uvs = new List<Vector2> { new Vector2(0, 0), new Vector2(1, 0), new Vector2(1, 1), new Vector2(0, 1) };
            var tris = new List<int> { 0, 2, 1, 0, 3, 2 };
            return Build(verts, norms, uvs, tris);
        });

        static Mesh Build(List<Vector3> v, List<Vector3> n, List<Vector2> uv, List<int> t)
        {
            var m = new Mesh();
            if (v.Count > 65000) m.indexFormat = UnityEngine.Rendering.IndexFormat.UInt32;
            m.SetVertices(v);
            m.SetNormals(n);
            m.SetUVs(0, uv);
            m.SetTriangles(t, 0);
            m.RecalculateBounds();
            return m;
        }
    }
}
