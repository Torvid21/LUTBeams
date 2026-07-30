// I dedicate this work to the public domain. Do as you will.
// Initial implementation by Torvid
// Optimizations by ValueFactory
// Tweaks and MDMX integration by Micca

Shader "LUTBeam/VideoExample"
{
    Properties
    {
        [NoScaleOffset] _GoboTex ("Gobo Array", 2D) = "white" {}
        [NoScaleOffset] _GoboLUT ("LUT Array", 2D) = "white" {}
        
        [Header(Shape)]
        _AngleX ("_AngleX", Range(0, 2.0)) = 0.1
        _AngleY ("_AngleY", Range(0, 2.0)) = 0.1
        _Offset ("_Offset", Range(-1,1)) = 0.25
        _NearRadius ("_NearRadius", Range(0,1)) = 0.1
        _FarZ ("_FarZ", Float) = 25
        _Gobo ("_Gobo", Float) = 0
            
        [Header(Color)]
        _Color ("Emission Color", Color) = (1, 1, 1, 1)
        _BeamIntensity ("_BeamIntensity", Range(0, 4.0)) = 1
        _GoboIntensity ("_GoboIntensity", Range(0, 4.0)) = 1
        _Hotness ("_Hotness", Range(0, 3.0)) = 1
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
            
            float _Offset;
            float _NearRadius;
            float _FarZ;
            float _AngleX;
            float _AngleY;
            float4 _Color;
            float _GoboIntensity;
            float _BeamIntensity;
            float _Hotness;

            v2f vert(appdata v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                o.beam = LUTBeamVert(v.vertex, _AngleX, _AngleY, _FarZ, _NearRadius, _Offset, _Color, _BeamIntensity, _GoboIntensity, _Hotness);

                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                float3 col = LUTBeamFrag(i.beam, 0, true, _Hotness);
                return float4(col, 0);
            }
            ENDCG
        }
    }
}
