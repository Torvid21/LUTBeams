Shader "Unlit/ScreenCopy"
{
    Properties
    {
        _MainTex ("_MainTex", 2D) = "white" {}
        _AVPRO("_AVPRO", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            SamplerState my_Trilinear_Aniso8_Clamp_sampler;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            float _AVPRO;
            Texture2D _MainTex;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                float4 color = _MainTex.Sample(my_Trilinear_Aniso8_Clamp_sampler, i.uv);
                if(_AVPRO > 0.5)
                {
                    color = _MainTex.Sample(my_Trilinear_Aniso8_Clamp_sampler, float2(i.uv.x, 1-i.uv.y));
                    color.rgb = pow(color.rgb, 2.2); // AVPro has wrong gamma (??)
                }

                // yeet to save AVPro
                if(color.a < 0.5)
                    discard;

                return float4(color.rgb, 1);
            }
            ENDCG
        }
    }
}
