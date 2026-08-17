Shader "Unlit/DebugBuffers"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
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
            // make fog work
            #pragma multi_compile_fog
        
            #include "UnityCG.cginc"
            #include "GpuPrinter.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            
            Texture2D _CameraDepthTexture;
            Texture2D _GrabTexture;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }


            fixed4 frag (v2f i) : SV_Target
            {
                uint Width = 0;
                uint Height = 0;
                _CameraDepthTexture.GetDimensions(Width, Height);
                float col = 0;
                col += DrawNumberAtPxPos(i.uv*200, float2(100, 100+20), Width);
                col += DrawNumberAtPxPos(i.uv*200, float2(100, 100+40), Height);
                return col;
            }
            ENDCG
        }
    }
}
