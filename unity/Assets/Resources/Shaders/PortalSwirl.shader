// 포털 안쪽 소용돌이 (Godot shaders/portal_swirl.gdshader 이식). 시간에 따라 회전, 가장자리로 갈수록 투명
Shader "PartyWorld/PortalSwirl"
{
    Properties { _Color ("Color", Color) = (1,0.6,0.8,1) _Speed ("Speed", Float) = 1.6 }
    SubShader
    {
        Tags { "Queue"="Transparent" "RenderType"="Transparent" }
        Blend One One
        ZWrite Off
        Cull Off
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            fixed4 _Color; float _Speed;
            struct v2f { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };
            v2f vert (appdata_base v) { v2f o; o.pos = UnityObjectToClipPos(v.vertex); o.uv = v.texcoord.xy; return o; }
            fixed4 frag (v2f i) : SV_Target
            {
                float2 p = i.uv * 2 - 1;
                float r = length(p);
                float a = atan2(p.y, p.x);
                float swirl = 0.5 + 0.5 * sin(a * 3 + r * 9 - _Time.y * _Speed * 3);
                float core = smoothstep(1, 0, r);
                float edge = smoothstep(1, 0.82, r);
                float3 c = lerp(_Color.rgb, float3(1,1,1), swirl * 0.45 + core * core * 0.5);
                float alpha = edge * (0.2 + 0.4 * swirl) * (0.4 + 0.35 * core);
                return fixed4(c * alpha, 1);
            }
            ENDCG
        }
    }
}
