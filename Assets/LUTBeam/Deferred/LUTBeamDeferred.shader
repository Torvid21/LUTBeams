Shader "LUTBeam/Deferred"
{
    Properties
    {
        [NoScaleOffset] _GoboTex ("Gobo Texture", 2DArray) = "white" {}
        [NoScaleOffset] _GoboLUT ("LUT Texture", 2DArray) = "white" {}
        [NoScaleOffset] _DataTexture ("Data Texture", 2D) = "black" {}

        // WorldPosXYZ, BeamIntensity
        // ForwardXYZ, BeamFalloff
        // UpXYZ, GoboIntensity
        // ZoomXY, _NearSizeXY
        // ColorRGB, FarZ
        // Gobo, _Focus, _Focus_ApertureSize, _Frost
        // _Framing0A _Framing0B _Framing1A _Framing1B
        // _Framing2A _Framing2B _Framing3A _Framing3B

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

        
        [Header(Framing Shutters)]
        [Toggle(LUTBEAM_FRAMING)] _FramingEnabled ("Enable", Float) = 0
        
        _Framing0A ("_Framing0A", Range(0, 1.0)) = 0
        _Framing0B ("_Framing0B", Range(0, 1.0)) = 0
        _Framing1A ("_Framing1A", Range(0, 1.0)) = 0
        _Framing1B ("_Framing1B", Range(0, 1.0)) = 0
        _Framing2A ("_Framing2A", Range(0, 1.0)) = 0
        _Framing2B ("_Framing2B", Range(0, 1.0)) = 0
        _Framing3A ("_Framing3A", Range(0, 1.0)) = 0
        _Framing3B ("_Framing3B", Range(0, 1.0)) = 0
            
        _Test ("_Test", Range(0, 1.0)) = 0
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

        Cull Off
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

            Texture2D _DataTexture;
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
            float _Test;
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

            // I dedicate this work to the public domain. Do as you will.
            // Initial implementation by Torvid
            // Optimizations by ValueFactory
            // Tweaks and MDMX integration by Micca
            // position resolution, IE how many possible places the camera can be.
            #define start_size 8
            // angular resolution, IE how many angles can the beam be viewed from.
            #define end_size 128

            struct dummy_struct {};

            #define CUSTOM_STRUCT_EXISTS
            #ifndef NESTED_STRUCT_TYPE
                #define NESTED_STRUCT_TYPE dummy_struct
                #undef CUSTOM_STRUCT_EXISTS
            #endif
            #pragma multi_compile _ LUTBEAM_FRAMING
            #pragma multi_compile _ LUTBEAM_FOCUS
            struct BeamSettings
            {
                float3 worldPos;
                float3 up;
                float3 forward;
                float3 right;
                float zoomX;
                float zoomY;
                float farz;
                float nearSizeX;
                float nearSizeY;
                float offset;
                float gobo;
                float3 color;
                float brightnessVolume;
                float brightnessGobo;
                float beamFalloff;
                float focus;
                float focus_apertureSize;
                float frost;
                float framing0A;
                float framing0B;
                float framing1A;
                float framing1B;
                float framing2A;
                float framing2B;
                float framing3A;
                float framing3B;
                float framingAngle;
            };

            struct BeamData
            {
                // Start texcoords at 40 so they are unlikely to be used by something else.
                float4 vertex : SV_POSITION;
                noperspective float frustumCorrection : TEXCOORD40;
                float3 rayDir : TEXCOORD41;

                noperspective float2 screenPosition : TEXCOORD42;

                nointerpolation float zoomX : TEXCOORD43;
                nointerpolation float zoomY : TEXCOORD44;
                nointerpolation float frustumNearZ : TEXCOORD45;
                nointerpolation float frustumFarZ : TEXCOORD46;
                nointerpolation float invBeamLength : TEXCOORD47;
    
                nointerpolation float3 rayOrigin  : TEXCOORD49;
                nointerpolation float3 colorGobo : TEXCOORD50;
                nointerpolation float3 colorVolume : TEXCOORD51;
                nointerpolation float4 clipPlane : TEXCOORD52;
                nointerpolation float4 aniso : TEXCOORD53;
                nointerpolation float falloff : TEXCOORD54;
                NESTED_STRUCT_TYPE nestedStruct : TEXCOORD55;
                
                noperspective float DepthFadeData : TEXCOORD56;
                nointerpolation float3 counter : TEXCOORD20;

            #if LUTBEAM_FOCUS
                nointerpolation float focus : TEXCOORD57;
                nointerpolation float focus_apertureSize : TEXCOORD64;
                nointerpolation float frost : TEXCOORD58;
            #endif

            #if LUTBEAM_FRAMING
                nointerpolation float4 bladePn : TEXCOORD59;
                float4 bladeDn : TEXCOORD60;
                nointerpolation bool framing : TEXCOORD63;
            #endif

            };

            float inverselerp(float from, float to, float value)
            {
                return (value - from) / (to - from);
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

            // NOTE(valuef): Mirrors use oblique clipping planes so we need to
            // do some extra math to properly convert the depth we sample out
            // of their depth textures.  
            // The code that does that here is based off:
            // https://github.com/lukis101/VRCUnityStuffs/blob/master/Shaders/DJL/Overlays/WorldPosOblique.shader
            // Retrieved 2025-09-23
            float4 CalculateFrustumCorrection()
            {
                float x1 = -UNITY_MATRIX_P._31 / (UNITY_MATRIX_P._11 * UNITY_MATRIX_P._34);
                float x2 = -UNITY_MATRIX_P._32 / (UNITY_MATRIX_P._22 * UNITY_MATRIX_P._34);
                return float4(x1, x2, 0, UNITY_MATRIX_P._33 / UNITY_MATRIX_P._34 + x1 * UNITY_MATRIX_P._13 + x2 * UNITY_MATRIX_P._23);
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

            float3 WorldToFrustumVector(float3 apex, float3 forward, float3 right, float3 up, float3 a)
            {
                float3 result = 0;
                result.x = dot(a, right);
                result.y = dot(a, up);
                result.z = dot(a, forward);
                return result;
            }

            float3 WorldToFrustumPosition(float3 apex, float3 forward, float3 right, float3 up, float3 a)
            {
                float3 result = 0;
                result.x = dot(a-apex, right);
                result.y = dot(a-apex, up);
                result.z = dot(a-apex, forward);
                return result;
            }

            float3 FrustumToWorldVector(float3 apex, float3 forward, float3 right, float3 up, float3 a)
            {
                return (right * a.x) + (up * a.y) + (forward * a.z);
            }

            float3 FrustumToWorldPosition(float3 apex, float3 forward, float3 right, float3 up, float3 a)
            {
                return apex + (right * a.x) + (up * a.y) + (forward * a.z);
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

            BeamSettings DefaultBeamSettings()
            {
                BeamSettings settings = (BeamSettings)0;
                settings.zoomX = 0.25;
                settings.zoomY = 0.25;
                settings.farz = 50;
                settings.nearSizeX = 0.1;
                settings.nearSizeY = 0.1;
                settings.offset = 0;
                settings.color = 1;
                settings.brightnessVolume = 4;
                settings.brightnessGobo = 4;
                settings.beamFalloff = 2;
                settings.focus = 0;
                settings.focus_apertureSize = 1;
                settings.frost = 0;
                settings.framing0A = 0;
                settings.framing0B = 0;
                settings.framing1A = 0;
                settings.framing1B = 0;
                settings.framing2A = 0;
                settings.framing2B = 0;
                settings.framing3A = 0;
                settings.framing3B = 0;
                settings.framingAngle = 0;
                return settings;
            }
            #define pi 3.1415926535897

            float CalculateMip(float t, float focus, float frost, float aperture)
            {
                float A = 1;
                t = sqrt(t);

                float blur = abs(t-focus);
    
                blur = 1-blur;
                blur = blur*blur*blur*blur;
                blur = 1-blur;

                return saturate(blur * aperture + frost);
            }

            float3 MagicSample(float2 start, float2 end, float blur, NESTED_STRUCT_TYPE nestedStruct)
            {
                float tex_size = start_size * end_size;
    
                float2 posF          = saturate(start) * (start_size - 1.001);
                float2 cell          = floor(posF);
                float2 chunkblend    = posF - cell;
                float2 chunkblendInv = 1 - chunkblend;
                float2 chunk         = cell * end_size;
        
                float mip = 0;
                float2 base = 0;
                #if LUTBEAM_FOCUS
                    mip = blur * 2.5;
                    float margin = clamp(exp2(mip), 0.5, end_size * 0.5);
                    float2 inTile = margin + saturate(end) * (end_size - 2 * margin);
                    base = chunk + inTile;
                #else
                    base = chunk + saturate(end) * (end_size - 1) + 0.5;
                #endif
    
                #ifdef LUTBEAM_CALLBACK_VOLUME
                    #ifdef CUSTOM_STRUCT_EXISTS
                        float3 s0 = LUTBEAM_CALLBACK_VOLUME(trilinear_clamp_sampler, (base + float2(0,        0))        / tex_size, mip, nestedStruct);
                        float3 s1 = LUTBEAM_CALLBACK_VOLUME(trilinear_clamp_sampler, (base + float2(end_size, 0))        / tex_size, mip, nestedStruct);
                        float3 s2 = LUTBEAM_CALLBACK_VOLUME(trilinear_clamp_sampler, (base + float2(0,        end_size)) / tex_size, mip, nestedStruct);
                        float3 s3 = LUTBEAM_CALLBACK_VOLUME(trilinear_clamp_sampler, (base + float2(end_size, end_size)) / tex_size, mip, nestedStruct);
                    #else
                        float3 s0 = LUTBEAM_CALLBACK_VOLUME(trilinear_clamp_sampler, (base + float2(0,        0))        / tex_size, mip);
                        float3 s1 = LUTBEAM_CALLBACK_VOLUME(trilinear_clamp_sampler, (base + float2(end_size, 0))        / tex_size, mip);
                        float3 s2 = LUTBEAM_CALLBACK_VOLUME(trilinear_clamp_sampler, (base + float2(0,        end_size)) / tex_size, mip);
                        float3 s3 = LUTBEAM_CALLBACK_VOLUME(trilinear_clamp_sampler, (base + float2(end_size, end_size)) / tex_size, mip);
                    #endif
    
                    return (s0 * chunkblendInv.x + s1 * chunkblend.x) * chunkblendInv.y + (s2 * chunkblendInv.x + s3 * chunkblend.x) * chunkblend.y;
                #else
                    return 1;
                    #endif
            }

            #pragma vertex vert
            #pragma fragment frag
            #pragma target 5.0

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                uint id : SV_VertexID;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                BeamData beam;

                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            // check if p falls on the left or right of line formed by a-b
            float leftCheck(float2 a, float2 b, float2 p)
            {
                float checkValue = ((b.x-a.x) * (p.y-a.y) - (b.y-a.y) * (p.x-a.x));
                return checkValue;
            }
            
            void giftwrap(float2 a[8], out float2 perimeter[8], out int perimeterCount)
            {
                // 1. find leftmost point
                int currentPoint = 0;
                float leftmost = a[0].x;
                for (int i = 1; i < 8; i++)
                {
                    if(a[i].x < leftmost)
                    {
                        leftmost = a[i].x;
                        currentPoint = i;
                    }
                }
                int startPoint = currentPoint;
            
                // check max 8 times
                for (int q = 0; q < 8; q++)
                {
                    // trace from the current point to every other point
                    for (int i = 0; i < 8; i++)
                    {
                        if(i == currentPoint)
                            continue;
            
                        // check if all points are to the left
                        bool allLeft = true;
                        for (int j = 0; j < 8; j++)
                        {
                            if(i == j || j == currentPoint)
                                continue;
            
                            float check = leftCheck(a[i], a[currentPoint], a[j]);
                            if(check > 0)
                            {
                                allLeft = false;
                                break;
                            }
                        }
            
                        // If all points are to the left, store it in the perimeter array
                        if(allLeft)
                        {
                            perimeter[perimeterCount] = a[i];
                            currentPoint = i;
                            perimeterCount++;
                            break;
                        }
                    }
                    // If we get back to where we started, we are done
                    if(startPoint == currentPoint)
                        break;
                }
            }

            float4 PlaneToWorld(float4 p, float3 right, float3 up, float3 forward, float3 apex)
            {
                float3 n = p.x * right + p.y * up + p.z * forward;
                return float4(n, p.w - dot(apex, n));
            }

            float3 plane_intersect3(float4 a, float4 b, float4 c)
            {
                float3 bc = cross(b.xyz, c.xyz);
                float3 ca = cross(c.xyz, a.xyz);
                float3 ab = cross(a.xyz, b.xyz);
                return -(a.w * bc + b.w * ca + c.w * ab) / dot(a.xyz, bc);
            }

            void frustum_corners(float4 L, float4 R, float4 B, float4 T,
                                 float4 N, float4 F, out float3 c[8])
            {
                [unroll]
                for (int i = 0; i < 8; i++)
                {
                    c[i] = plane_intersect3((i & 1) ? R : L,
                                            (i & 2) ? T : B,
                                            (i & 4) ? F : N);
                }
            }

            bool all_outside(float4 p, float3 c[8])
            {
                [unroll]
                for (int i = 0; i < 8; i++)
                {
                    if (dot(p.xyz, c[i]) + p.w >= 0.0)
                        return false;
                }
                return true;
            }

            bool separated_on_axis(float3 axis, float3 a[8], float3 b[8])
            {
                float aMin =  1e30, aMax = -1e30;
                float bMin =  1e30, bMax = -1e30;
                [unroll] for (int i = 0; i < 8; i++)
                {
                    float da = dot(axis, a[i]);  aMin = min(aMin, da);  aMax = max(aMax, da);
                    float db = dot(axis, b[i]);  bMin = min(bMin, db);  bMax = max(bMax, db);
                }
                return (aMax < bMin) || (bMax < aMin);
            }

            bool frustum_overlap(float4 plane0Left, float4 plane0Right, float4 plane0Bottom,
                                 float4 plane0Top,  float4 plane0Near,  float4 plane0Far,
                                 float4 plane1Left, float4 plane1Right, float4 plane1Bottom,
                                 float4 plane1Top,  float4 plane1Near,  float4 plane1Far)
            {
                float3 c0[8];
                float3 c1[8];
                frustum_corners(plane0Left, plane0Right, plane0Bottom,
                                plane0Top,  plane0Near,  plane0Far,  c0);
                frustum_corners(plane1Left, plane1Right, plane1Bottom,
                                plane1Top,  plane1Near,  plane1Far,  c1);

                if (all_outside(plane0Left,   c1)) return false;
                if (all_outside(plane0Right,  c1)) return false;
                if (all_outside(plane0Bottom, c1)) return false;
                if (all_outside(plane0Top,    c1)) return false;
                if (all_outside(plane0Near,   c1)) return false;
                if (all_outside(plane0Far,    c1)) return false;

                if (all_outside(plane1Left,   c0)) return false;
                if (all_outside(plane1Right,  c0)) return false;
                if (all_outside(plane1Bottom, c0)) return false;
                if (all_outside(plane1Top,    c0)) return false;
                if (all_outside(plane1Near,   c0)) return false;
                if (all_outside(plane1Far,    c0)) return false;

                //#if 0
                //    float3 e0[6], e1[6];
                //    e0[0] = c0[1] - c0[0];  e0[1] = c0[2] - c0[0];
                //    e0[2] = c0[4] - c0[0];  e0[3] = c0[5] - c0[1];
                //    e0[4] = c0[6] - c0[2];  e0[5] = c0[7] - c0[3];
                //    e1[0] = c1[1] - c1[0];  e1[1] = c1[2] - c1[0];
                //    e1[2] = c1[4] - c1[0];  e1[3] = c1[5] - c1[1];
                //    e1[4] = c1[6] - c1[2];  e1[5] = c1[7] - c1[3];
                //
                //    [unroll] for (int i = 0; i < 6; i++)
                //    [unroll] for (int j = 0; j < 6; j++)
                //    {
                //        float3 axis = cross(e0[i], e1[j]);
                //        if (dot(axis, axis) < 1e-12) continue;   // parallel edges
                //        if (separated_on_axis(axis, c0, c1)) return false;
                //    }
                //#endif

                return true;
            }

            float3 rayPlane(float4 plane, float3 rayDir, float3 rayOrigin)
            {
                float denom = dot(plane.xyz, rayDir);
                float t = (plane.w - dot(plane.xyz, rayOrigin)) / denom;
                return rayOrigin+rayDir*t;
            }

            v2f vert(appdata v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                
                float4 Line0 = _DataTexture.Load(int3(0, 0, 0));
                float4 Line1 = _DataTexture.Load(int3(0, 1, 0));
                float4 Line2 = _DataTexture.Load(int3(0, 2, 0));
                float4 Line3 = _DataTexture.Load(int3(0, 3, 0));
                float4 Line4 = _DataTexture.Load(int3(0, 4, 0));
                float4 Line5 = _DataTexture.Load(int3(0, 5, 0));

                // Line0 - WorldPosXYZ, BeamIntensity
                // Line1 - ForwardXYZ, BeamFalloff
                // Line2 - UpXYZ, GoboIntensity
                // Line3 - ZoomXY, _NearSizeXY
                // Line4 - ColorRGB, FarZ
                // Line5 - Gobo, _Focus, _Focus_ApertureSize, _Frost
                // _Framing0A _Framing0B _Framing1A _Framing1B
                // _Framing2A _Framing2B _Framing3A _Framing3B
                //int offset = 100 * 4;
                //if(v.uv.x < _Test)
                //{
                //    o.beam.vertex = asfloat(-1);
                //    return o;
                //}


                BeamSettings settings = DefaultBeamSettings();
                settings.worldPos = Line0.xyz;
                settings.up = Line1.xyz;
                settings.forward = Line2.xyz;
                settings.right = cross(Line1.xyz, Line2.xyz);
                settings.zoomX = Line3.x;
                settings.zoomY = Line3.y;
                settings.farz = Line4.w;
                settings.gobo = Line5.r;
                settings.nearSizeX = Line3.z;
                settings.nearSizeY = Line3.w;
                settings.offset = _Offset;
                settings.color = Line4.rgb;
                settings.brightnessVolume = Line0.w;
                settings.brightnessGobo = Line2.w;
                settings.beamFalloff = Line1.w;
                settings.focus = _Focus;
                settings.focus_apertureSize = _Focus_ApertureSize;
                settings.frost = _Frost;
                settings.framing0A = _Framing0A;
                settings.framing0B = _Framing0B;
                settings.framing1A = _Framing1A;
                settings.framing1B = _Framing1B;
                settings.framing2A = _Framing2A;
                settings.framing2B = _Framing2B;
                settings.framing3A = _Framing3A;
                settings.framing3B = _Framing3B;
                settings.framingAngle = _FramingAngle;

                
                float4 vertexPos = v.vertex;

                float ex = settings.nearSizeX + tan(radians(max(settings.zoomX/2, 1))) * settings.farz;
                float ey = settings.nearSizeY + tan(radians(max(settings.zoomY/2, 1))) * settings.farz;
                float minWidth = 0.05;
                settings.color *= 2 / pow(ex * ey + minWidth, 0.7);

                
                BeamData beam = (BeamData)0;
    
                beam.zoomX = tan(radians(max(settings.zoomX/2, 1)));
                beam.zoomY = tan(radians(max(settings.zoomY/2, 1)));
    
            #if LUTBEAM_FOCUS
                beam.focus = settings.focus;
                beam.frost = settings.frost;
                float FocusZoomExtra = beam.focus*0.05 * settings.focus_apertureSize;
                beam.zoomX += FocusZoomExtra;
                beam.zoomY += FocusZoomExtra;
                beam.focus_apertureSize = settings.focus_apertureSize;
            #endif

                if ((!any(settings.color)) || (settings.brightnessVolume <= 0 && settings.brightnessGobo <= 0))
                {
                    beam.vertex = asfloat(-1);
                    return beam;
                }

                beam.falloff = settings.beamFalloff;
                beam.zoomX = max(beam.zoomX, 0.0001);
                beam.zoomY = max(beam.zoomY, 0.0001);

                float apexDistX = settings.nearSizeX / beam.zoomX;
                float apexDistY = settings.nearSizeY / beam.zoomY;
                float frustumNearZ  = max(apexDistX, apexDistY);
                float frustumFarZ   = frustumNearZ + settings.farz;
                float frustumOffset = -frustumNearZ + settings.offset;

                float apexZX = frustumNearZ - apexDistX;
                float apexZY = frustumNearZ - apexDistY;
                float wX = -beam.zoomX * apexZX;
                float wY = -beam.zoomY * apexZY;
                beam.aniso = float4(apexZX, apexZY, wX, wY);

                float p = settings.beamFalloff + 1e-4;
    
                float falloffNorm = exp2(3.26 - 1.54*p - 0.68*p*p);

                beam.colorGobo = settings.color * settings.brightnessGobo * 5;
                beam.colorVolume = settings.color * settings.brightnessVolume * falloffNorm * 0.1; 

                float maxVolume = max(max(beam.colorVolume.r, beam.colorVolume.g), beam.colorVolume.b);
                float maxGobo = max(max(beam.colorGobo.r, beam.colorGobo.g), beam.colorGobo.b) * 0.05;
                float C = max(maxVolume, maxGobo);

                // Binary search to find where the fade function intersects 0.5 brightness, then move the frustum back to that point.
                float eps = 0.5 / 255.0;
                float logCE = log2(max(C, 1e-20) / eps);

                float lo = 0.0;
                float hi = 0.999;
                [unroll]
                for (int i = 0; i < 12; i++)
                {
                    float mid = 0.5 * (lo + hi);
                    float L = C * (1.0 - mid) * (1.0 - mid) * pow(mid + 0.01, -p);
                    if (L > eps)
                        lo = mid;
                    else
                        hi = mid;
                }
                float farClipValue = lerp(frustumNearZ, frustumFarZ, lo) / frustumFarZ;
                float t = vertexPos.z+0.5;
                beam.vertex = vertexPos;
                beam.vertex.z = lerp(0, frustumFarZ, t*farClipValue);
                beam.vertex.x *= (beam.vertex.z - apexZX) * beam.zoomX * 2;
                beam.vertex.y *= (beam.vertex.z - apexZY) * beam.zoomY * 2;
                beam.vertex.z += frustumOffset;

                float3 right    = float3(1, 0, 0);
                float3 up       = float3(0, 1, 0);
                float3 forward  = float3(0, 0, -1);
    
                float3 corrected_pos = 0;
                float3 frustumOffsetVector = float3(0, 0, frustumOffset);

                forward = normalize(mul(ObjectToWorld_NoScale(), float4(forward, 0)).xyz);
                right   = normalize(mul(ObjectToWorld_NoScale(), float4(right, 0)).xyz);
                up      = normalize(mul(ObjectToWorld_NoScale(), float4(up, 0)).xyz);
    
                float3 worldPos = mul(ObjectToWorld_NoScale(), beam.vertex);
                beam.vertex = mul(UNITY_MATRIX_VP, float4(worldPos, 1));

                beam.screenPosition = ComputeScreenPos(beam.vertex).xy;

                float3 apex = mul(ObjectToWorld_NoScale(), float4(corrected_pos + frustumOffsetVector, 1)).xyz;
    
                beam.frustumCorrection = dot(beam.vertex, CalculateFrustumCorrection());
                beam.frustumNearZ  = frustumNearZ;
                beam.frustumFarZ   = frustumFarZ;

                float3 rayDir = normalize(worldPos - _WorldSpaceCameraPos);
                float3 rayOrigin = _WorldSpaceCameraPos;

                float3 objectPos = mul(ObjectToWorld_NoScale(), float4(0, 0, 0, 1));

                float3 cameraForward = WorldToFrustumVector(apex, forward, right, up, unity_CameraToWorld._m02_m12_m22);

                beam.rayOrigin = WorldToFrustumPosition(apex, forward, right, up, rayOrigin);
                float3 worldPosLocal = WorldToFrustumPosition(apex, forward, right, up, worldPos.xyz);
                
                float4 plane0Left   = float4(float3( 1,  0, beam.zoomX), beam.aniso.z);
                float4 plane0Right  = float4(float3(-1,  0, beam.zoomX), beam.aniso.z);
                float4 plane0Bottom = float4(float3( 0, -1, beam.zoomY), beam.aniso.w);
                float4 plane0Top    = float4(float3( 0,  1, beam.zoomY), beam.aniso.w);
                float4 plane0Near   = float4(float3(0, 0, 1), -beam.frustumNearZ);
                float4 plane0Far    = float4(float3(0, 0, -1), beam.frustumFarZ);

                plane0Left   = PlaneToWorld(plane0Left   , right, up, forward, apex);
                plane0Right  = PlaneToWorld(plane0Right  , right, up, forward, apex);
                plane0Bottom = PlaneToWorld(plane0Bottom , right, up, forward, apex);
                plane0Top    = PlaneToWorld(plane0Top    , right, up, forward, apex);
                plane0Near   = PlaneToWorld(plane0Near   , right, up, forward, apex);
                plane0Far    = PlaneToWorld(plane0Far    , right, up, forward, apex);
                
                float xMin = (v.uv.x * 2 - 1);
                float xMax = (v.uv.x * 2 - 1);//+(1.0/16);
                float yMin = (v.uv.y * 2 - 1);
                float yMax = (v.uv.y * 2 - 1);//+(1.0/16);

                float4 R0 = UNITY_MATRIX_VP[0];
                float4 R1 = UNITY_MATRIX_VP[1];
                float4 R2 = UNITY_MATRIX_VP[2];
                float4 R3 = UNITY_MATRIX_VP[3];

                float4 plane1Left   = R0 - xMin * R3;
                float4 plane1Right  = xMax * R3 - R0;
                float4 plane1Bottom = R1 - yMin * R3;
                float4 plane1Top    = yMax * R3 - R1;
                //#if UNITY_REVERSED_Z
                    float4 plane1Near = R3 - R2;
                    float4 plane1Far  = R2;
                //#else
                //    float4 plane1Near = R2 + R3;
                //    float4 plane1Far  = R3 - R2;
                //#endif

                bool check = frustum_overlap(plane0Left, plane0Right, plane0Bottom,
                                             plane0Top,  plane0Near,  plane0Far,
                                             plane1Left, plane1Right, plane1Bottom,
                                             plane1Top,  plane1Near,  plane1Far);

                float3 hitPos = rayPlane(plane0Far, rayDir, rayOrigin);
                beam.vertex = mul(UNITY_MATRIX_VP, float4(hitPos, 1));

                bool useQuad = true;
                // Make the frustum into a fullscreen quad, we are inside it anyways so performance should be unaffected.
                if (useQuad)
                {
                    //vertexPos.y = -vertexPos.y;
                    float2 ndc = (vertexPos.xy);
                    beam.vertex = float4(ndc, UNITY_NEAR_CLIP_VALUE, 1);
                
                    float d = 4.0;
                    float3 viewPos = float3(
                        d * (ndc.x + UNITY_MATRIX_P._m02) / UNITY_MATRIX_P._m00,
                        d * (ndc.y + UNITY_MATRIX_P._m12) / UNITY_MATRIX_P._m11,
                        -d);
                    float3 wp = mul(UNITY_MATRIX_I_V, float4(viewPos, 1)).xyz;
                    
                    worldPosLocal.xyz = WorldToFrustumPosition(apex, forward, right, up, wp);
                    beam.screenPosition    = ComputeScreenPos(beam.vertex).xy;
                    beam.frustumCorrection = dot(beam.vertex, CalculateFrustumCorrection());
                }
                
                //if(check)
                //    beam.vertex = asfloat(-1);
                beam.counter = check ? 1 : 0;
                beam.rayDir = (worldPosLocal - beam.rayOrigin);

                beam.DepthFadeData = UNITY_MATRIX_P._34 / dot(cameraForward, beam.rayDir);

                beam.frustumCorrection *= UNITY_MATRIX_P._34;
                beam.frustumCorrection /= beam.vertex.w;
                beam.screenPosition /= beam.vertex.w;

                beam.invBeamLength = 1 / abs(frustumNearZ - frustumFarZ);

                o.beam = beam;

                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                
                BeamData beam = i.beam;
                return float4(i.beam.counter, 1);

                float beamFalloff = beam.falloff;
                float frustumNearZ = beam.frustumNearZ;
                float frustumFarZ = beam.frustumFarZ;
                float invBeamLength = beam.invBeamLength;

                float3 rayDir = beam.rayDir;
                float3 rayOrigin = beam.rayOrigin;

                float2 suv = beam.screenPosition.xy;
    
                float raw_dist = _CameraDepthTexture.SampleLevel(point_clamp_sampler, suv, 0).r;
                float SceneDistance = beam.DepthFadeData / (raw_dist + beam.frustumCorrection);

                #if defined(SHADER_API_MOBILE)
                    SceneDistance = 9999999;
                #endif

                if(!DepthExists())
                    SceneDistance = 9999999;

                float4 leftPlane   = float4(float3( 1, 0, beam.zoomX), beam.aniso.z);
                float4 rightPlane  = float4(float3(-1, 0, beam.zoomX), beam.aniso.z);
                float4 bottomPlane = float4(float3( 0,-1, beam.zoomY), beam.aniso.w);
                float4 topPlane    = float4(float3( 0, 1, beam.zoomY), beam.aniso.w);
                float4 nearPlane   = float4(float3(0, 0,  1), -beam.frustumNearZ);
                float4 farPlane    = float4(float3(0, 0, -1),  beam.frustumFarZ);
    
                float4 planes[5] = { leftPlane, rightPlane, bottomPlane, topPlane, beam.clipPlane };

                // Near plane and far plane are parallel, so we can do the angle math just once for them :>
                float invDz = rcp(rayDir.z);
                float t4 =  (nearPlane.w - dot(nearPlane.xyz, beam.rayOrigin)) * invDz;
                float t5 = -(farPlane.w - dot(farPlane.xyz, beam.rayOrigin)) * invDz;
                float tMin = min(t4, t5);
                float tMax = max(t4, t5);

                [branch]
                if(_VRChatMirrorMode != 0)
                {
                    [unroll]
                    for(int i = 0; i < 5; i++)
                    {
                        float denom = dot(planes[i].xyz, rayDir);
                        float t = (planes[i].w - dot(planes[i].xyz, rayOrigin)) / denom;
            
                        if(denom < 0)
                            tMin = max(tMin, t);
                        else
                            tMax = min(tMax, t);
                    }
                }
                else
                {
                    [unroll]
                    for(int i = 0; i < 4; i++)
                    {
                        float denom = dot(planes[i].xyz, rayDir);
                        float t = (planes[i].w - dot(planes[i].xyz, rayOrigin)) / denom;
            
                        if(denom < 0)
                            tMin = max(tMin, t);
                        else
                            tMax = min(tMax, t);
                    }
                }

                #if LUTBEAM_FRAMING
                    [branch]
                    if(beam.framing > 0)
                    {
                        float4 pn = beam.bladePn;
                        float4 dn = beam.bladeDn;
                        float4 t  = pn / dn;
            
                        if (dn.x >= 0) tMax = min(tMax, t.x);
                        else tMin = max(tMin, t.x);
    
                        if (dn.y >= 0) tMax = min(tMax, t.y);
                        else tMin = max(tMin, t.y);
    
                        if (dn.z >= 0) tMax = min(tMax, t.z);
                        else tMin = max(tMin, t.z);
    
                        if (dn.w >= 0) tMax = min(tMax, t.w);
                        else tMin = max(tMin, t.w);
                    }
                #endif
    
                if(tMax - tMin < 0.00001)
                    discard;

                tMin = max(0, tMin);
                tMax = max(0, tMax);

    
                bool hit = (tMax > SceneDistance) && (SceneDistance > 0.000001);

                // NOTE(valuef): Regarding the if: Only clamp when the pixel depth isn't approaching the far plane.
                // This should only be false in mirrors due to the oblique frustum correction when the pixel we're drawing
                // hasn't had any depth written to it.
                // 2025-09-23
                if(SceneDistance > 0.000001)
                {
                    tMin = min(tMin, SceneDistance);
                    tMax = min(tMax, SceneDistance);
                }

                float3 entryPos = (rayOrigin + rayDir * tMin);
                float3 exitPos = (rayOrigin + rayDir * tMax);
    
                float3 entryNormalized = -entryPos.xyz;
                float3 exitNormalized  = -exitPos.xyz;

                entryNormalized.x /= (entryNormalized.z - beam.aniso.x) * beam.zoomX * 2;
                entryNormalized.y /= (entryNormalized.z - beam.aniso.y) * beam.zoomY * 2;
                entryNormalized.xy = entryNormalized.xy + 0.5;

                exitNormalized.x /= (exitNormalized.z - beam.aniso.x) * beam.zoomX * 2;
                exitNormalized.y /= (exitNormalized.z - beam.aniso.y) * beam.zoomY * 2;
                exitNormalized.xy = exitNormalized.xy + 0.5;

                float t = 0;
                float3 col = 0;


                // closest point on ray
                float3 A  = entryPos - float3(0, 0, -frustumNearZ);
                float3 B  = exitPos  - float3(0, 0, -frustumNearZ);
                float3 AB = B - A;
                float  d2 = max(dot(AB, AB), 1e-5);
                float  ct = saturate(dot(-A, AB) / d2);
                float3 closest = A + ct * AB;
                float distToSource = length(closest);
    
                // Normalize to 0-1
                t = saturate((distToSource + 0.06) * beam.invBeamLength);
    
                float volFac = (1 - t) * (1 - t) * pow(t + 0.01, -beamFalloff);
                float volFacNotHot = (1 - t) * (1 - t) * rcp(t + 0.01);
                float3 volColor = volFac * beam.colorVolume;
    
                float framing = 1;
    
                float penumbra = 10;
                float blur = 0;
                #if LUTBEAM_FOCUS
                    blur = CalculateMip(t, beam.focus, beam.frost, beam.focus_apertureSize);
                    penumbra = rcp((blur*4+1) * t);
                #endif
    
                float4 B0 = 0;
                #if LUTBEAM_FRAMING
                [branch]
                if(beam.framing > 0)
                {
                    float4 A = (beam.bladePn - tMin * beam.bladeDn) * penumbra;
                    B0 = (beam.bladePn - tMax * beam.bladeDn) * penumbra;
                    float4 S = (saturate(A) + 4 * saturate(0.5 * (A + B0)) + saturate(B0)) * (1.0 / 6.0);
                    framing = S.x * S.y * S.z * S.w;
                }
                #endif

                // early out if the fade would make it invisible anyways
                [branch]
                if (volFac * framing < 0.001)
                    discard;

                col = MagicSample(entryNormalized.xy, exitNormalized.xy, blur, beam.nestedStruct);

                col *= volColor * framing;
    
                // gobo on the surface
                [branch]
                if(hit && (any(beam.colorGobo)))
                {
                    #ifdef LUTBEAM_CALLBACK_PROJECTION
                        #ifdef CUSTOM_STRUCT_EXISTS
                            float3 goboResult = LUTBEAM_CALLBACK_PROJECTION(trilinear_clamp_sampler, exitNormalized, blur * 5, beam.nestedStruct);
                        #else
                            float3 goboResult = LUTBEAM_CALLBACK_PROJECTION(trilinear_clamp_sampler, exitNormalized, blur * 5);
                        #endif
                    #else
                        float3 goboResult = float3(1, 1, 1);
                    #endif
            
                #if LUTBEAM_FRAMING
                    [branch]
                    if (beam.framing)
                    {
                        float4 s = saturate(B0);
                        goboResult *= s.x * s.y * s.z * s.w;
                    }
                #endif
                    // large parts of gobos are black, so we can skip the heavy grab sample pretty often!
                    [branch]
                    if(any(goboResult))
                    {
                        goboResult *= volFacNotHot * beam.colorGobo;

                        float4 grab = _GrabTexture.SampleLevel(trilinear_clamp_sampler, suv, 0);
                        #if LUTBEAM_AVATAR
                            grab = 1;
                        #endif

                        col += grab.rgb * goboResult;
                    }
                }
                return float4(col, 1);
                //float3 col = LUTBeamFrag(i.beam);
                return float4(col, 0);
            }
            ENDCG
        }
    }
}
