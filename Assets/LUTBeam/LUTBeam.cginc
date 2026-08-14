// I dedicate this work to the public domain. Do as you will.
// Initial implementation by Torvid
// Optimizations by ValueFactory
// Tweaks and MDMX integration by Micca
// position resolution, IE how many possible places the camera can be.
#define start_size 16
// angular resolution, IE how many angles can the beam be viewed from.
#define end_size 64

struct dummy_struct {};

#define CUSTOM_STRUCT_EXISTS
#ifndef NESTED_STRUCT_TYPE
    #define NESTED_STRUCT_TYPE dummy_struct
    #undef CUSTOM_STRUCT_EXISTS
#endif

struct BeamData
{
    // Start texcoords at 40 so they are unlikely to be used by something else.
    float4 vertex : SV_POSITION;
    noperspective float frustumCorrection : TEXCOORD40;
    float3 rayDir : TEXCOORD41;

    noperspective float2 screenPosition : TEXCOORD42;

    nointerpolation  float zoomX : TEXCOORD43;
    nointerpolation  float zoomY : TEXCOORD44;
    nointerpolation  float frustumNearZ : TEXCOORD45;
    nointerpolation  float frustumFarZ : TEXCOORD46;
    nointerpolation  float invBeamLength : TEXCOORD47;
    
    nointerpolation  float frustumOffset : TEXCOORD48;
    nointerpolation  float3 rayOrigin  : TEXCOORD49;
    nointerpolation  float3 colorGobo : TEXCOORD50;
    nointerpolation  float3 colorVolume : TEXCOORD51;
    nointerpolation  float4 clipPlane : TEXCOORD52;
    nointerpolation  float4 aniso : TEXCOORD53;
    nointerpolation  float falloff : TEXCOORD54;
    NESTED_STRUCT_TYPE nestedStruct : TEXCOORD55;

    noperspective float DepthFadeData : TEXCOORD56;
    nointerpolation  float focus : TEXCOORD57;
};

float inverselerp(float from, float to, float value)
{
    return (value - from) / (to - from);
}

UNITY_DECLARE_DEPTH_TEXTURE(_CameraDepthTexture);
SamplerState trilinear_clamp_sampler;
Texture2D _GrabTexture;
float _VRChatMirrorMode;

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

