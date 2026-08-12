Shader "LUTBeam/Spin"
{
    Properties
    {
        [NoScaleOffset] _GoboTex ("Gobo Texture", 2DArray) = "white" {}
        [NoScaleOffset] _GoboLUT ("LUT Texture", 2DArray) = "white" {}

        [Header(Shape)]
        _ZoomX ("_ZoomX", Range(0, 2.0)) = 0.1
        _ZoomY ("_ZoomY", Range(0, 2.0)) = 0.1
        _NearSizeX ("_NearSizeX", Range(0,1)) = 0.1
        _NearSizeY ("_NearSizeY", Range(0,1)) = 0.1
        _Offset ("_Offset", Range(-1,1)) = 0.25
        _FarZ ("_FarZ", Float) = 25
        _Gobo ("Gobo Index", Integer) = 0
        _SpinSpeed ("_SpinSpeed", Float) = 0.1
        _Frost ("_Frost", Range(0, 1.0)) = 0
        
        [Header(Color)]
        _Color ("Color", Color) = (1, 1, 1, 1)
        _BeamIntensity ("_BeamIntensity", Range(0, 8.0)) = 1
        _BeamFalloff ("_BeamFalloff", Range(0, 3.0)) = 1
        _GoboIntensity ("_GoboIntensity", Range(0, 8.0)) = 1
        
        [Header(Stencil)]
        [IntRange] _StencilRef ("Ref", Range(0, 255)) = 142
        [IntRange] _StencilReadMask ("Read Mask", Range(0, 255)) = 255
        [IntRange] _StencilWriteMask ("Write Mask", Range(0, 255)) = 255
        [Enum(UnityEngine.Rendering.CompareFunction)] _StencilCompareFunction ("Compare Function", Float) = 6
        [Enum(UnityEngine.Rendering.StencilOp)] _StencilPassOp ("Pass Op", Float) = 0
        [Enum(UnityEngine.Rendering.StencilOp)] _StencilFailOp ("Fail Op", Float) = 0
        [Enum(UnityEngine.Rendering.StencilOp)] _StencilZFailOp ("ZFail Op", Float) = 0
    }
    SubShader
    {
        Tags {"RenderType"="Transparent" "Queue"="Transparent+303" }
        
        Stencil
        {
            Ref [_StencilRef]
            ReadMask [_StencilReadMask]
            WriteMask [_StencilWriteMask]
            Comp [_StencilCompareFunction]
            Pass [_StencilPassOp]
            Fail [_StencilFailOp]
            ZFail [_StencilZFailOp]
        }

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
            float _ZoomX;
            float _ZoomY;
            float _NearSizeX;
            float _NearSizeY;
            float _FarZ;
            float _Gobo;
            float4 _Color;
            float _GoboIntensity;
            float _BeamIntensity;
            float _BeamFalloff;
            float _SpinSpeed;
            float _Frost;

            float Lerp4(float4 c, float t)
            {
                float x = saturate(t) * 3.0;
                return lerp(lerp(lerp(c.r, c.g, saturate(x)), c.b, saturate(x - 1)), c.a, saturate(x - 2));
            }

            #define LUTBEAM_CALLBACK_PROJECTION LUTBeamCallbackProjection
            float3 LUTBeamCallbackProjection(SamplerState samp, float2 uv)
            {
                float4 result = _GoboTex.SampleLevel(samp, float3(uv, _Gobo), 0).rgba;
                return Lerp4(result, _Frost);
            }
            #define LUTBEAM_CALLBACK_VOLUME LUTBeamCallbackVolume
            float3 LUTBeamCallbackVolume(SamplerState samp, float2 uv)
            {
                float4 result = _GoboLUT.SampleLevel(samp, float3(uv, _Gobo), 0).rgba;
                return Lerp4(result, _Frost);
            }
            
            #define LUTBEAM_CALLBACK_VERTEX LUTBeamCallbackTransform
            float3 LUTBeamCallbackTransform(float3 vertex)
            {
                float spin = _Time.g * _SpinSpeed;

                float3x3 spinMatrix3 = float3x3(
                    cos(spin), -sin(spin), 0,
                    sin(spin),  cos(spin), 0,
                    0,         0,          1
                );

                return mul(spinMatrix3, vertex);
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
                float zoomFade = lerp(1, 0.1, saturate((_ZoomX+_ZoomY)*0.25));
                
                // make sure you feed in v.vertex from the unity default cube here directly without modifying it
                // otherwise things may go wroooonngggg :)
                o.beam = LUTBeamVert(v.vertex, _ZoomX, _ZoomY, _FarZ, _NearSizeX, _NearSizeY, _Offset, _Color * zoomFade, _BeamIntensity, _GoboIntensity, _BeamFalloff);

                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                
                float3 col = LUTBeamFrag(i.beam);
                return float4(col, 0);
            }
            ENDCG
        }
    }
}
