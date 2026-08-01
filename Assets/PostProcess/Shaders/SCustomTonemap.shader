Shader "Silent/CustomRenderTexture/CustomTonemap"
{
    Properties
    {
        [HeaderEx(Tonemapper Settings)]
        [Enum(Gran Turismo, 0, AgX, 1, Khronos Neutral, 2, Tony McMapface, 3, Gran Turismo 7, 4, Debug None, 99)] _TonemapperType("Tonemapper", Float) = 0
        
        [Space]
        [IfSet(_TonemapperType, 1)]
        [Enum(Base, 0, Golden, 1, Punchy, 2, Custom, 99)]_AgX_Look("AgX Look", Float) = 0
        [IfSet(_TonemapperType, 1)][IfSet(_AgX_Look, 99)]
        [RGBSlider(0.0, 5.0)][HDR]_AgX_Offset("Offset", Vector) = (0,0,0,0)
        [IfSet(_TonemapperType, 1)][IfSet(_AgX_Look, 99)]
        [RGBSlider(0.0, 5.0)][HDR]_AgX_Slope("Slope", Vector) = (1,1,1,1)
        [IfSet(_TonemapperType, 1)][IfSet(_AgX_Look, 99)]
        [RGBSlider(0.0, 5.0)][HDR]_AgX_Power("Power", Vector) = (1,1,1,1)
        [IfSet(_TonemapperType, 1)][IfSet(_AgX_Look, 99)]
        _AgX_Sat("Saturation", Float) = 1.0
        [Space]
        [HeaderEx(Pre Tonemap Adjustments)]
        [GradientDisplay( #409cffff, #ffffffff, #FF3800FF)]
        _AdjColorTemp("Color Temperature", Range(-4000, 4000)) = 0.0
        [Space]
        [GradientDisplay( #00FF00FF, #ffffffff, #FF00FFFF)]
        _AdjColorCast("Color Cast", Range(-100, 100)) = 0.0
        [Space]
        _AdjSaturation("Saturation", Range(0.0, 2.0)) = 1.0
        [Space]
        [RGBSlider(0.0, 5.0)]_AdjBrightness("Brightness", Vector) = (1.0, 1.0, 1.0, 1.0)
        [RGBSlider(0.0, 5.0)]_AdjContrast("Contrast", Vector) = (1.0, 1.0, 1.0, 1.0)
        [RGBSlider(0.0, 5.0)]_AdjHighlight("Highlight", Vector) = (1.0, 1.0, 1.0, 1.0)
        [Space]
        _AdjMidpointCorrection("Midpoint Correction", Range(0.0, 5.0)) = 1.0
        _AdjBlackCorrection("Black Correction", Range(-1.0, 1.0)) = 0.0
        [Space]
        [HeaderEx(Post Tonemap Adjustment LUT)]
        [NoScaleOffset]_CustomLUT1("LUT 1", 3D) = "_Lut3D" {}
        _CustomLUT1Intensity("LUT 1 Intensity", Range(0, 1)) = 0.0
        [NoScaleOffset]_CustomLUT2("LUT 2", 3D) = "_Lut3D" {}
        _CustomLUT2Intensity("LUT 2 Intensity", Range(0, 1)) = 0.0
        [Space]
        [NonModifiableTextureData][HideInInspector]_UnityLogToLinearR1("Unity Log to Linear Transform LUT", 3D) = "_Lut3D"
        [NonModifiableTextureData][HideInInspector]_TonyMcMapfaceLUT("Tony McMapface Transform LUT", 3D) = "_Lut3D"
    }

    CustomEditor "SilentCustomTonemap.Unity.CustomTonemapInspector"

    SubShader
    {
        Lighting Off
        Blend One Zero

        Tags {"PreviewType" = "Plane"}

        Pass
        {
            Name "Tonemap"
            CGPROGRAM
            #include "UnityCustomRenderTexture.cginc"
            #pragma vertex CustomRenderTextureVertexShader
            #pragma fragment frag
            #pragma target 5.0

            float _TonemapperType;
            float _AgX_Look;

            float3 _AgX_Offset;
            float3 _AgX_Slope;
            float3 _AgX_Power;
            float _AgX_Sat;

            sampler3D _UnityLogToLinearR1;

            sampler3D _CustomLUT1;
            float _CustomLUT1Intensity;
            sampler3D _CustomLUT2;
            float _CustomLUT2Intensity;

            float _AdjColorTemp;
            float _AdjColorCast;
            float _AdjSaturation;
            float3 _AdjBrightness;
            float3 _AdjContrast;
            float3 _AdjHighlight;
            float _AdjMidpointCorrection;
            float _AdjBlackCorrection;

            #include "LogColorTransform.hlsl" 
            #include "ColourGrading.hlsl" 
            #include "GranTurismoTonemapper.hlsl"
            #include "AgxTonemapper.hlsl"
            #include "KhronosNeutralTonemapper.hlsl" 
            #include "TonyMcMapfaceTonemapper.hlsl" 
            #include "GranTurismo7Tonemapper.hlsl"

            /* 
            On the PP side, external tonemapping is applied like this

            float3 colorLutSpace = saturate(LinearToLogC(colorLinear));
            float3 colorLut = ApplyLut3D(TEXTURE3D_ARGS(_LogLut3D, sampler_LogLut3D), colorLutSpace, _LogLut3D_Params.xy);
            colorLinear = lerp(colorLinear, colorLut, _LogLut3D_Params.z);

            where
            float4 _LogLut3D_Params;    // x: 1 / lut_size, y: lut_size - 1, z: contribution, w: unused
            
            half3 ApplyLut3D(TEXTURE3D_ARGS(tex, samplerTex), float3 uvw, float2 scaleOffset)
            {
                uvw.xyz = uvw.xyz * scaleOffset.yyy * scaleOffset.xxx + scaleOffset.xxx * 0.5;
                return SAMPLE_TEXTURE3D(tex, samplerTex, uvw).rgb;
            }
            */

            float3 RemapUV(float3 uv, float width, float height, float depth) {
                float3 dim = float3(width, height, depth);
                uv = floor(uv * dim) / (dim - 1.0);

                // Fix 3D slice coordinates directly
                uv.z = _CustomRenderTexture3DSlice  / (_CustomRenderTextureDepth - 1.0);

                return uv;
            }

            float4 frag(v2f_customrendertexture IN) : COLOR
            {
                float3 position = float3 (IN.localTexcoord.xyz).xyz; 
                
                float width = _CustomRenderTextureWidth;
                float height = _CustomRenderTextureHeight;
                float depth = _CustomRenderTextureDepth;
                position = RemapUV(position, width, height, depth);

                // For debugging; shouldn't be necessary
                // position = tex3D(_UnityLogToLinearR1, position);
                
                LogColorTransform lct;
                position = lct.LogCToLinear(position); 

                // Apply pre-tonemap colour grading
                ColorGradingPreset cgp = (ColorGradingPreset) 1.0;
                
                cgp.colorTemperature = _AdjColorTemp;
                cgp.colorCastAdjustment = _AdjColorCast;
                cgp.saturation = _AdjSaturation;
                cgp.brightness = _AdjBrightness;
                cgp.contrast = _AdjContrast;
                cgp.highlight = _AdjHighlight;
                cgp.midpoint = _AdjMidpointCorrection;
                cgp.blackCorrection = _AdjBlackCorrection;

                ColourGrading cg;
                position = cg.colorGradingProcess(cgp, position);

                switch (_TonemapperType)
                {
                case 0:
                {
                    GranTurismoTonemapper gtt;
                    position = gtt.Map3(position);
                    break;
                }
                case 1:
                {
                    AgxTonemapper agx;
                    position = agx.agx(position);
                    position = agx.agxLook(position);
                    position = agx.agxEotf(position);
                    break;
                }
                case 2:
                {
                    KhronosNeutralTonemapper knt;
                    position = knt.Map(position);
                    break;
                }
                case 3:
                {
                    TonyMcMapfaceTonemapper tony;
                    position = tony.map(position);
                    break;
                }
                case 4:
                {
                    GT7Tonemapper tone;
                    position = tone.ApplyToneMapping(position);
                    break;
                }
                }

                if (_CustomLUT1Intensity > 0)
                {
                    position = lerp(position, tex3D(_CustomLUT1, position), _CustomLUT1Intensity);
                }
                if (_CustomLUT2Intensity > 0)
                {
                    position = lerp(position, tex3D(_CustomLUT2, position), _CustomLUT2Intensity);
                }

                return float4(max(position, 0), 1);
            }
        ENDCG
        }
    }
}