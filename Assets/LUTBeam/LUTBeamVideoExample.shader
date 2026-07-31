Shader "LUTBeam/VideoExample"
{
    Properties
    {
        [NoScaleOffset] _GoboTex ("Gobo Texture", 2D) = "white" {}
        [NoScaleOffset] _GoboLUT ("LUT Texture", 2D) = "white" {}
        
        [Header(Shape)]
        _ZoomX ("_ZoomX", Range(0, 2.0)) = 0.1
        _ZoomY ("_ZoomY", Range(0, 2.0)) = 0.1
        _Offset ("_Offset", Range(-1,1)) = 0.25
        _NearRadius ("_NearRadius", Range(0,1)) = 0.1
        _FarZ ("_FarZ", Float) = 25
        _Gobo ("_Gobo", Float) = 0
        
        [Header(Color)]
        _Color ("Color", Color) = (1, 1, 1, 1)
        _BeamIntensity ("_BeamIntensity", Range(0, 4.0)) = 1
        _BeamHotness ("_BeamHotness", Range(0, 3.0)) = 1
        _GoboIntensity ("_GoboIntensity", Range(0, 4.0)) = 1
    }
    SubShader
    {
        Tags {"RenderType"="Transparent" "Queue"="Transparent+304" }

        LOD 100

        Cull Back
        ZTest LEqual
        ZWrite Off


        Pass
        {
            Name "LUTBeam"
            Blend One One
            CGPROGRAM
            
            #pragma multi_compile_instancing

            #include "UnityCG.cginc"
            Texture2D _GoboTex;
            Texture2D _GoboLUT;
            float _Offset;
            float _NearRadius;
            float _FarZ;
            float _ZoomX;
            float _ZoomY;
            float4 _Color;
            float _GoboIntensity;
            float _BeamIntensity;
            float _BeamHotness;

            #define LUTBEAM_CALLBACK_GOBO 1
            float3 LUTBeamCallbackGobo(SamplerState samp, float2 uv)
            {
                return _GoboTex.SampleLevel(samp, uv, 0).rgb;
            }
            #define LUTBEAM_CALLBACK_VOLUME 1
            float3 LUTBeamCallbackVolume(SamplerState samp, float2 uv)
            {
                return _GoboLUT.SampleLevel(samp, uv, 0).rgb;
            }
            #include "LUTBeam.cginc"
        
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 5.0

            struct appdata
            {
                float4 vertex : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                BeamData beam;

                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };
            
            v2f vert(appdata v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                o.beam = LUTBeamVert(v.vertex, _ZoomX, _ZoomY, _FarZ, _NearRadius, _Offset, _Color, _BeamIntensity, _GoboIntensity, _BeamHotness);

                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                float3 col = LUTBeamFrag(i.beam, _BeamHotness);
                return float4(col, 0);
            }
            ENDCG
        }
    }
}
