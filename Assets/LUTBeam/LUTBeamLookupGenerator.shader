// I dedicate this work to the public domain. Do as you will.
// Initial implementation by Torvid
// Optimizations by ValueFactory
// Tweaks and MDMX integration by Micca

Shader "LUTBeam/GoboLookupGenerator" {
    Properties
    {
        _MainTex ("_MainTex", 2D) = "white" {}
        _Mask ("_Mask", 2D) = "white" {}
        _StepCount ("_StepCount", Float) = 64
        _AspectRatio ("_AspectRatio", Float) = 1
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

            float _Small;
			float _StepCount;
            
            #include "UnityCG.cginc"
            #include "Assets/LUTBeam/LUTBeam.cginc"
            
            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            sampler2D _Mask;
            float4 _MainTex_ST;
            
            float _EnableBake_Supersample;
            float _EnableBake_Gobo;
            float _Zoom;
            float _RayAngle;
            float _AspectRatio;
            
            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            #define Supersample 3

	        float2 GoldenSpiral(float step)
	        {
		        float PhiRadians = 2.3998277;
		        return float2(sin(step * PhiRadians) * step, cos(step * PhiRadians) * step);
	        }
	        float2 SpiralBlurUVOffset(float Radius, float Samples, float i)
	        {
		        return GoldenSpiral(i) / Samples * Radius;
	        }

            float4 SampleGobo(float2 uv)
            {
                uv = (uv-0.5) * 1.1 + 0.5;
                uv = saturate(uv);
                return tex2Dlod(_MainTex, float4(uv, 0, 0)) * tex2Dlod(_Mask, float4(uv, 0, 0));
            }

            float4 frag(v2f input) : SV_Target
            {
                if(_EnableBake_Gobo > 0.5)
                {
                    int samples = 100;
		            float4 result = 0;
		            for (int i = 0; i < samples; i++)
		            {
			            result.r += SampleGobo(input.uv + SpiralBlurUVOffset(0.00*0.125, samples, i)).r;
			            result.g += SampleGobo(input.uv + SpiralBlurUVOffset(0.50*0.125, samples, i)).r;
			            result.b += SampleGobo(input.uv + SpiralBlurUVOffset(0.70*0.125, samples, i)).r*0.9;
			            result.a += SampleGobo(input.uv + SpiralBlurUVOffset(1.00*0.125, samples, i)).r*0.8;
		            }
		            result /= ((float)samples);
		            return result;
                }

                if(_EnableBake_Supersample < 0.5) // fast version that's ok for realtime use
                {
                    float2 tile   = floor(input.uv * start_size);
                    float2 inTile = frac(input.uv * start_size);
                    float2 start = tile / (start_size - 1.0);
                    float2 end   = (inTile * end_size - 0.5) / (end_size - 1.0);

                    float4 result = 0;
                    for (int i = 0; i < _StepCount; i++)
                    {
                        float t = i / (_StepCount - 1);
                        float2 pos = lerp(start, end, t);
                        pos.y = (pos.y - 0.5) * _AspectRatio + 0.5;
                        result += SampleGobo(pos) * !any(pos - saturate(pos));
                    }
                    result /= _StepCount;
                    //result *= distance(start, end);
                    result.a = 1;
                
                    return result;
                }
                else // slow version, don't use this when rendering in realtime
                {
                    uint2 texel  = (uint2)floor(input.uv * (start_size * end_size));
                    uint2 posIdx = texel / (uint)end_size;
                    uint2 dirIdx = texel % (uint)end_size;

                    float2 start = posIdx / (start_size - 1.0);
                    float2 end   = dirIdx / (end_size   - 1.0);

                    float2 startPixelSize = 1.0 / (start_size - 1.0);
                    float2 endPixelSize   = 1.0 / (end_size   - 1.0);

                    float2 startScale = saturate(min(start, 1 - start) / (0.5 * startPixelSize));
                    float2 endScale = saturate(min(end,   1 - end)   / (0.5 * endPixelSize));

                    float4 result = 0;
                    
                    [loop]
                    for (int sx = 0; sx < Supersample; sx++)
                    {
                        [loop]
                        for (int sy = 0; sy < Supersample; sy++)
                        {
                            [loop]
                            for (int ex = 0; ex < Supersample; ex++)
                            {
                                [loop]
                                for (int ey = 0; ey < Supersample; ey++)
                                {
                                    float2 startOffset = (float2(sx, sy) + 0.5) / Supersample - 0.5;
                                    float2 endOffset   = (float2(ex, ey) + 0.5) / Supersample - 0.5;

                                    float2 newStart = start + startOffset * startPixelSize * startScale;
                                    float2 newEnd   = end   + endOffset   * endPixelSize * endScale;

                                    [loop]
                                    for (int i = 0; i < _StepCount; i++)
                                    {
                                        float t = i / (_StepCount - 1);
                                        float2 pos = lerp(newStart, newEnd, t);
                                        pos.y = (pos.y - 0.5) * _AspectRatio + 0.5;
                                        result += SampleGobo(pos) * !any(pos - saturate(pos));
                                    }
                                }
                            }
                        }
                    }
                    result /= _StepCount * Supersample * Supersample * Supersample * Supersample;
                    return result;
                }
            }
            ENDCG
        }
    }
}