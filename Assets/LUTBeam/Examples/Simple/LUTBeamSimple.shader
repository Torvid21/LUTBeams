Shader "LUTBeam/Simple"
{
    Properties
    {
        [NoScaleOffset] _GoboTex ("Gobo Texture", 2DArray) = "white" {}
        [NoScaleOffset] _GoboLUT ("LUT Texture", 2DArray) = "white" {}

        [Header(Shape)]
        _ZoomX ("_ZoomX", Range(0, 120.0)) = 45
        _ZoomY ("_ZoomY", Range(0, 120.0)) = 45
        _NearSizeX ("_NearSizeX", Range(0,2)) = 0.1
        _NearSizeY ("_NearSizeY", Range(0,2)) = 0.1
        _Offset ("_Offset", Range(-1,1)) = 0.25
        _FarZ ("_FarZ", Float) = 25
        [IntRange] _Gobo ("Gobo Index", Range(0,16)) = 0

        [Header(Color)]
        _Color ("Color", Color) = (1, 1, 1, 1)
        _BeamIntensity ("_BeamIntensity", Range(0, 16.0)) = 1
        _BeamFalloff ("_BeamFalloff", Range(0, 4.0)) = 1
        _GoboIntensity ("_GoboIntensity", Range(0, 16.0)) = 1
        
        //[Header(Focus)]
        //[Toggle(LUTBEAM_FOCUS)]   _FocusEnabled   ("Enable",    Float) = 0
        //_Focus ("_Focus", Range(0, 1.0)) = 0
        //_Focus_ApertureSize ("_Focus_ApertureSize", Range(0, 1.0)) = 1
        //_Frost ("_Frost", Range(0, 1.0)) = 0
        //
        //
        //[Header(Framing Shutters)]
        //[Toggle(LUTBEAM_FRAMING)] _FramingEnabled ("Enable", Float) = 0
        //    
        ////[Header(Framing 0)]
        //_Framing0A ("_Framing0A", Range(0, 1.0)) = 0
        //_Framing0B ("_Framing0B", Range(0, 1.0)) = 0
        ////[Header(Framing 1)]
        //_Framing1A ("_Framing1A", Range(0, 1.0)) = 0
        //_Framing1B ("_Framing1B", Range(0, 1.0)) = 0
        ////[Header(Framing 2)]
        //_Framing2A ("_Framing2A", Range(0, 1.0)) = 0
        //_Framing2B ("_Framing2B", Range(0, 1.0)) = 0
        ////[Header(Framing 3)]
        //_Framing3A ("_Framing3A", Range(0, 1.0)) = 0
        //_Framing3B ("_Framing3B", Range(0, 1.0)) = 0


        
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
            ColorMask RGB

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
            float _Focus;
            float _Focus_ApertureSize;
            float _Frost;
            float _Framing0A;
            float _Framing0B;
            float _Framing1A;
            float _Framing1B;
            float _Framing2A;
            float _Framing2B;
            float _Framing3A;
            float _Framing3B;
            float _FramingAngle;

            #define LUTBEAM_CALLBACK_PROJECTION LUTBeamCallbackProjection
            float3 LUTBeamCallbackProjection(SamplerState samp, float2 uv, float mip)
            {
                return _GoboTex.SampleLevel(samp, float3(uv, _Gobo), mip).rrr;
            }
            #define LUTBEAM_CALLBACK_VOLUME LUTBeamCallbackVolume
            float3 LUTBeamCallbackVolume(SamplerState samp, float2 uv, float mip)
            {
                return _GoboLUT.SampleLevel(samp, float3(uv, _Gobo), mip).rrr;
            }
            #define LUTBEAM_CALLBACK_VERTEX LUTBeamCallbackTransform
            float3 LUTBeamCallbackTransform(float3 vertex)
            {
                return vertex + float3(0,0,_Offset);
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
                //settings.focus = _Focus;
                //settings.focus_apertureSize = _Focus_ApertureSize;
                //settings.frost = _Frost;
                //settings.framing0A = _Framing0A;
                //settings.framing0B = _Framing0B;
                //settings.framing1A = _Framing1A;
                //settings.framing1B = _Framing1B;
                //settings.framing2A = _Framing2A;
                //settings.framing2B = _Framing2B;
                //settings.framing3A = _Framing3A;
                //settings.framing3B = _Framing3B;
                //settings.framingAngle = _FramingAngle;


                float ex = settings.nearSizeX*10 + tan(radians(max(settings.zoomX/2, 1))) * settings.farz;
                float ey = settings.nearSizeY*10 + tan(radians(max(settings.zoomY/2, 1))) * settings.farz;
                float minWidth = 0.05;
                settings.color *= 2 / pow(ex * ey + minWidth, 0.7);

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
