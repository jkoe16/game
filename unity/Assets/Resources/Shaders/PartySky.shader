// 하늘: 위(sky top) → 지평선(horizon) → 아래 그라데이션 + 해 주변 밝음
Shader "PartyWorld/Sky"
{
    Properties
    {
        _Top ("Top", Color) = (0.38,0.62,0.98,1)
        _Horizon ("Horizon", Color) = (0.93,0.9,1,1)
        _Bottom ("Bottom", Color) = (0.3,0.5,0.8,1)
        _Curve ("Curve", Float) = 0.12
    }
    SubShader
    {
        Tags { "Queue"="Background" "RenderType"="Background" "PreviewType"="Skybox" }
        Cull Off ZWrite Off
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            fixed4 _Top, _Horizon, _Bottom; float _Curve;
            struct v2f { float4 pos : SV_POSITION; float3 dir : TEXCOORD0; };
            v2f vert (appdata_base v) { v2f o; o.pos = UnityObjectToClipPos(v.vertex); o.dir = v.vertex.xyz; return o; }
            fixed4 frag (v2f i) : SV_Target
            {
                float3 d = normalize(i.dir);
                float y = d.y;
                float3 c = y >= 0 ? lerp(_Horizon.rgb, _Top.rgb, pow(saturate(y), _Curve * 4)) : lerp(_Horizon.rgb, _Bottom.rgb, saturate(-y * 3));
                float sun = pow(saturate(dot(d, normalize(_WorldSpaceLightPos0.xyz))), 400) * 0.8;
                return fixed4(c + sun, 1);
            }
            ENDCG
        }
    }
}