BeamData LUTBeamVert(float4 vertexPos, float zoomX, float zoomY, float farz, float nearSizeX, float nearSizeY, float offset, float3 color, float brightnessVolume, float brightnessGobo, float beamFalloff, float focus)
{
    BeamData beam = (BeamData)0;
    
    if ((!any(color)) || (brightnessVolume <= 0 && brightnessGobo <= 0))
    {
        beam.vertex = asfloat(-1);
        return beam;
    }

    beam.falloff = beamFalloff;
    zoomX = max(zoomX, 0.0001);
    zoomY = max(zoomY, 0.0001);
    beam.zoomX = zoomX;
    beam.zoomY = zoomY;
    beam.focus = focus;

    float apexDistX = nearSizeX / zoomX;      // lens-to-apex distance per axis
    float apexDistY = nearSizeY / zoomY;
    float frustumNearZ  = max(apexDistX, apexDistY);
    float frustumFarZ   = frustumNearZ + farz;
    float frustumOffset = -frustumNearZ + offset;

    float apexZX = frustumNearZ - apexDistX;    // >= 0, one of them is always 0
    float apexZY = frustumNearZ - apexDistY;
    float wX = -zoomX * apexZX;
    float wY = -zoomY * apexZY;
    beam.aniso = float4(apexZX, apexZY, wX, wY);

    float t = vertexPos.z+0.5;
    beam.vertex = vertexPos;
    beam.vertex.z = lerp(frustumNearZ, frustumFarZ, t);
    beam.vertex.x *= (beam.vertex.z - apexZX) * zoomX * 2;
    beam.vertex.y *= (beam.vertex.z - apexZY) * zoomY * 2;
    beam.vertex.z += frustumOffset;
    
    float3 right    = float3(1, 0, 0);
    float3 up       = float3(0, 1, 0);
    float3 forward  = float3(0, 0, -1);
    
    float3 corrected_pos = 0;
    float3 frustumOffsetVector = float3(0, 0, frustumOffset);

    #ifdef LUTBEAM_CALLBACK_VERTEX
        corrected_pos = LUTBEAM_CALLBACK_VERTEX(float3(0, 0, 0));
        beam.vertex.xyz = LUTBEAM_CALLBACK_VERTEX(beam.vertex.xyz);
        forward = LUTBEAM_CALLBACK_VERTEX(forward) - corrected_pos;
        right = LUTBEAM_CALLBACK_VERTEX(right) - corrected_pos;
        up = LUTBEAM_CALLBACK_VERTEX(up) - corrected_pos;
        frustumOffsetVector = LUTBEAM_CALLBACK_VERTEX(frustumOffsetVector) - corrected_pos;
    #endif
        
    forward = normalize(mul(unity_ObjectToWorld, float4(forward, 0)).xyz);
    right = normalize(mul(unity_ObjectToWorld, float4(right, 0)).xyz);
    up = normalize(mul(unity_ObjectToWorld, float4(up, 0)).xyz);
    
    float3 worldPos = mul(unity_ObjectToWorld, beam.vertex);
    beam.vertex = mul(UNITY_MATRIX_VP, float4(worldPos, 1));

    beam.screenPosition = ComputeScreenPos(beam.vertex).xy;

    float3 apex = mul(unity_ObjectToWorld, float4(corrected_pos + frustumOffsetVector, 1)).xyz;
    
    beam.frustumCorrection = dot(beam.vertex, CalculateFrustumCorrection());
    beam.frustumNearZ  = frustumNearZ;
    beam.frustumFarZ   = frustumFarZ;
    beam.frustumOffset = frustumOffset;

    float3 rayDir = normalize(worldPos - _WorldSpaceCameraPos);
    float3 rayOrigin = _WorldSpaceCameraPos;

    float3 objectPos = mul(unity_ObjectToWorld, float4(0, 0, 0, 1));

    float3 cameraForward = WorldToFrustumVector(apex, forward, right, up, unity_CameraToWorld._m02_m12_m22);

    beam.rayOrigin = WorldToFrustumPosition(apex, forward, right, up, rayOrigin);
    float3 worldPosLocal = WorldToFrustumPosition(apex, forward, right, up, worldPos.xyz);
    
    float e = 0.01;
    float Aa = 1.0 + e;
    float p = beamFalloff + 1e-4;
    float3 q = float3(1.0, 2.0, 3.0) - p;
    float3 G = (pow(Aa, q) - pow(e, q)) / q;
    float  I = Aa*Aa*G.x - 2.0*Aa*G.y + G.z;
    float falloffNorm = 3.198 / I;

    beam.colorGobo = color * brightnessGobo * 1;
    beam.colorVolume = color * brightnessVolume * 0.1 * falloffNorm;

    // 1. Camera-inside test, check if the camera is inside the beam frustum and make it a fullscreen-quad in that case.
    #if defined(USING_STEREO_MATRICES)
        float3 testCam = (unity_StereoWorldSpaceCameraPos[0] + unity_StereoWorldSpaceCameraPos[1]) * 0.5;
    #else
        float3 testCam = _WorldSpaceCameraPos;
    #endif
    testCam = WorldToFrustumPosition(apex, forward, right, up, testCam);

    float invLenX = rsqrt(1 + zoomX * zoomX);
    float invLenY = rsqrt(1 + zoomY * zoomY);
    float inside = min(min(
        min((wX - dot(float3( 1, 0, zoomX), testCam)) * invLenX,
            (wX - dot(float3(-1, 0, zoomX), testCam)) * invLenX),
        min((wY - dot(float3( 0,-1, zoomY), testCam)) * invLenY,
            (wY - dot(float3( 0, 1, zoomY), testCam)) * invLenY)),
        min(-frustumNearZ - testCam.z,
             frustumFarZ  + testCam.z));

    float margin = 0.25;
    bool useQuad = inside > -margin;

    // 2. Mirrors can cut open a hole in the beam, push the beam back in that case so it gently touches the mirror surface.
    if (_VRChatMirrorMode != 0)
    {
        // Also generate a clipping plane so it can be cut nice and volumetric-ly..
        float4 pl = float4(UNITY_MATRIX_VP._m30, UNITY_MATRIX_VP._m31, UNITY_MATRIX_VP._m32, UNITY_MATRIX_VP._m33) - float4(UNITY_MATRIX_VP._m20, UNITY_MATRIX_VP._m21, UNITY_MATRIX_VP._m22, UNITY_MATRIX_VP._m23);
        float3 nf = WorldToFrustumVector(apex, forward, right, up, pl.xyz);
        float  wf = dot(pl.xyz, apex) + pl.w;
        beam.clipPlane = float4(-nf, wf) / length(nf);
        
        useQuad = false;

        float dCurrent = dot(pl.xyz, worldPos) + pl.w - 0.001;
        float dStart   = dot(pl.xyz, apex) + pl.w - 0.001;
        if (dCurrent <= 0.0)
        {
            float denom = dCurrent - dStart;
            float t = (abs(denom) > 1e-6) ? dCurrent / denom : 1.0;
            t = saturate(t);

            worldPos = lerp(worldPos, apex, t);

            beam.vertex = mul(UNITY_MATRIX_VP, float4(worldPos, 1));
            beam.screenPosition = ComputeScreenPos(beam.vertex).xy;
            beam.frustumCorrection = dot(beam.vertex, CalculateFrustumCorrection());
            worldPosLocal.xyz = WorldToFrustumPosition(apex, forward, right, up, worldPos);
        }
    }

    // Make the frustum into a fullscreen quad, we are inside it anyways so performance should be unaffected.
    if (useQuad)
    {
        beam.vertex = float4(sign(vertexPos.x), sign(vertexPos.y), UNITY_NEAR_CLIP_VALUE, 1.0);
    
        float2 ndc = sign(vertexPos.xy) * 2.0;
        beam.vertex = float4(ndc, UNITY_NEAR_CLIP_VALUE, 1.0);
    
        const float d = 4.0;
        float3 viewPos = float3(
            d * (ndc.x + UNITY_MATRIX_P._m02) / UNITY_MATRIX_P._m00,
            d * (ndc.y + UNITY_MATRIX_P._m12) / UNITY_MATRIX_P._m11,
            -d);
        float3 wp = mul(UNITY_MATRIX_I_V, float4(viewPos, 1)).xyz;
    
        worldPosLocal.xyz = WorldToFrustumPosition(apex, forward, right, up, wp);
        beam.screenPosition    = ComputeScreenPos(beam.vertex).xy;
        beam.frustumCorrection = dot(beam.vertex, CalculateFrustumCorrection());
    }
    
    beam.rayDir = (worldPosLocal - beam.rayOrigin);

    beam.DepthFadeData = UNITY_MATRIX_P._34 / dot(cameraForward, beam.rayDir);

    beam.frustumCorrection *= UNITY_MATRIX_P._34;
    beam.frustumCorrection /= beam.vertex.w;
    beam.screenPosition /= beam.vertex.w;

    float4 leftPlane   = float4(float3( 1, 0, beam.zoomX), beam.aniso.z);
    float4 rightPlane  = float4(float3(-1, 0, beam.zoomX), beam.aniso.z);
    float4 bottomPlane = float4(float3( 0,-1, beam.zoomY), beam.aniso.w);
    float4 topPlane    = float4(float3( 0, 1, beam.zoomY), beam.aniso.w);
    float4 nearPlane   = float4(float3(0, 0,  1), -beam.frustumNearZ);
    float4 farPlane    = float4(float3(0, 0, -1),  beam.frustumFarZ);
    
    float4 planes[7] = { leftPlane, rightPlane, bottomPlane, topPlane, nearPlane, farPlane, beam.clipPlane };

    beam.invBeamLength = 1/abs(frustumNearZ - frustumFarZ);
    return beam;
 }

