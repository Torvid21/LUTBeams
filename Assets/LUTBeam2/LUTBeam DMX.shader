// I dedicate this work to the public domain. Do as you will.
// Initial implementation by Torvid
// Optimizations by ValueFactory
// Tweaks and MDMX integration by Micca

Shader "MDMX/LUTBeam"
{
    Properties
    {
        _GoboTex0 ("Gobo 0", 2D) = "white" {}
        _GoboLUT0 ("LUT 0", 2D) = "white" {}
        _GoboTex1 ("Gobo 1", 2D) = "white" {}
        _GoboLUT1 ("LUT 1", 2D) = "white" {}
        _GoboTex2 ("Gobo 2", 2D) = "white" {}
        _GoboLUT2 ("LUT 2", 2D) = "white" {}
        _GoboTex3 ("Gobo 3", 2D) = "white" {}
        _GoboLUT3 ("LUT 3", 2D) = "white" {}
        _GoboTex4 ("Gobo 4", 2D) = "white" {}
        _GoboLUT4 ("LUT 4", 2D) = "white" {}
        _GoboTex5 ("Gobo 5", 2D) = "white" {}
        _GoboLUT5 ("LUT 5", 2D) = "white" {}
        _GoboTex6 ("Gobo 6", 2D) = "white" {}
        _GoboLUT6 ("LUT 6", 2D) = "white" {}
        _GoboTex7 ("Gobo 7", 2D) = "white" {}
        _GoboLUT7 ("LUT 7", 2D) = "white" {}

        _Angle ("_Angle", Float) = 1
        _Offset ("_Offset", Float) = 0.25
        _NearRadius ("_NearRadius", Float) = 10
        _FarZ ("_FarZ", Float) = 10

        _BrightnessGoboZoomMin ("_BrightnessGoboZoomMin", Float) = 1
        _BrightnessGoboZoomMax ("_BrightnessGoboZoomMax", Float) = 1
        _BrightnessVolumeZoomMin ("_BrightnessVolumeZoomMin", Float) = 1
        _BrightnessVolumeZoomMax ("_BrightnessVolumeZoomMax", Float) = 1

        _FadeDist ("Volume Fade Distance", Float) = 1
        _FadeMult ("Volume Fade Mult", Float) = 1

        _AngleMin ("Zoom Min", Float) = 0.1
        _AngleMax ("Zoom Max", Float) = 0.3

        _PanOffset("Pan Offset", Float) = 0
        _PanMin("Pan Min", Float) = -90
        _PanMax("Pan Max", Float) = 90
        
        _TiltOffset("Tilt Offset", Float) = 0
        _TiltMin("Tilt Min", Float) = -90
        _TiltMax("Tilt Max", Float) = 90

        _SpinMult("Spin Speed", Float) = 4

        _DMXChannel("DMX Channel", Int) = -1

        _DMXMotionChannel ("Motion Channel", Int) = -1
        _MotionScale("Motion Scale", Vector) = (1,1,1)
        _MotionOffset("Motion Offset", Vector) = (1,1,1)
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" }
        LOD 100
        Blend One One
        Cull Front
        ZTest Off
        ZWrite Off

        Pass
        {
            CGPROGRAM
            #pragma multi_compile_instancing

            #pragma vertex vert
            #pragma fragment frag
            #pragma target 5.0

            #include "UnityCG.cginc"
            //#include "Assets/Micca/DMX/Shared/MDMX.cginc"

            struct appdata
            {
                float4 vertex : POSITION;

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float2 screenPosition : TEXCOORD2;
                float3 worldPos : TEXCOORD3;
                nointerpolation float3 A : TEXCOORD4;
                nointerpolation float3 a : TEXCOORD5;
                nointerpolation float3 r : TEXCOORD6;
                nointerpolation float3 u : TEXCOORD7;

                nointerpolation float3 color : COLOR0;
                nointerpolation uint gobo : TEXCOORD8;
                nointerpolation float angle : TEXCOORD9;

                nointerpolation float4 nearPlane     : TEXCOORD10;
                nointerpolation float4 farPlane      : TEXCOORD11;
                nointerpolation float4 leftPlane     : TEXCOORD12;
                nointerpolation float4 rightPlane    : TEXCOORD13;
                nointerpolation float4 bottomPlane   : TEXCOORD14;
                nointerpolation float4 topPlane      : TEXCOORD15;
                
                // nointerpolation float exitDistance      : TEXCOORD16;

                nointerpolation float brightnessGobo      : TEXCOORD17;
                nointerpolation float brightnessVolume      : TEXCOORD18;

                float frustumCorrection : TEXCOORD19;

                UNITY_VERTEX_OUTPUT_STEREO
                UNITY_VERTEX_INPUT_INSTANCE_ID 
            };

            UNITY_DECLARE_DEPTH_TEXTURE(_CameraDepthTexture);

            sampler2D _GoboTex0;
            Texture2D _GoboLUT0;
            sampler2D _GoboTex1;
            Texture2D _GoboLUT1;
            sampler2D _GoboTex2;
            Texture2D _GoboLUT2;
            sampler2D _GoboTex3;
            Texture2D _GoboLUT3;
            sampler2D _GoboTex4;
            Texture2D _GoboLUT4;
            sampler2D _GoboTex5;
            Texture2D _GoboLUT5;
            sampler2D _GoboTex6;
            Texture2D _GoboLUT6;
            sampler2D _GoboTex7;
            Texture2D _GoboLUT7;

            SamplerState _SamplerClampLinear;
            
            float inverselerp(float a, float b, float value)
            {
                return (value - a) / (b - a);
            }
            
            float _NearRadius;
            float _Offset;
            float _FarZ;

            float frustumNearZ;
            float frustumFarZ;
            float frustumOffset;
            
            float _BrightnessGoboZoomMin;
            float _BrightnessGoboZoomMax;
            float _BrightnessVolumeZoomMin;
            float _BrightnessVolumeZoomMax;

            float _Angle;
            float _TiltOffset;
            float _TiltMin;
            float _TiltMax;
            float _PanOffset;
            float _PanMin;
            float _PanMax;
            float _LightEmission;
            int _DMXMotionChannel;
            float4 _MotionScale;
            float4 _MotionOffset;

            float _AngleMin, _AngleMax, _SpinMult;

            float _FadeDist, _FadeMult;

            // matrix notes: https://learnopengl.com/Getting-started/Transformations
            // micca's funny rot stuff
            float4 rotateVertex(float4 vertex, float inX, float inY, float inZ) {
                float sinX, cosX, sinY, cosY, sinZ, cosZ;
                sincos(inX,sinX,cosX);
                sincos(inY,sinY,cosY);
                sincos(inZ,sinZ,cosZ);
                float4x4 matX = float4x4( //spin
                    1, 0, 0, 0,
                    0, cosX, -sinX, 0,
                    0, sinX, cosX, 0,
                    0, 0, 0, 1
                );
                float4x4 matY = float4x4( //tilt
                    cosY, 0, sinY, 0,
                    0, 1, 0, 0,
                    -sinY, 0, cosY, 0,
                    0, 0, 0, 1
                );
                float4x4 matZ = float4x4( //pan
                    cosZ, -sinZ, 0, 0,
                    sinZ, cosZ, 0, 0,
                    0, 0, 1, 0,
                    0, 0, 0, 1
                );
                float4x4 matF = mul(mul(matY,matZ),matX);
                return mul(matF,vertex);
            }

            //float degreesToRadians(float degrees)
            //{
            //    return degrees * (3.141592 / 180.0f);
            //}

            float3 GetScale()
            {
                float3 scale = 0;
                scale.x = length(float3(unity_ObjectToWorld._m00, unity_ObjectToWorld._m10, unity_ObjectToWorld._m20));
                scale.y = length(float3(unity_ObjectToWorld._m01, unity_ObjectToWorld._m11, unity_ObjectToWorld._m21));
                scale.z = length(float3(unity_ObjectToWorld._m02, unity_ObjectToWorld._m12, unity_ObjectToWorld._m22));
                return scale;
            }

            float4x4 ObjectToWorld_NoScale()
            {
                float3 right   = normalize(float3(unity_ObjectToWorld._m00, unity_ObjectToWorld._m10, unity_ObjectToWorld._m20));
                float3 up      = normalize(float3(unity_ObjectToWorld._m01, unity_ObjectToWorld._m11, unity_ObjectToWorld._m21));
                float3 forward = normalize(float3(unity_ObjectToWorld._m02, unity_ObjectToWorld._m12, unity_ObjectToWorld._m22));
                float3 t       = float3(unity_ObjectToWorld._m03, unity_ObjectToWorld._m13, unity_ObjectToWorld._m23);

                float4x4 m = unity_ObjectToWorld;
                m._m00_m10_m20_m30 = float4(right,   0.0);
                m._m01_m11_m21_m31 = float4(up,      0.0);
                m._m02_m12_m22_m32 = float4(forward, 0.0);

                m._m03 = t.x; m._m13 = t.y; m._m23 = t.z;
                m._m30 = 0.0; m._m31 = 0.0; m._m32 = 0.0; m._m33 = 1.0;

                return m;
            }

            // called in both pixel and vertex shader to set global variables for the frustum shape
            void SetVariables(float angle)
            {
                frustumNearZ = (_NearRadius / angle);
                frustumFarZ = (_NearRadius / angle) + _FarZ;
                frustumOffset = -(_NearRadius / angle) - _Offset;
            }

            // NOTE(valuef): Mirrors use oblique clipping planes so we need to
            // do some extra math to properly convert the depth we sample out
            // of their depth textures.  
            //
            // The code that does that here is based off:
            // https://github.com/lukis101/VRCUnityStuffs/blob/master/Shaders/DJL/Overlays/WorldPosOblique.shader
            // Retrieved 2025-09-23
            inline float4 CalculateFrustumCorrection()
            {
                float x1 = -UNITY_MATRIX_P._31 / (UNITY_MATRIX_P._11 * UNITY_MATRIX_P._34);
                float x2 = -UNITY_MATRIX_P._32 / (UNITY_MATRIX_P._22 * UNITY_MATRIX_P._34);
                return float4(x1, x2, 0, UNITY_MATRIX_P._33 / UNITY_MATRIX_P._34 + x1 * UNITY_MATRIX_P._13 + x2 * UNITY_MATRIX_P._23);
            }

            inline float CorrectedLinearEyeDepth(float z, float frustumCorrection)
            {
                return 1.0 / (z / UNITY_MATRIX_P._34 + frustumCorrection);
            }

            v2f vert (appdata v)
            {
                v2f input;

                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_OUTPUT(v2f, input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(input);
                UNITY_TRANSFER_INSTANCE_ID(v, input);

                //funny dmx
                uint channel = 0;//GetDMXChannel();

#if 0
                float pan = ReadDMX(channel);
                float tilt = ReadDMX(channel+2);
                float zoom = ReadDMX(channel+4);
                float dimmer = ReadDMX(channel+5);
                float strobe = ReadStrobe(channel+6);
                float3 color = ReadColor(channel+7);
                float goboSpin = ReadSpin(channel+10) * _SpinMult;
                input.gobo = ReadDMX(channel+11) * 8;
#else
                float pan = 0;
                float tilt = 0;
                float zoom = 1;
                float dimmer = 1;
                float strobe = 1;
                float3 color = 1;
                float goboSpin = 0;
                input.gobo = 1;
#endif

                //cap range
                input.gobo = clamp(input.gobo,0,7);

                tilt = radians(lerp(_TiltMin, _TiltMax, tilt) + _TiltOffset);
                pan = -radians(lerp(_PanMin, _PanMax, pan) + _PanOffset);

                float zoomStep = smoothstep(-1,1,zoom);
                input.brightnessGobo = lerp(_BrightnessGoboZoomMin, _BrightnessGoboZoomMax, zoomStep);
                input.brightnessVolume = lerp(_BrightnessVolumeZoomMin, _BrightnessVolumeZoomMax, zoomStep);

                float2x2 spinMatrix = {
                    cos(goboSpin), -sin(goboSpin),
                    sin(goboSpin),  cos(goboSpin)
                };
                float2x2 tiltMatrix = {
                    cos(tilt), -sin(tilt),
                    sin(tilt),  cos(tilt)
                };
                float2x2 panMatrix = {
                    cos(pan), -sin(pan),
                    sin(pan),  cos(pan)
                };

                input.color = color * dimmer * strobe;

                // NOTE(valuef): Vertex discard if color is close enough to black
                // 2025-09-23
                if(input.color.r + input.color.g + input.color.b <= .0003) {
                //if(!all(input.color)) {
                  return (v2f)asfloat(-1);
                }

                input.angle = lerp(_AngleMin, _AngleMax, zoom);
                SetVariables(input.angle);

                float t = v.vertex.z+0.5;
                v.vertex.z = lerp(frustumNearZ, frustumFarZ, t);
                v.vertex.xy *= v.vertex.z * input.angle * 2;
                v.vertex.z += frustumOffset;
                
                float3 pos = 0;
                if (_DMXMotionChannel >= 0)
                {
                    //pos = (float3(ReadDMX(_DMXMotionChannel+4), -ReadDMX(_DMXMotionChannel+2), ReadDMX(_DMXMotionChannel)) - _MotionOffset) * _MotionScale.xyz;
                    v.vertex.xyz += pos;
                }

                v.vertex.xy = mul(v.vertex.xy, spinMatrix);
                v.vertex.yz = mul(v.vertex.yz, tiltMatrix);
                v.vertex.xy = mul(v.vertex.xy, panMatrix);
                
                input.a = float3(0, 0, -1);
                input.a.xy = mul(input.a.xy, spinMatrix);
                input.a.yz = mul(input.a.yz, tiltMatrix);
                input.a.xy = mul(input.a.xy, panMatrix);
                input.r = float3(1, 0, 0);
                input.r.xy = mul(input.r.xy, spinMatrix);
                input.r.yz = mul(input.r.yz, tiltMatrix);
                input.r.xy = mul(input.r.xy, panMatrix);
                input.u = float3(0, 1, 0);
                input.u.xy = mul(input.u.xy, spinMatrix);
                input.u.yz = mul(input.u.yz, tiltMatrix);
                input.u.xy = mul(input.u.xy, panMatrix);
                
                input.a = normalize(mul(unity_ObjectToWorld, float4(input.a, 0)).xyz);
                input.r = normalize(mul(unity_ObjectToWorld, float4(input.r, 0)).xyz);
                input.u = normalize(mul(unity_ObjectToWorld, float4(input.u, 0)).xyz);

                float3 forward = float3(0,0,1);
                float3 up = float3(0,0,1);
                
                input.vertex = mul(UNITY_MATRIX_VP, mul(ObjectToWorld_NoScale(), v.vertex));

                input.screenPosition = ComputeScreenPos(input.vertex).xy;
                input.worldPos = mul(ObjectToWorld_NoScale(), v.vertex);

                float3 A = mul(unity_ObjectToWorld, float4(0, 0, 0, 1)).xyz;
                A -= input.a * frustumOffset;
                
                A -= input.a * pos.z;
                A += input.r * pos.x;
                A += input.u * pos.y;

                float3 a = input.a;
                float3 r = input.r;
                float3 u = input.u;

                float k = input.angle;
                float nearWidth  = 2.0 * k * frustumNearZ;
                float nearHeight = 2.0 * k * frustumNearZ;
                float farWidth   = 2.0 * k * frustumFarZ;
                float farHeight  = 2.0 * k * frustumFarZ;

                input.nearPlane   = float4(a                   , -dot(a                   , -A + a*frustumNearZ));
                input.farPlane    = float4(-a                  , -dot(-a                  , -A + a*frustumFarZ));
                input.leftPlane   = float4(normalize(k * a + r), -dot(normalize(k * a + r), -A));
                input.rightPlane  = float4(normalize(k * a - r), -dot(normalize(k * a - r), -A));
                input.bottomPlane = float4(normalize(k * a - u), -dot(normalize(k * a - u), -A));
                input.topPlane    = float4(normalize(k * a + u), -dot(normalize(k * a + u), -A));
                
                input.A = A;

                input.frustumCorrection = dot(input.vertex, CalculateFrustumCorrection());
                
                // float3 CameraForward = mul((float3x3)unity_CameraToWorld, float3(0, 0, 1));
                // float3 CameraToWorld = normalize(input.worldPos - _WorldSpaceCameraPos);

                //float d = dot(CameraForward, CameraToWorld);
                //input.exitDistance = distance(input.worldPos, _WorldSpaceCameraPos) * d;


                return input;
            }

            float3 MagicSample(Texture2D goboLUT, float2 start, float2 end, int gobo)
            {
#if 0
                // old method, slower
                int size = 32;
                int2 chunk = floor(start*(size-1))*size;
                float2 chunkblend = frac(start*(size-1));
                chunkblend = smoothstep(0,1,chunkblend);
                float2 chunkblendInv = 1-chunkblend;
                int2 pixel = floor(end*(size-1));
                float2 pixelblend = frac(end*(size-1));
                pixelblend = smoothstep(0,1,pixelblend);
                float2 pixelblendInv = 1-pixelblend;
                
                float3 sample0 = goboLUT.Load(int4(chunk+pixel+float2(0, 0), 0, 0)).rgb;
                float3 sample1 = goboLUT.Load(int4(chunk+pixel+float2(1, 0), 0, 0)).rgb;
                float3 sample2 = goboLUT.Load(int4(chunk+pixel+float2(0, 1), 0, 0)).rgb;
                float3 sample3 = goboLUT.Load(int4(chunk+pixel+float2(1, 1), 0, 0)).rgb;
                float3 sample4 = goboLUT.Load(int4(chunk+int2(size, 0)+pixel+int2(0, 0), 0, 0)).rgb;
                float3 sample5 = goboLUT.Load(int4(chunk+int2(size, 0)+pixel+int2(1, 0), 0, 0)).rgb;
                float3 sample6 = goboLUT.Load(int4(chunk+int2(size, 0)+pixel+int2(0, 1), 0, 0)).rgb;
                float3 sample7 = goboLUT.Load(int4(chunk+int2(size, 0)+pixel+int2(1, 1), 0, 0)).rgb;
                float3 sample8  = goboLUT.Load(int4(chunk+int2(0, size)+pixel+int2(0, 0), 0, 0)).rgb;
                float3 sample9  = goboLUT.Load(int4(chunk+int2(0, size)+pixel+int2(1, 0), 0, 0)).rgb;
                float3 sample10 = goboLUT.Load(int4(chunk+int2(0, size)+pixel+int2(0, 1), 0, 0)).rgb;
                float3 sample11 = goboLUT.Load(int4(chunk+int2(0, size)+pixel+int2(1, 1), 0, 0)).rgb;
                float3 sample12 = goboLUT.Load(int4(chunk+int2(size, size)+pixel+int2(0, 0), 0, 0)).rgb;
                float3 sample13 = goboLUT.Load(int4(chunk+int2(size, size)+pixel+int2(1, 0), 0, 0)).rgb;
                float3 sample14 = goboLUT.Load(int4(chunk+int2(size, size)+pixel+int2(0, 1), 0, 0)).rgb;
                float3 sample15 = goboLUT.Load(int4(chunk+int2(size, size)+pixel+int2(1, 1), 0, 0)).rgb;
                
                float3 sample4D0 = (sample0 * pixelblendInv.x +  sample1  * pixelblend.x) * pixelblendInv.y +  (sample2  * pixelblendInv.x + sample3  * pixelblend.x) * pixelblend.y;
                float3 sample4D1 = (sample4 * pixelblendInv.x +  sample5  * pixelblend.x) * pixelblendInv.y +  (sample6  * pixelblendInv.x + sample7  * pixelblend.x) * pixelblend.y;
                float3 sample4D2 = (sample8 * pixelblendInv.x +  sample9  * pixelblend.x) * pixelblendInv.y +  (sample10 * pixelblendInv.x + sample11 * pixelblend.x) * pixelblend.y;
                float3 sample4D3 = (sample12* pixelblendInv.x +  sample13 * pixelblend.x) * pixelblendInv.y +  (sample14 * pixelblendInv.x + sample15 * pixelblend.x) * pixelblend.y;
                float3 sample4D  = (sample4D0 * chunkblendInv.x + sample4D1 * chunkblend.x) * chunkblendInv.y + (sample4D2 * chunkblendInv.x + sample4D3 * chunkblend.x) * chunkblend.y;

                // gobo 7 is RGB
                if(gobo != 7)
                    sample4D.rgb = sample4D.r;

                return sample4D;
#else
                const int chunk_size = 32;
                const float tex_size = chunk_size * chunk_size;

                int2 chunk = floor(start*(chunk_size-1))*chunk_size;
                float2 chunkblend = frac(start*(chunk_size-1));
                chunkblend = smoothstep(0,1,chunkblend);
                float2 chunkblendInv = 1-chunkblend;

                int2 pixel = floor(end*(chunk_size-1));
                float2 pixelblend = frac(end*(chunk_size-1));
                pixelblend = smoothstep(0,1,pixelblend);
                
                // NOTE(valuef): +0.5 to move the sample from the center of the pixel to a corner so that pixelblend becomes the bilinear blend coefficient.
                float4 sample4D0 = goboLUT.SampleLevel(_SamplerClampLinear, float2(chunk + float2(0,          0)          + pixel + pixelblend + .5) / tex_size, 0);
                float4 sample4D1 = goboLUT.SampleLevel(_SamplerClampLinear, float2(chunk + float2(chunk_size, 0)          + pixel + pixelblend + .5) / tex_size, 0);
                float4 sample4D2 = goboLUT.SampleLevel(_SamplerClampLinear, float2(chunk + float2(0,          chunk_size) + pixel + pixelblend + .5) / tex_size, 0);
                float4 sample4D3 = goboLUT.SampleLevel(_SamplerClampLinear, float2(chunk + float2(chunk_size, chunk_size) + pixel + pixelblend + .5) / tex_size, 0);
                
                float3 sample4D  = (sample4D0 * chunkblendInv.x + sample4D1 * chunkblend.x) * chunkblendInv.y + (sample4D2 * chunkblendInv.x + sample4D3 * chunkblend.x) * chunkblend.y;

                // gobo 7 is RGB
                if(gobo != 7)
                    sample4D.rgb = sample4D.r;

                return sample4D;

#endif

            }

            float2 RayFrustumIntersect(float3 rayOrigin, float3 rayDir, 
                                      float4 leftPlane, float4 rightPlane, 
                                      float4 bottomPlane, float4 topPlane, 
                                      float4 nearPlane, float4 farPlane)
            {
                float tMin = -1e30;
                float tMax = 1e30;
    
                // Test each plane
                float denom, t;
    
                // Left plane
                denom = dot(leftPlane.xyz, rayDir);
                if (abs(denom) > 1e-6) {
                    t = (leftPlane.w - dot(leftPlane.xyz, rayOrigin)) / denom;
                    if (denom < 0) tMin = max(tMin, t);
                    else tMax = min(tMax, t);
                }
    
                // Right plane
                denom = dot(rightPlane.xyz, rayDir);
                if (abs(denom) > 1e-6) {
                    t = (rightPlane.w - dot(rightPlane.xyz, rayOrigin)) / denom;
                    if (denom < 0) tMin = max(tMin, t);
                    else tMax = min(tMax, t);
                }
    
                // Bottom plane
                denom = dot(bottomPlane.xyz, rayDir);
                if (abs(denom) > 1e-6) {
                    t = (bottomPlane.w - dot(bottomPlane.xyz, rayOrigin)) / denom;
                    if (denom < 0) tMin = max(tMin, t);
                    else tMax = min(tMax, t);
                }
    
                // Top plane
                denom = dot(topPlane.xyz, rayDir);
                if (abs(denom) > 1e-6) {
                    t = (topPlane.w - dot(topPlane.xyz, rayOrigin)) / denom;
                    if (denom < 0) tMin = max(tMin, t);
                    else tMax = min(tMax, t);
                }
    
                // Near plane
                denom = dot(nearPlane.xyz, rayDir);
                if (abs(denom) > 1e-6) {
                    t = (nearPlane.w - dot(nearPlane.xyz, rayOrigin)) / denom;
                    if (denom < 0) tMin = max(tMin, t);
                    else tMax = min(tMax, t);
                }
    
                // Far plane
                denom = dot(farPlane.xyz, rayDir);
                if (abs(denom) > 1e-6) {
                    t = (farPlane.w - dot(farPlane.xyz, rayOrigin)) / denom;
                    if (denom < 0) tMin = max(tMin, t);
                    else tMax = min(tMax, t);
                }

                return (tMin <= tMax && tMax >= 0) ? float2(max(0, tMin), tMax) : float2(-1, -1);
            }

            float4 frag (v2f input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                SetVariables(input.angle);
                float3 CameraForward = mul((float3x3)unity_CameraToWorld, float3(0, 0, 1));

                float3 view_delta = input.worldPos - _WorldSpaceCameraPos;
                float sq_view_dist = dot(view_delta, view_delta);
                float view_dist = sqrt(sq_view_dist);

                float3 CameraToWorld = view_delta / view_dist;

                float d = dot(CameraForward, CameraToWorld);
                float raw_dist = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, input.screenPosition.xy / input.vertex.w);
                float SceneDistance = CorrectedLinearEyeDepth(raw_dist, input.frustumCorrection / input.vertex.w);
                SceneDistance /= d;
                
                float3 A = input.A;
                float3 a = input.a;
                float3 r = input.r;
                float3 u = input.u;

                float3 rayOrigin = _WorldSpaceCameraPos;
                float3 rayDir = CameraToWorld;

#if 0
                float2 intersection = RayFrustumIntersect(
                    rayOrigin, rayDir,
                    input.leftPlane, input.rightPlane,
                    input.bottomPlane, input.topPlane,
                    input.nearPlane, input.farPlane
                );

                float entryDistance = intersection.x;
                float exitDistance = intersection.y;
#else

                float entryDistance;
                {
                  float4 planes[6] = { input.leftPlane, input.rightPlane, input.bottomPlane, input.topPlane, input.nearPlane, input.farPlane };

                  float tMin = -1e30;
                  for(int i = 0; i < 6; i++) {
                    float denom = dot(planes[i].xyz, rayDir);
                    if (denom < 0) tMin = max(tMin, (planes[i].w - dot(planes[i].xyz, rayOrigin)) / denom);
                  }
      
                  entryDistance = max(0, tMin);
                }
                float exitDistance = view_dist;
#endif
                
                {
                    bool hit = false;
                    if(entryDistance < SceneDistance && exitDistance > SceneDistance)
                    {
                        hit = true;
                    }
                    
                    // NOTE(valuef): Regarding the if: Only clamp when the pixel depth isn't approaching the far plane.
                    // This should only be false in mirrors due to the oblique frustum correction when the pixel we're drawing
                    // hasn't had any depth written to it.
                    // 2025-09-23
                    if(SceneDistance >= 0) {
                      entryDistance = min(entryDistance, SceneDistance);
                      exitDistance = min(exitDistance, SceneDistance);
                    }

                    {
                      // NOTE(valuef): Save on a sqrt by just comparing the squared equlidean length instead.
                      //  distance(a, b) < dist
                      //  sqrt(dot(a - b, a - b)) < dist
                      //  dot(a - b, a - b) < (dist*dist)

                      float dist = .01;
                      float2 delta = entryDistance - exitDistance;
                      if(dot(delta, delta) < (dist*dist)) {
                        discard;
                      }
                    }

                    float3 entryPos = rayOrigin + rayDir * entryDistance;
                    float3 exitPos = rayOrigin + rayDir * exitDistance;
                    entryPos = A-entryPos;
                    exitPos = A-exitPos;
                    entryPos = float3(dot(a, entryPos), dot(r, entryPos), dot(u, entryPos));
                    exitPos = float3(dot(a, exitPos), dot(r, exitPos), dot(u, exitPos));

                    float3 entryNormalized = entryPos.yzx;
                    float3 exitNormalized = exitPos.yzx;
                    
                    entryNormalized.xy /= entryNormalized.z * input.angle * 2;
                    entryNormalized.xy = entryNormalized.xy+0.5;
                    entryNormalized.z = inverselerp(frustumNearZ, frustumFarZ, entryNormalized.z);
                    
                    exitNormalized.xy /= exitNormalized.z * input.angle * 2;
                    exitNormalized.xy = exitNormalized.xy+0.5;
                    exitNormalized.z = inverselerp(frustumNearZ, frustumFarZ, exitNormalized.z);

                    // Hacky way to get a 0-1 gradient from nearZ to farZ for fading the beam
                    float alignemnt = dot(a, CameraForward)*0.5+0.5;
                    float t = lerp(entryNormalized.z, exitNormalized.z, alignemnt);

                    t += 0.1; // adding 0.1 here mitigates the box issue at the light source
                    t = saturate(t);

                    float3 col;
                    //help
                    // fluffy
                    [forcecase]
                    switch (input.gobo) {
                        case 0: col = MagicSample(_GoboLUT0, entryNormalized.xy, exitNormalized.xy, input.gobo); break;
                        case 1: col = MagicSample(_GoboLUT1, entryNormalized.xy, exitNormalized.xy, input.gobo); break;
                        case 2: col = MagicSample(_GoboLUT2, entryNormalized.xy, exitNormalized.xy, input.gobo); break;
                        case 3: col = MagicSample(_GoboLUT3, entryNormalized.xy, exitNormalized.xy, input.gobo); break;
                        case 4: col = MagicSample(_GoboLUT4, entryNormalized.xy, exitNormalized.xy, input.gobo); break;
                        case 5: col = MagicSample(_GoboLUT5, entryNormalized.xy, exitNormalized.xy, input.gobo); break;
                        case 6: col = MagicSample(_GoboLUT6, entryNormalized.xy, exitNormalized.xy, input.gobo); break;
                        case 7: col = MagicSample(_GoboLUT7, entryNormalized.xy, exitNormalized.xy, input.gobo); break;
                        default: col = 0; break;
                    }

                    //For fading out volumetric near depth plane
                    //float fadeDist = saturate(exitDistance - SceneDistance + _FadeDist);

                    //if(!all(col)) discard;
                    
                    // exponential decay
                    //col = saturate(col - (fadeDist * _FadeMult));
                    col *= (1-t)*(50/((t*1000)+1));
                    col *= input.color * input.brightnessVolume;
                    col *= 10;

                    if(hit)
                    {
                        float3 gobo;
                        //help
                        [forcecase]
                        switch (input.gobo) {
                            case 0: gobo = tex2D(_GoboTex0, float2(exitNormalized.xy)).r; break;
                            case 1: gobo = tex2D(_GoboTex1, float2(exitNormalized.xy)).r; break;
                            case 2: gobo = tex2D(_GoboTex2, float2(exitNormalized.xy)).r; break;
                            case 3: gobo = tex2D(_GoboTex3, float2(exitNormalized.xy)).r; break;
                            case 4: gobo = tex2D(_GoboTex4, float2(exitNormalized.xy)).r; break;
                            case 5: gobo = tex2D(_GoboTex5, float2(exitNormalized.xy)).r; break;
                            case 6: gobo = tex2D(_GoboTex6, float2(exitNormalized.xy)).r; break;
                            case 7: gobo = tex2D(_GoboTex7, float2(exitNormalized.xy)); break;
                            default: gobo = 0; break;
                        }
                        float3 scenePos = _WorldSpaceCameraPos + CameraToWorld * SceneDistance;
                        
                        float t2 = distance(A, scenePos) / frustumFarZ;
                        // exponential decay
                        gobo *= (1-t2)*(200/((t2*1000)+1));
                        gobo *= input.brightnessGobo;
                        col += gobo * input.color * .25;
                    }

                    return float4(col,1);
                }
            }
            ENDCG
        }
    }
}
