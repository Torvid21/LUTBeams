Shader "LUTBeam/SpinExample"
{
    Properties
    {
        [NoScaleOffset] _GoboTex ("Gobo Texture", 2DArray) = "white" {}
        [NoScaleOffset] _GoboLUT ("LUT Texture", 2DArray) = "white" {}

        [Header(Shape)]
        _Zoom ("_Zoom", Range(0, 2.0)) = 0.1
        _Offset ("_Offset", Range(-1,1)) = 0.25
        _NearRadius ("_NearRadius", Range(0,1)) = 0.1
        _FarZ ("_FarZ", Float) = 25
        _Gobo ("Gobo Index", Integer) = 0
        _SpinSpeed ("_SpinSpeed", Float) = 0.1
            
        [Header(Color)]
        _Color ("Color", Color) = (1, 1, 1, 1)
        _BeamIntensity ("_BeamIntensity", Range(0, 8.0)) = 1
        _BeamFalloff ("_BeamFalloff", Range(0, 3.0)) = 1
        _GoboIntensity ("_GoboIntensity", Range(0, 8.0)) = 1
    }
    SubShader
    {
        Tags {"RenderType"="Transparent" "Queue"="Transparent+303" }

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

            Texture2DArray _GoboTex;
            Texture2DArray _GoboLUT;
            float _Offset;
            float _NearRadius;
            float _FarZ;
            float _Zoom;
            float _Gobo;
            float4 _Color;
            float _GoboIntensity;
            float _BeamIntensity;
            float _BeamFalloff;
            float _SpinSpeed;
                
            #define LUTBEAM_CALLBACK_PROJECTION 1
            float3 LUTBeamCallbackProjection(SamplerState samp, float2 uv)
            {
                return _GoboTex.SampleLevel(samp, float3(uv, _Gobo), 0).rrr;
            }
            #define LUTBEAM_CALLBACK_VOLUME 1
            float3 LUTBeamCallbackVolume(SamplerState samp, float2 uv)
            {
                return _GoboLUT.SampleLevel(samp, float3(uv, _Gobo), 0).rrr;
            }
            
            #define LUTBEAM_CALLBACK_TRANSFORM 1
            float3x3 LUTBeamCallbackTransform(float3 vertex, inout float3 worldPositionOffset)
            {
                float spin = _Time.g*_SpinSpeed;

                float3x3 spinMatrix3 = float3x3(
                    cos(spin), -sin(spin), 0,
                    sin(spin),  cos(spin), 0,
                    0,         0,          1
                );
                return spinMatrix3;
            }
            #include "Assets/LUTBeam/LUTBeam.cginc"
        
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 5.0

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
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

                // simulate dimming that happens when the gobo is zoomed out
                float zoomFade = lerp(1, 0.1, saturate(_Zoom*0.5));

                // make sure you feed in v.vertex from the unity default cube here directly without modifying it
                // otherwise things may go wroooonngggg :)
                o.beam = LUTBeamVert(v.vertex, _Zoom, _Zoom, _FarZ, _NearRadius, _Offset, _Color * zoomFade, _BeamIntensity, _GoboIntensity, _BeamFalloff);

                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                
                float3 col = LUTBeamFrag(i.beam, _BeamFalloff);
                return float4(col, 0);
            }
            ENDCG
        }
    }
}
