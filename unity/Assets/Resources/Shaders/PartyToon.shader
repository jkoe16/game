// 3D PARTY WORLD 공용 카툰 셰이더 (Godot shaders/toon.gdshader 이식, 내장 렌더 파이프라인)
// 부드러운 2단 셀 음영 + 파스텔 그림자색 + 은은한 하이라이트 + 림 라이트. 텍스처 없이 색만 사용.
Shader "PartyWorld/Toon"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _ShadowTint ("Shadow Tint", Color) = (0.66,0.64,0.95,1)
        _ShadowStrength ("Shadow Strength", Range(0,1)) = 0.3
        _BandSoftness ("Band Softness", Range(0.001,0.8)) = 0.32
        _RimStrength ("Rim Strength", Range(0,1)) = 0.14
        _Gloss ("Gloss", Range(0,1)) = 0.12
        _Emission ("Emission", Range(0,4)) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        Pass
        {
            Tags { "LightMode"="ForwardBase" }
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fwdbase
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            #include "AutoLight.cginc"

            fixed4 _ShadowTint;
            half _ShadowStrength, _BandSoftness, _RimStrength, _Gloss, _Emission;
            UNITY_INSTANCING_BUFFER_START(Props)
                UNITY_DEFINE_INSTANCED_PROP(fixed4, _Color)
            UNITY_INSTANCING_BUFFER_END(Props)

            struct appdata { float4 vertex : POSITION; float3 normal : NORMAL; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct v2f
            {
                float4 pos : SV_POSITION;
                float3 wn : TEXCOORD0;
                float3 wp : TEXCOORD1;
                SHADOW_COORDS(2)
                UNITY_FOG_COORDS(3)
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            v2f vert (appdata v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                o.pos = UnityObjectToClipPos(v.vertex);
                o.wn = UnityObjectToWorldNormal(v.normal);
                o.wp = mul(unity_ObjectToWorld, v.vertex).xyz;
                TRANSFER_SHADOW(o);
                UNITY_TRANSFER_FOG(o, o.pos);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                fixed3 albedo = UNITY_ACCESS_INSTANCED_PROP(Props, _Color).rgb;
                float3 n = normalize(i.wn);
                float3 v = normalize(_WorldSpaceCameraPos - i.wp);
                float3 l = normalize(_WorldSpaceLightPos0.xyz);
                float atten = SHADOW_ATTENUATION(i);
                float ndl = dot(n, l);
                float lit = smoothstep(-0.05, _BandSoftness, ndl) * atten;
                float3 shade = lerp(_ShadowTint.rgb * (1.0 - _ShadowStrength), float3(1,1,1), lit);
                // 반대편 하늘빛 보조광 + 하늘(주변광)
                float fill = saturate(dot(n, -l) * 0.5 + 0.2) * 0.14;
                float3 ambient = ShadeSH9(float4(n, 1)) * 0.45;
                float3 col = albedo * (shade * _LightColor0.rgb * 0.82 + ambient + fill * float3(0.75,0.82,1.0));
                float rim = pow(1.0 - saturate(dot(n, v)), 2.6);
                col += albedo * (rim * _RimStrength + saturate(n.y * 0.5 + 0.5) * 0.02);
                float3 h = normalize(l + v);
                col += _LightColor0.rgb * smoothstep(0.92, 0.985, dot(n, h)) * _Gloss * atten;
                col += albedo * _Emission;
                fixed4 c = fixed4(col, 1);
                UNITY_APPLY_FOG(i.fogCoord, c);
                return c;
            }
            ENDCG
        }
        Pass
        {
            Tags { "LightMode"="ShadowCaster" }
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_shadowcaster
            #pragma multi_compile_instancing
            #include "UnityCG.cginc"
            struct v2f { V2F_SHADOW_CASTER; };
            v2f vert (appdata_base v) { v2f o; UNITY_SETUP_INSTANCE_ID(v); TRANSFER_SHADOW_CASTER_NORMALOFFSET(o) return o; }
            float4 frag (v2f i) : SV_Target { SHADOW_CASTER_FRAGMENT(i) }
            ENDCG
        }
    }
}
