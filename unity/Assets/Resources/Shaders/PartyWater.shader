// 반투명 물 (분수)
Shader "PartyWorld/Water"
{
    Properties { _Color ("Color", Color) = (0.55,0.85,1,0.85) }
    SubShader
    {
        Tags { "Queue"="Transparent" "RenderType"="Transparent" }
        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            fixed4 _Color;
            struct v2f { float4 pos : SV_POSITION; float3 wn : TEXCOORD0; float3 wp : TEXCOORD1; };
            v2f vert (appdata_base v) { v2f o; o.pos = UnityObjectToClipPos(v.vertex); o.wn = UnityObjectToWorldNormal(v.normal); o.wp = mul(unity_ObjectToWorld, v.vertex).xyz; return o; }
            fixed4 frag (v2f i) : SV_Target
            {
                float3 v = normalize(_WorldSpaceCameraPos - i.wp);
                float rim = pow(1 - saturate(dot(normalize(i.wn), v)), 2);
                float wave = 0.04 * sin(i.wp.x * 3 + _Time.y * 2) * sin(i.wp.z * 3 + _Time.y * 1.7);
                return fixed4(_Color.rgb + rim * 0.35 + wave, _Color.a);
            }
            ENDCG
        }
    }
}
