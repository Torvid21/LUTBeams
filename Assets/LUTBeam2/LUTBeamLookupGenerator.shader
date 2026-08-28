// I dedicate this work to the public domain. Do as you will.
// Initial implementation by Torvid
// Optimizations by ValueFactory
// Tweaks and MDMX integration by Micca

Shader "Unlit/GoboLookupGenerator"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Small ("_Small", Float) = 0
        _StepCount ("_StepCount", Float) = 100
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
            // make fog work
            #pragma multi_compile_fog
            float _Small;
            float _StepCount;

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            float _Angle;
            float _RayAngle;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }

            // takes a point at the edge of the square and turns it into a piecewise value
            float EdgeEncode(float2 p)
            {
                if (abs(p.y - 0.0) < 1e-5) return p.x * 0.25;
                else if (abs(p.x - 1.0) < 1e-5) return 0.25 + p.y * 0.25;
                else if (abs(p.y - 1.0) < 1e-5) return 0.5 + (1.0 - p.x) * 0.25;
                else if (abs(p.x - 0.0) < 1e-5) return 0.75 + (1.0 - p.y) * 0.25;
                return 0.0;
            }
            
            // creates a point at the edge of the unit square from t going around the square
            float2 EdgeDecode(float t)
            {
                t = frac(t);
                float ft = t * 4.0;
                if (ft < 1.0) return float2(ft, 0.0);
                else if (ft < 2.0) return float2(1.0, ft - 1.0);
                else if (ft < 3.0) return float2(3.0 - ft, 1.0);
                else return float2(0.0, 4.0 - ft);
            }

            fixed4 frag (v2f input) : SV_Target
            {
                float size = 32;
                float2 start = 0;
                float2 end  = 0;
                if(_Small)
                {
                    //start = floor(input.uv * size) / size;

                    start = EdgeDecode(floor(input.uv.x * size) / size);
                    end = frac(float2(input.uv.x * size, input.uv.y));
                    //end  = EdgeDecode(input.uv.y);
                    //return float4(0,0,0,0);
                }
                else
                {
                    start = floor(input.uv * size) / size;
                    end = frac(input.uv * size);
                }

                float4 result = 0;
                for (int i = 0; i < _StepCount; i++)
                {
                    float t = i / (_StepCount-1);

                    float2 pos = lerp(start, end, t);
                    
                    //float2 up = start-end;
                    //up = float2(-up.y, up.x);
                    //pos += up * sin((t+_Time.g)*4)*0.3;
                    
                    result += tex2Dlod(_MainTex, float4(pos, 0, 0));
                }
                result /= _StepCount;
                result.a = 1;
                
                return result;
            }
            ENDCG
        }
    }
}
