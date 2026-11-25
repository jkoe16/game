// 캐릭터 발밑 동그란 그림자 (Godot character_visual.gd _build_shadow 의 방사형 그라디언트)
Shader "PartyWorld/BlobShadow"
{
    Properties
    {
        _Alpha ("Alpha", Range(0,1)) = 1
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent-10" "IgnoreProjector"="True" }
        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off
        Cull Off
        Offset -1, -1
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            half _Alpha;
            struct v2f { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };
            v2f vert (appdata_base v) { v2f o; o.pos = UnityObjectToClipPos(v.vertex); o.uv = v.texcoord.xy; return o; }
            fixed4 frag (v2f i) : SV_Target
            {
                float r = length(i.uv * 2.0 - 1.0);
                float a = r < 0.55 ? lerp(0.55, 0.38, r / 0.55) : lerp(0.38, 0.0, saturate((r - 0.55) / 0.45));
                return fixed4(0.18, 0.14, 0.32, a * _Alpha);
            }
            ENDCG
        }
    }
}