float Bayer2(float2 a)
{
    a = floor(a);
    return frac(a.x * 0.5 + a.y * a.y * 0.75);
}
float Bayer4(float2 a) { return Bayer2(0.5 * a) * 0.25 + Bayer2(a); }
float Bayer8(float2 a) { return Bayer4(0.5 * a) * 0.25 + Bayer2(a); }

float SoftBlade(float4 P, float3 ro, float3 rd, float t0, float t1, float invPenumbra)
{
    float pn = P.w - dot(P.xyz, ro);
    float dn = dot(P.xyz, rd);
    float A  = (pn - t0 * dn) * invPenumbra;
    float B  = (pn - t1 * dn) * invPenumbra;

    return (saturate(A) + 4 * saturate(0.5 * (A + B)) + saturate(B)) * (1.0 / 6.0);
}

void BladeCut(float4 bladePlane, float3 rayOrigin, float3 rayDir, inout float tMax, inout float tMin)
{
    float pn = bladePlane.w - dot(bladePlane.xyz, rayOrigin);
    float dn = dot(bladePlane.xyz, rayDir);
    
    if (dn > 0)       tMax = min(tMax, pn / dn);
    else if (dn < 0)  tMin = max(tMin, pn / dn);
    else if (pn < 0)  discard;
}

