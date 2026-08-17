Shader "LUTBeam/Avatar"
{
    Properties
    {
        [NoScaleOffset] _GoboTex ("Gobo Texture", 2DArray) = "white" {}
        [NoScaleOffset] _GoboLUT ("LUT Texture", 2DArray) = "white" {}

        [Header(Shape)]
        _Zoom ("_Zoom", Range(0, 120.0)) = 20
        _NearSize ("_NearSize", Range(0,1)) = 0.1
        _Offset ("_Offset", Range(-1,1)) = 0.25
        _FarZ ("_FarZ", Float) = 25
        _Gobo ("Gobo Index", Integer) = 0
            
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
            float _NearSize;
            float _FarZ;
            float _Zoom;
            float _Gobo;
            float4 _Color;
            float _GoboIntensity;
            float _BeamIntensity;
            float _BeamFalloff;
            
            // For projection to look right it needs a grab pass
            // which is really bad for performance so we simply turn it off.
            #define LUTBEAM_CALLBACK_PROJECTION LUTBeamCallbackProjection
            float3 LUTBeamCallbackProjection(SamplerState samp, float2 uv, float mip)
            {
                return 0;//_GoboTex.SampleLevel(samp, float3(uv, _Gobo), mip).rrr;
            }
            #define LUTBEAM_CALLBACK_VOLUME LUTBeamCallbackVolume
            float3 LUTBeamCallbackVolume(SamplerState samp, float2 uv, float mip)
            {
                return _GoboLUT.SampleLevel(samp, float3(uv, _Gobo), mip).rrr;
            }

            // This flag disables the grab pass
            // and disables scene depth
            // since a lot of worlds don't have that.
            #define LUTBEAM_AVATAR 1
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
                settings.zoomX = _Zoom;
                settings.zoomY = _Zoom;
                settings.farz = _FarZ;
                settings.nearSizeX = _NearSize;
                settings.nearSizeY = _NearSize;
                settings.offset = _Offset;
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
