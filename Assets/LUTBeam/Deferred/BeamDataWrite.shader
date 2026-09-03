Shader "LUTBeam/CRT"
{
    Properties
    {
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
        
        [Header(Focus)]
        [Toggle(LUTBEAM_FOCUS)]   _FocusEnabled   ("Enable",    Float) = 0
        _Focus ("_Focus", Range(0, 1.0)) = 0
        _Focus_ApertureSize ("_Focus_ApertureSize", Range(0, 1.0)) = 1
        _Frost ("_Frost", Range(0, 1.0)) = 0
    }

    SubShader
    {
        Lighting Off
        Blend Off

        Pass
        {
            CGPROGRAM
            #pragma vertex CustomRenderTextureVertexShader
            #pragma fragment frag
            #pragma target 4.5

            #define _SelfTexture2D _SelfTexture2D_unused
            #include "UnityCustomRenderTexture.cginc"
            #undef _SelfTexture2D

            Texture2D<float4> _SelfTexture2D;
            float _ZoomX;
            float _ZoomY;

            float4 frag(v2f_customrendertexture i) : SV_Target
            {
                int2 px = int2(i.vertex.xy);
                
                // WorldPosXYZ, BeamIntensity
                // ForwardXYZ, BeamFalloff
                // UpXYZ, GoboIntensity
                // ZoomXY, _NearSizeXY
                // ColorRGB, FarZ
                // Gobo, _Focus, _Focus_ApertureSize, _Frost
                // _Framing0A _Framing0B _Framing1A _Framing1B
                // _Framing2A _Framing2B _Framing3A _Framing3B
                if(px.x == 0)
                {
                    if(px.y == 0) return float4(0.0, 0.0, 0.0, 1.0);
                    if(px.y == 1) return float4(0.0, 0.0, 1.0, 1.0);
                    if(px.y == 2) return float4(0.0, 1.0, 0.0, 1.0);
                    if(px.y == 3) return float4(_ZoomX, _ZoomY, 0.5, 0.5);
                    if(px.y == 4) return float4(1.0, 0.5, 1.0, 100);
                    if(px.y == 5) return float4(2.0, 0.0, 0.0, 0.0);
                }
                else if(px.x == 1)
                {
                    if(px.y == 0) return float4(0.0, 0.0, 8.0, 1.0);
                    if(px.y == 1) return float4(0.0, 0.0, 1.0, 1.0);
                    if(px.y == 2) return float4(0.0, 1.0, 0.0, 1.0);
                    if(px.y == 3) return float4(_ZoomX, _ZoomY, 0.5, 0.5);
                    if(px.y == 4) return float4(0.1, 0.1, 1.0, 100);
                    if(px.y == 5) return float4(2.0, 0.0, 0.0, 0.0);
                }

                return 0;

            }
            ENDCG
        }
    }
}