float CalculateMip(float t, float Focus)
{
    //return Focus;
    float A = 1;
    float focus = lerp(0.0, 1, Focus);
    t = sqrt(t);

    float blur = abs(t-Focus);//saturate(A * abs(1-(t / focus)));
                
    blur = 1-blur;
    blur = blur*blur;
    blur = 1-blur;

    //blur = sqrt(blur);
    //blur *= 1-t;
                
    //float gradient = abs(t*2-1);
    //
    //gradient = 1-pow(saturate(t*4), 4);//pow(gradient, 2);
    //
    return saturate(blur);//saturate(abs(t - _Frost))*3;//saturate(abs(t-0.5))*5;
}

float3 MagicSample(float2 start, float2 end, float2 pixel, bool highQuality, float t, float focus, NESTED_STRUCT_TYPE nestedStruct)
{
    if (highQuality)
    {
        float tex_size = start_size * end_size;

        float2 posF          = saturate(start) * (start_size - 1.001);
        float2 cell          = floor(posF);
        float2 chunkblend    = posF - cell;
        float2 chunkblendInv = 1 - chunkblend;
        float2 chunk         = cell * end_size;

        //#ifdef LUTBEAM_CALLBACK_BLUR
            float mip    = CalculateMip(t, focus) * 2.5;
            float margin = clamp(exp2(mip), 0.5, end_size * 0.5);
            float2 inTile = margin + saturate(end) * (end_size - 2 * margin);
            float2 base = chunk + inTile;
        //#else
        //    float2 base = chunk + saturate(end) * (end_size - 1) + 0.5;
        //#endif

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
    else
    {
        // I realized I can sample just once, the angular resolution will look dithery
        // but maybe we can get away with it, ahaha. I left the old verison commented out
        // in case people get upset
        float tex_size = start_size * end_size;
        float2 n = Bayer4(pixel);
        float2 posF = saturate(start) * (start_size - 1.001);
        float2 cell  = floor(posF + n);
        float2 chunk = cell * end_size;

        float2 base = chunk + clamp(end * (end_size - 1), 0, end_size - 1) + 0.5;

        #ifdef LUTBEAM_CALLBACK_VOLUME
            #ifdef CUSTOM_STRUCT_EXISTS
                float3 goboResult = LUTBEAM_CALLBACK_VOLUME(trilinear_clamp_sampler, base / tex_size, 0, nestedStruct);
            #else
                float3 goboResult = LUTBEAM_CALLBACK_VOLUME(trilinear_clamp_sampler, base / tex_size, 0);
            #endif
        #else
            float3 goboResult = float3(1, 1, 1);
        #endif
        
        return goboResult;
    }
}


float3 LUTBeamFrag(BeamData beam, bool highQuality = true)
{
    float beamFalloff = beam.falloff;
    float frustumNearZ = beam.frustumNearZ;
    float frustumFarZ = beam.frustumFarZ;
    float invBeamLength = beam.invBeamLength;
    float frustumOffset = beam.frustumOffset;

    float3 rayDir = beam.rayDir;
    float3 rayOrigin = beam.rayOrigin;

    float2 suv = beam.screenPosition.xy;
    
    float raw_dist = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, suv);
    float SceneDistance = beam.DepthFadeData / (raw_dist + beam.frustumCorrection);

    #if LUTBEAM_AVATAR
        SceneDistance = 9999999;
    #endif

    #if defined(SHADER_API_MOBILE)
        SceneDistance = 9999999;
    #endif

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

    if (_VRChatMirrorMode != 0)
    {
        [unroll]
        for(int i = 0; i < 5; i++)
        {
            float denom = dot(planes[i].xyz, rayDir);
            float t = (planes[i].w - dot(planes[i].xyz, rayOrigin)) / denom;

            if (denom < 0)
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

            if (denom < 0)
                tMin = max(tMin, t);
            else
                tMax = min(tMax, t);
        }
    }

    float angle = _FramingAngle;
    float tau = 3.1415926536897 * 2;
    float2 r0 = float2(cos(angle+tau*0.00), sin(angle+tau*0.00));
    float2 r1 = float2(cos(angle+tau*0.25), sin(angle+tau*0.25));
    float2 r2 = float2(cos(angle+tau*0.50), sin(angle+tau*0.50));
    float2 r3 = float2(cos(angle+tau*0.75), sin(angle+tau*0.75));

    float invTwoL = 1;

    float4 bladePlane0 = float4((r0 - (_Framing0B - _Framing0A) * invTwoL * r1), 0.5 * (_Framing0A + _Framing0B), 0);
    float4 bladePlane2 = float4((r1 - (_Framing1B - _Framing1A) * invTwoL * r2), 0.5 * (_Framing1A + _Framing1B), 0);
    float4 bladePlane3 = float4((r2 - (_Framing2B - _Framing2A) * invTwoL * r3), 0.5 * (_Framing2A + _Framing2B), 0);
    float4 bladePlane1 = float4((r3 - (_Framing3B - _Framing3A) * invTwoL * r0), 0.5 * (_Framing3A + _Framing3B), 0);

    BladeCut(bladePlane0, rayOrigin, rayDir, tMax, tMin);
    BladeCut(bladePlane1, rayOrigin, rayDir, tMax, tMin);
    BladeCut(bladePlane2, rayOrigin, rayDir, tMax, tMin);
    BladeCut(bladePlane3, rayOrigin, rayDir, tMax, tMin);

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
    float falloff = 10;

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
    float volFacNotHot = (1 - t) * (1 - t) * pow(t + 0.01, -1);
    float3 volColor = volFac * beam.colorVolume;
     
    float blur = CalculateMip(t, beam.focus);

    float penumbra = (1)/((blur*4+1) * t);
    float framing = 1;
    framing *= SoftBlade(bladePlane0, rayOrigin, rayDir, tMin, tMax, penumbra);
    framing *= SoftBlade(bladePlane1, rayOrigin, rayDir, tMin, tMax, penumbra);
    framing *= SoftBlade(bladePlane2, rayOrigin, rayDir, tMin, tMax, penumbra);
    framing *= SoftBlade(bladePlane3, rayOrigin, rayDir, tMin, tMax, penumbra);

    // early out if the fade would make it invisible anyways
    if(volFac < 0.001)
        discard;

    col = MagicSample(entryNormalized.xy, exitNormalized.xy, beam.vertex.xy, highQuality, t, beam.focus, beam.nestedStruct);

    col *= volColor * framing;
    
    // gobo on the surface
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

        goboResult *= saturate(dot(exitPos.yzx, bladePlane0) * penumbra);
        goboResult *= saturate(dot(exitPos.yzx, bladePlane1) * penumbra);
        goboResult *= saturate(dot(exitPos.yzx, bladePlane2) * penumbra);
        goboResult *= saturate(dot(exitPos.yzx, bladePlane3) * penumbra);

        // large parts of gobos are black, so we can skip the heavy grab sample pretty often!
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
}