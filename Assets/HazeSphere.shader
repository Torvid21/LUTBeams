// CC0 - Public domain - Do as you will.

Shader "FX/HazeSphere"
{
    // Fog sphere, Should to be used on the default unity sphere.
    
    Properties
    {
        [HDR] _Color("Color", Color) = (0.64, 0.77, 0.94, 1)
        _Opacity("Opacity", Range(0, 10.0)) = 1.0
        _Softness("_Softness", Range(0, 10.0)) = 0.0
    }
    SubShader
    {
        Tags { "Queue" = "Transparent" }
        LOD 100
        
        Blend SrcAlpha OneMinusSrcAlpha
        Cull Back
        ZTest LEqual
        ZWrite Off
        
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            
            #include "UnityCG.cginc"
            
            struct appdata
            {
                float4 vertex : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            struct v2f
            {
                float4 vertex : SV_POSITION;
                float radiusScale   : TEXCOORD1;
                float3 rayDir       : TEXCOORD2;
                float3 rayOrigin    : TEXCOORD3;
                float mirrorFade    : TEXCOORD4;
                noperspective float2 screenPosition : TEXCOORD5;
                noperspective float frustumCorrection : TEXCOORD6;

                UNITY_VERTEX_INPUT_INSTANCE_ID 
            };
            
            UNITY_INSTANCING_BUFFER_START(Props)
                UNITY_DEFINE_INSTANCED_PROP(float4, _Color)
                UNITY_DEFINE_INSTANCED_PROP(float, _Opacity)
                UNITY_DEFINE_INSTANCED_PROP(float, _Softness)
            UNITY_INSTANCING_BUFFER_END(Props)

            float4 CalculateFrustumCorrection()
            {
                float x1 = -UNITY_MATRIX_P._31/(UNITY_MATRIX_P._11*UNITY_MATRIX_P._34);
                float x2 = -UNITY_MATRIX_P._32/(UNITY_MATRIX_P._22*UNITY_MATRIX_P._34);
                return float4(x1, x2, 0, UNITY_MATRIX_P._33/UNITY_MATRIX_P._34 + x1*UNITY_MATRIX_P._13 + x2*UNITY_MATRIX_P._23);
            }
            
            float CorrectedLinearEyeDepth(float z, float B)
            {
                return 1.0 / (z/UNITY_MATRIX_P._34 + B);
            }
            
            Texture2D _CameraDepthTexture;
            Texture2D _GrabTexture;
            SamplerState trilinear_clamp_sampler;
            SamplerState point_clamp_sampler;
            float _VRChatMirrorMode;
            
            bool DepthExists()
            {
                uint Width = 0;
                uint Height = 0;
                _CameraDepthTexture.GetDimensions(Width, Height);
                return !(Width == 16 && Height == 16);
            }
            
            v2f vert(appdata app)
            {
                v2f input = (v2f)0;
                UNITY_SETUP_INSTANCE_ID(app);
                UNITY_TRANSFER_INSTANCE_ID(app, input);
                
                input.vertex = UnityObjectToClipPos(app.vertex);
                float3 worldPos = mul(unity_ObjectToWorld, app.vertex).xyz;
                
                float Radius = 0.49f;
                
                float scale = min(min(length(float3(unity_ObjectToWorld[0].x, unity_ObjectToWorld[1].x, unity_ObjectToWorld[2].x)),
                                      length(float3(unity_ObjectToWorld[0].y, unity_ObjectToWorld[1].y, unity_ObjectToWorld[2].y))),
                                      length(float3(unity_ObjectToWorld[0].z, unity_ObjectToWorld[1].z, unity_ObjectToWorld[2].z)));
                
                float3 ObjectPos = mul(unity_ObjectToWorld, float4(0.0, 0.0, 0.0, 1.0)).xyz;
                float WorldRadius = scale * Radius;
                
                #if defined(USING_STEREO_MATRICES)
                    float3 testCam = (unity_StereoWorldSpaceCameraPos[0] + unity_StereoWorldSpaceCameraPos[1]) * 0.5;
                #else
                    float3 testCam = _WorldSpaceCameraPos;
                #endif
                
                float margin = _ProjectionParams.y * 2.0 + 0.1;
                
                if (length(testCam - ObjectPos) < (WorldRadius + margin))
                {
                    float3 dir = normalize(worldPos - ObjectPos);
                    worldPos = _WorldSpaceCameraPos - dir * (_ProjectionParams.y * 2.0);
                    input.vertex = mul(UNITY_MATRIX_VP, float4(worldPos, 1.0));
                }
                
                float mirrorFade = 1;
                if (_VRChatMirrorMode != 0)
                {
                    float4 mirrorPlane = float4(UNITY_MATRIX_VP._m30, UNITY_MATRIX_VP._m31, UNITY_MATRIX_VP._m32, UNITY_MATRIX_VP._m33) -
                                         float4(UNITY_MATRIX_VP._m20, UNITY_MATRIX_VP._m21, UNITY_MATRIX_VP._m22, UNITY_MATRIX_VP._m23);
                    mirrorPlane /= length(mirrorPlane.xyz);
                    
                    float distToPlane = dot(mirrorPlane.xyz, ObjectPos) + mirrorPlane.w;
                    mirrorFade = saturate((distToPlane - WorldRadius) / (WorldRadius * 0.25));
                    
                    if (mirrorFade <= 0)
                        input.vertex = asfloat(-1);
                }
                
                input.screenPosition = ComputeScreenPos(input.vertex).xy;
                input.screenPosition /= input.vertex.w;
                input.frustumCorrection = dot(input.vertex, CalculateFrustumCorrection());
                input.frustumCorrection *= UNITY_MATRIX_P._34;
                input.frustumCorrection /= input.vertex.w;
                
                input.rayDir = worldPos - _WorldSpaceCameraPos;
                input.rayOrigin = (_WorldSpaceCameraPos - ObjectPos) / WorldRadius;
                input.radiusScale = 1.0f / WorldRadius;
                input.mirrorFade = mirrorFade;
                
                return input;
            }

            float4 frag(v2f input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                
                float4 _Color2 = UNITY_ACCESS_INSTANCED_PROP(Props, _Color);
                float _Opacity2 = UNITY_ACCESS_INSTANCED_PROP(Props, _Opacity);
                float _Softness2 = UNITY_ACCESS_INSTANCED_PROP(Props, _Softness);
                
                // ray-sphere intersect
                float3 RayDirection = normalize(input.rayDir);
                float3 rc = input.rayOrigin;
                
                float b = dot(RayDirection, rc);
                float c = dot(rc, rc) - 1.0;
                float h = b * b - c;
                
                float Hit = h > 0.0 ? 1 : 0;
                
                h = sqrt(max(h, 0.001));
                
                float HitNear = -b - h;
                float HitFar = -b + h;
                
                float powMask = pow(abs(HitNear - HitFar) / 2.0, _Softness2) * _Opacity2;
                
                if (HitNear > HitFar || HitFar < 0.0)
                    Hit = 0;
                
                HitNear = max(HitNear, 0.0);
                
                float2 suv = input.screenPosition.xy;
                float raw_dist = _CameraDepthTexture.SampleLevel(point_clamp_sampler, suv, 0).r;

                float3 CameraForward = mul((float3x3)unity_CameraToWorld, float3(0, 0, 1));
                float DepthFadeData = UNITY_MATRIX_P._34 / dot(CameraForward, RayDirection);
                float SceneDistance = DepthFadeData / (raw_dist + input.frustumCorrection);

                #if defined(SHADER_API_MOBILE)
                    SceneDistance = 9999999;
                #else
                    if(!DepthExists())
                        SceneDistance = 9999999;
                #endif
                
                HitFar = min(HitFar, SceneDistance * input.radiusScale);
                HitNear = min(HitNear, SceneDistance * input.radiusScale);
                float i1 = -((c * HitNear) + (b * HitNear * HitNear) + (HitNear * HitNear) * (HitNear / 3.0));
                float i2 = -((c * HitFar) + (b * HitFar * HitFar) + (HitFar * HitFar) * (HitFar / 3.0));
                float Opacity = (i2 - i1) * (3.0 / 4.0);
                
                return float4(_Color2.rgb, max(Opacity * Hit * powMask * input.mirrorFade * 0.1, 0));
            }
            ENDCG
        }
    }
}