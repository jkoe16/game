// 스스로 빛나는 단색 (조명 영향 없음): 가로등, 분수 물방울, 포털 바닥 등
Shader "PartyWorld/Glow"
{
    Properties { _Color ("Color", Color) = (1,1,1,1) _Energy ("Energy", Range(0,4)) = 1 }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #include "UnityCG.cginc"
            fixed4 _Color; half _Energy;
            struct v2f { float4 pos : SV_POSITION; UNITY_FOG_COORDS(0) };
            v2f vert (appdata_base v) { v2f o; o.pos = UnityObjectToClipPos(v.vertex); UNITY_TRANSFER_FOG(o, o.pos); return o; }
            fixed4 frag (v2f i) : SV_Target
            {
                fixed4 c = fixed4(saturate(_Color.rgb * (0.75 + 0.25 * _Energy)), 1);
                UNITY_APPLY_FOG(i.fogCoord, c);
                return c;
            }
            ENDCG
        }
    }
}
