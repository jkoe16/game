using UnityEngine;

namespace PartyWorld
{
    /// <summary>
    /// 이동 테스트용 회색 연습장: 바닥, 계단(0.3m·0.4m), 완만한 경사(30°)와 가파른 경사(55°),
    /// 점프 발판, 벽, 낭떠러지. Godot 판과 이동 느낌을 비교하기 위한 맵.
    /// </summary>
    public static class PracticeMap
    {
        public static readonly Vector3 Spawn = new Vector3(0f, 0.5f, 0f);

        public static void Build()
        {
            var root = new GameObject("PracticeMap").transform;

            // 빛과 하늘색
            var sun = new GameObject("Sun").AddComponent<Light>();
            sun.type = LightType.Directional;
            sun.intensity = 1.2f;
            sun.shadows = LightShadows.Soft;
            sun.transform.rotation = Quaternion.Euler(50f, -30f, 0f);
            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Flat;
            RenderSettings.ambientLight = new Color(0.62f, 0.66f, 0.78f);

            var grass = Mat(new Color(0.55f, 0.82f, 0.5f));
            var stone = Mat(new Color(0.85f, 0.82f, 0.78f));
            var blue = Mat(new Color(0.55f, 0.75f, 1f));
            var pink = Mat(new Color(1f, 0.6f, 0.7f));

            // 바닥 40×40 (위 표면 y = 0)
            Box(root, new Vector3(0f, -0.5f, 0f), new Vector3(40f, 1f, 40f), grass);

            // 계단 0.3m × 6칸 (앞쪽 +Z)
            FixStairs(root, stone, -6f, 0.3f, 6);
            // 오를 수 없는 계단 0.4m
            FixStairs(root, pink, -10f, 0.4f, 4);

            // 경사 30° (오를 수 있음), 55° (미끄러짐)
            Ramp(root, new Vector3(4f, 0f, 8f), 30f, 8f, blue);
            Ramp(root, new Vector3(9f, 0f, 8f), 55f, 6f, pink);

            // 점프 발판: 높이 1.2 / 1.6 / 1.9 m (점프 최고 높이 ≈ 1.92 m)
            Box(root, new Vector3(0f, 0.6f, -6f), new Vector3(2f, 1.2f, 2f), stone);
            Box(root, new Vector3(3.5f, 0.8f, -6f), new Vector3(2f, 1.6f, 2f), stone);
            Box(root, new Vector3(7f, 0.95f, -6f), new Vector3(2f, 1.9f, 2f), pink);
            // 징검다리 (간격 점점 넓게)
            for (int i = 0; i < 5; i++)
                Box(root, new Vector3(-8f - i * (2.2f + i * 0.4f), 1f, -8f), new Vector3(1.2f, 0.4f, 1.2f), blue);

            // 벽 (부딪혀 미끄러지기 확인)
            Box(root, new Vector3(12f, 1.5f, -2f), new Vector3(0.5f, 3f, 10f), stone);

            // 낭떠러지 쪽 섬 (떨어지면 리스폰)
            Box(root, new Vector3(0f, -0.5f, 26f), new Vector3(6f, 1f, 6f), grass);
        }

        static void FixStairs(Transform root, Material m, float x, float step, int count)
        {
            // 각 칸을 바닥부터 쌓은 기둥으로 (틈 없이)
            for (int i = 0; i < count; i++)
            {
                float h = step * (i + 1);
                Box(root, new Vector3(x, h * 0.5f, 6f + i * 0.6f), new Vector3(3f, h, 0.6f), m);
            }
        }

        static void Ramp(Transform root, Vector3 foot, float angleDeg, float length, Material m)
        {
            float a = angleDeg * Mathf.Deg2Rad;
            float h = Mathf.Sin(a) * length, d = Mathf.Cos(a) * length;
            var g = Box(root, Vector3.zero, new Vector3(3f, 0.3f, length), m);
            g.transform.rotation = Quaternion.Euler(-angleDeg, 0f, 0f);
            g.transform.position = foot + new Vector3(0f, h * 0.5f, d * 0.5f) - g.transform.up * 0.15f;
        }

        public static GameObject Box(Transform parent, Vector3 pos, Vector3 size, Material m)
        {
            var g = GameObject.CreatePrimitive(PrimitiveType.Cube);
            g.transform.SetParent(parent, false);
            g.transform.position = pos;
            g.transform.localScale = size;
            g.GetComponent<Renderer>().sharedMaterial = m;
            g.isStatic = true;
            return g;
        }

        static Material _base;

        public static Material Mat(Color c)
        {
            // 기본 도형의 재질을 복제해서 색만 바꾼다 → URP/기본 렌더러 어느 쪽이든, 웹 빌드에서도 셰이더가 빠지지 않음
            if (_base == null)
            {
                var tmp = GameObject.CreatePrimitive(PrimitiveType.Cube);
                _base = tmp.GetComponent<Renderer>().sharedMaterial;
                Object.Destroy(tmp);
            }
            var m = new Material(_base) { color = c };
            if (m.HasProperty("_Smoothness")) m.SetFloat("_Smoothness", 0.1f);
            if (m.HasProperty("_Glossiness")) m.SetFloat("_Glossiness", 0.1f);
            return m;
        }
    }
}
