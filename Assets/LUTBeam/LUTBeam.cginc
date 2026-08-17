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
struct BeamSettings
{
    float zoomX;
    float zoomY;
    float farz;
    float nearSizeX;
    float nearSizeY;
    float offset;
    float3 color;
    float brightnessVolume;
    float brightnessGobo;
    float beamFalloff;
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
    return settings;
}
#define pi 3.1415926535897

BeamData LUTBeamVert(float4 vertexPos, BeamSettings settings)
{
    BeamData beam = (BeamData)0;
    
    beam.zoomX = tan(radians(max(settings.zoomX, 1)));
    beam.zoomY = tan(radians(max(settings.zoomY, 1)));

    float ex = settings.nearSizeX + beam.zoomX * settings.farz;
    float ey = settings.nearSizeY + beam.zoomY * settings.farz;
    float minWidth = 0.05;
    settings.color *= 2 / pow(ex * ey + minWidth, 0.7);


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
    float farClipValue = max(lo, 0.05);

    float t = vertexPos.z+0.5;
    beam.vertex = vertexPos;
    beam.vertex.z = lerp(0, frustumFarZ, t*farClipValue);
    beam.vertex.x *= (beam.vertex.z - apexZX) * beam.zoomX * 2;
    beam.vertex.y *= (beam.vertex.z - apexZY) * beam.zoomY * 2;
    beam.vertex.z += frustumOffset;
    
    // special case, push the front corners in a little bit, makes it fit better
    if(beam.vertex.z > 0 && length(beam.vertex.xy) > 0.1)
    {
        beam.vertex = vertexPos;
        beam.vertex.z = lerp(0, frustumFarZ*0.9, t*farClipValue);
        beam.vertex.x *= (beam.vertex.z - apexZX) * beam.zoomX * 2;
        beam.vertex.y *= (beam.vertex.z - apexZY) * beam.zoomY * 2;
        beam.vertex.z += frustumOffset;
    }

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
    
    // 1. Camera-inside test, check if the camera is inside the beam frustum and make it a fullscreen-quad in that case.
    #if defined(USING_STEREO_MATRICES)
        float3 testCam = (unity_StereoWorldSpaceCameraPos[0] + unity_StereoWorldSpaceCameraPos[1]) * 0.5;
    #else
        float3 testCam = _WorldSpaceCameraPos;
    #endif
    testCam = WorldToFrustumPosition(apex, forward, right, up, testCam);

    // Changed the mesh to an octagon, so inside-frustum-check needs 8 planes now.
    float farClipped = lerp(frustumNearZ, frustumFarZ, farClipValue);

    float inside = min(-frustumNearZ - testCam.z, farClipped  + testCam.z);
    float margin = 0.1;
    [unroll]
    for (int k = 0; k < 8; k++)
    {
        float angle  = (k + 0.5) * 0.78539816;
        float2 n2 = float2(cos(angle), sin(angle));
        float slopeX = n2.x * beam.zoomX;
        float slopeY = n2.y * beam.zoomY;
        float slope = sqrt(slopeX*slopeX + slopeY*slopeY);
        float offset = -(slopeX*slopeX*apexZX + slopeY*slopeY*apexZY) / max(slope, 1e-6);
        float dist  = (offset - dot(float3(n2, slope), testCam)) * rsqrt(1.0 + slope*slope);
        inside = min(inside, dist);
    }
    bool useQuad = inside > -margin;

    // 2. Mirrors can cut open a hole in the beam, push the beam back in that case so it gently touches the mirror surface.
    if (_VRChatMirrorMode != 0)
    {
        // Also generate a clipping plane so it can be cut nice and volumetric-ly at the surface of the mirror..
        float4 mirrorPlane = float4(UNITY_MATRIX_VP._m30, UNITY_MATRIX_VP._m31, UNITY_MATRIX_VP._m32, UNITY_MATRIX_VP._m33) -
                             float4(UNITY_MATRIX_VP._m20, UNITY_MATRIX_VP._m21, UNITY_MATRIX_VP._m22, UNITY_MATRIX_VP._m23);
        float3 planeNormal = WorldToFrustumVector(apex, forward, right, up, mirrorPlane.xyz);
        float planeOffset = dot(mirrorPlane.xyz, apex) + mirrorPlane.w;
        beam.clipPlane = float4(-planeNormal, planeOffset) / length(planeNormal);
        
        useQuad = false;

        float dCurrent = dot(mirrorPlane.xyz, worldPos) + mirrorPlane.w - 0.001;
        float dStart   = dot(mirrorPlane.xyz, apex) + mirrorPlane.w - 0.001;
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
    
    beam.rayDir = (worldPosLocal - beam.rayOrigin);

    beam.DepthFadeData = UNITY_MATRIX_P._34 / dot(cameraForward, beam.rayDir);

    beam.frustumCorrection *= UNITY_MATRIX_P._34;
    beam.frustumCorrection /= beam.vertex.w;
    beam.screenPosition /= beam.vertex.w;

    beam.invBeamLength = 1 / abs(frustumNearZ - frustumFarZ);

    return beam;
 }

float Bayer2(float2 a)
{
    a = floor(a);
    return frac(a.x * 0.5 + a.y * a.y * 0.75);
}
float Bayer4(float2 a) { return Bayer2(0.5 * a) * 0.25 + Bayer2(a); }
float Bayer8(float2 a) { return Bayer4(0.5 * a) * 0.25 + Bayer2(a); }


float3 MagicSample(float2 start, float2 end, float blur, NESTED_STRUCT_TYPE nestedStruct)
{
    float tex_size = start_size * end_size;
    
    float2 posF          = saturate(start) * (start_size - 1.001);
    float2 cell          = floor(posF);
    float2 chunkblend    = posF - cell;
    float2 chunkblendInv = 1 - chunkblend;
    float2 chunk         = cell * end_size;
        
    float2 base = chunk + saturate(end) * (end_size - 1) + 0.5;
    
    #ifdef LUTBEAM_CALLBACK_VOLUME
        #ifdef CUSTOM_STRUCT_EXISTS
            float3 s0 = LUTBEAM_CALLBACK_VOLUME(trilinear_clamp_sampler, (base + float2(0,        0))        / tex_size, 0, nestedStruct);
            float3 s1 = LUTBEAM_CALLBACK_VOLUME(trilinear_clamp_sampler, (base + float2(end_size, 0))        / tex_size, 0, nestedStruct);
            float3 s2 = LUTBEAM_CALLBACK_VOLUME(trilinear_clamp_sampler, (base + float2(0,        end_size)) / tex_size, 0, nestedStruct);
            float3 s3 = LUTBEAM_CALLBACK_VOLUME(trilinear_clamp_sampler, (base + float2(end_size, end_size)) / tex_size, 0, nestedStruct);
        #else
            float3 s0 = LUTBEAM_CALLBACK_VOLUME(trilinear_clamp_sampler, (base + float2(0,        0))        / tex_size, 0);
            float3 s1 = LUTBEAM_CALLBACK_VOLUME(trilinear_clamp_sampler, (base + float2(end_size, 0))        / tex_size, 0);
            float3 s2 = LUTBEAM_CALLBACK_VOLUME(trilinear_clamp_sampler, (base + float2(0,        end_size)) / tex_size, 0);
            float3 s3 = LUTBEAM_CALLBACK_VOLUME(trilinear_clamp_sampler, (base + float2(end_size, end_size)) / tex_size, 0);
        #endif
    
        return (s0 * chunkblendInv.x + s1 * chunkblend.x) * chunkblendInv.y + (s2 * chunkblendInv.x + s3 * chunkblend.x) * chunkblend.y;
    #else
        return 1;
    #endif
}

float3 LUTBeamFrag(BeamData beam)
{
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
    float blur = 0;

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
}
