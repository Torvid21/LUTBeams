Shader "LUTBeam/Video"
{
    Properties
    {
        [NoScaleOffset] _GoboTex ("Gobo Texture", 2D) = "white" {}
        [NoScaleOffset] _GoboLUT ("LUT Texture", 2D) = "white" {}
        
        [Header(Shape)]
        _ZoomX ("_ZoomX", Range(0, 120.0)) = 45
        _ZoomY ("_ZoomY", Range(0, 120.0)) = 30
        _Offset ("_Offset", Range(-1,1)) = 0.0
        _NearSizeX ("_NearSizeX", Range(0,1)) = 0.1
        _NearSizeY ("_NearSizeY", Range(0,1)) = 0.1
        _FarZ ("_FarZ", Float) = 25
        _Gobo ("Gobo Index", Integer) = 0
        
        [Header(Color)]
        _Color ("Color", Color) = (1, 1, 1, 1)
        _BeamIntensity ("_BeamIntensity", Range(0, 4.0)) = 1
        _BeamFalloff ("_BeamFalloff", Range(0, 3.0)) = 1
        _GoboIntensity ("_GoboIntensity", Range(0, 4.0)) = 1
        
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
        Tags {"RenderType"="Transparent" "Queue"="Transparent+304" }
        
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
            Texture2D _GoboTex;
            Texture2D _GoboLUT;
            float _Offset;
            float _NearSizeX;
            float _NearSizeY;
            float _FarZ;
            float _ZoomX;
            float _ZoomY;
            float4 _Color;
            float _GoboIntensity;
            float _BeamIntensity;
            float _BeamFalloff;
            float _Gobo;
            
            #define LUTBEAM_CALLBACK_PROJECTION LUTBeamCallbackProjection
            float3 LUTBeamCallbackProjection(SamplerState samp, float2 uv, float mip)
            {
                return _GoboTex.SampleLevel(samp, float3(uv, _Gobo), mip).rgb;
            }

            #define LUTBEAM_CALLBACK_VOLUME LUTBeamCallbackVolume
            float3 LUTBeamCallbackVolume(SamplerState samp, float2 uv, float mip)
            {
                return _GoboLUT.SampleLevel(samp, float3(uv, _Gobo), mip).rgb;
            }
            #define LUTBEAM_CALLBACK_VERTEX LUTBeamCallbackTransform
            float3 LUTBeamCallbackTransform(float3 vertex)
            {
                return vertex + float3(0, 0, _Offset);
            }

            #include "Assets/LUTBeam/LUTBeam.cginc"
        
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

                BeamSettings settings = DefaultBeamSettings();
                settings.zoomX = _ZoomX;
                settings.zoomY = _ZoomY;
                settings.farz = _FarZ;
                settings.nearSizeX = _NearSizeX;
                settings.nearSizeY = _NearSizeY;
                settings.color = _Color;
                settings.brightnessVolume = _BeamIntensity;
                settings.brightnessGobo = _GoboIntensity;
                settings.beamFalloff = _BeamFalloff;

                o.beam = LUTBeamVert(v.vertex, settings);

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
