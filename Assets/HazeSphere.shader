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
                noperspective float2 screenPosition : TEXCOORD42;
                noperspective float frustumCorrection : TEXCOORD40;
                noperspective float DepthFadeData : TEXCOORD56;

                float radiusScale   : TEXCOORD1;
                float b             : TEXCOORD2;
                float c             : TEXCOORD3;
                float powMask       : TEXCOORD4;
                float hitFar        : TEXCOORD5;
                float hitNear       : TEXCOORD6;
                float d             : TEXCOORD7;
                float hit           : TEXCOORD8;
                float obliqueFix    : TEXCOORD9;

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
                
                float4 _Color2 = UNITY_ACCESS_INSTANCED_PROP(Props, _Color);
                float _Opacity2 = UNITY_ACCESS_INSTANCED_PROP(Props, _Opacity);
                float _Softness2 = UNITY_ACCESS_INSTANCED_PROP(Props, _Softness);

                input.vertex = UnityObjectToClipPos(app.vertex);
                input.screenPosition = ComputeScreenPos(input.vertex);
                float3 worldPos = mul(unity_ObjectToWorld, app.vertex).xyz;

                float Radius = 0.49f;

                float scale = min(min(length(float3(unity_ObjectToWorld[0].x, unity_ObjectToWorld[1].x, unity_ObjectToWorld[2].x)),
                                      length(float3(unity_ObjectToWorld[0].y, unity_ObjectToWorld[1].y, unity_ObjectToWorld[2].y))),
                                      length(float3(unity_ObjectToWorld[0].z, unity_ObjectToWorld[1].z, unity_ObjectToWorld[2].z)));

                float3 CameraForward = mul((float3x3)unity_CameraToWorld, float3(0, 0, 1));
                float3 ViewDir = normalize(worldPos - _WorldSpaceCameraPos);
                float3 ObjectPos = mul(unity_ObjectToWorld, float4(0.0, 0.0, 0.0, 1.0)).xyz;
	            float3 RayOrigin = _WorldSpaceCameraPos - ObjectPos;
	            float3 RayDirection = ViewDir;

                float d = dot(CameraForward, ViewDir);

	            float3 rc = RayOrigin / (scale * Radius);

	            float b = dot(RayDirection, rc);
	            float c = dot(rc, rc) - 1.0;
	            float h = b * b - c;
	
	            h = max(h, 0.001);

	            h = sqrt(h);

	            float HitNear = -b - h;
	            float HitFar = -b + h;

	            float powMask = abs(HitNear - HitFar) / 2.0;
	
	            float Hit = 1;
	            if (HitNear > HitFar || HitFar < 0.0 || HitFar < 0.0)
		            Hit = 0;
	
	            HitNear = max(HitNear, 0.0);

                input.radiusScale = 1.0f / (scale * Radius);
                input.b = b;
                input.c = c;
                input.powMask = pow(powMask, _Softness2) * _Opacity2;
                input.hitFar = HitFar;
                input.hitNear = HitNear;
                input.d = d;
                input.hit = Hit;
			    input.obliqueFix = dot(input.vertex, CalculateFrustumCorrection());
                input.DepthFadeData = UNITY_MATRIX_P._34 / dot(CameraForward, RayDirection);

                return input;
            }

            float4 frag(v2f input, float facing : VFACE) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
            
                float4 _Color2 = UNITY_ACCESS_INSTANCED_PROP(Props, _Color);
                float _Opacity2 = UNITY_ACCESS_INSTANCED_PROP(Props, _Opacity);
                float _Softness2 = UNITY_ACCESS_INSTANCED_PROP(Props, _Softness);

                float2 suv = input.screenPosition.xy;
                float raw_dist = _CameraDepthTexture.SampleLevel(point_clamp_sampler, suv, 0).r;
                float SceneDistance = input.DepthFadeData / (raw_dist + input.frustumCorrection);

                #if defined(SHADER_API_MOBILE)
                    SceneDistance = 9999999;
                #else
                    if(!DepthExists())
                        SceneDistance = 9999999;
                #endif

                
	 	        float HitFar = min(input.hitFar, SceneDistance * input.radiusScale);
		        float HitNear = min(input.hitNear, SceneDistance * input.radiusScale);
		        float i1 = -((input.c * HitNear) + (input.b * HitNear * HitNear) + (HitNear * HitNear) * (HitNear / 3.0));
	 	        float i2 = -((input.c * HitFar) + (input.b * HitFar * HitFar) + (HitFar * HitFar) * (HitFar / 3.0));
	 	        float Opacity = (i2 - i1) * (3.0 / 4.0);

                return float4(_Color2.rgb, max(Opacity * input.hit * input.powMask * 0.1, 0));
            }
            ENDCG
        }
    }
}