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

struct BeamData
{
    // Start texcoords at 40 so they are unlikely to be used by something else.
    float4 vertex : SV_POSITION;
    float2 screenPosition : TEXCOORD40;
    float zoomX : TEXCOORD41;
    float zoomY : TEXCOORD42;
    float frustumCorrection : TEXCOORD43;
    float frustumNearZ : TEXCOORD44;
    float frustumFarZ : TEXCOORD45;
    float frustumOffset : TEXCOORD46;
    float3 rayOrigin  : TEXCOORD47;
    float3 cameraForward  : TEXCOORD48;
    float4 worldPosLocal : TEXCOORD49;
    float3 colorGobo : TEXCOORD50;
    float3 colorVolume : TEXCOORD51;
    float4 clipPlane : TEXCOORD52;
    float4 falloffNorm : TEXCOORD53;
    float4 aniso : TEXCOORD54;
    float falloff : TEXCOORD55;
    float3 worldPos : TEXCOORD57;
    NESTED_STRUCT_TYPE nestedStruct : TEXCOORD56;
};

float inverselerp(float from, float to, float value)
{
    return (value - from) / (to - from);
}

UNITY_DECLARE_DEPTH_TEXTURE(_CameraDepthTexture);

SamplerState _SamplerClampLinear;
Texture2D _GrabTexture;
float _VRChatMirrorMode;

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

float CorrectedLinearEyeDepth(float z, float frustumCorrection)
{
    return 1.0 / (z / UNITY_MATRIX_P._34 + frustumCorrection);
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

BeamData LUTBeamVert(float4 vertexPos, float zoomX, float zoomY, float farz, float nearSizeX, float nearSizeY, float offset, float3 color, float brightnessVolume, float brightnessGobo, float beamFalloff)
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

    //beam.clipPlane = float4(0, 0, 0, 1); 
    
    float t = vertexPos.z+0.5;
    beam.vertex = vertexPos;
    beam.vertex.z = lerp(frustumNearZ, frustumFarZ, t);
    beam.vertex.x *= (beam.vertex.z - apexZX) * zoomX * 2;
    beam.vertex.y *= (beam.vertex.z - apexZY) * zoomY * 2;
    beam.vertex.z += frustumOffset;
    
    float3 right    = float3(1, 0, 0);
    float3 up       = float3(0, 1, 0);
    float3 forward  = float3(0, 0, -1);
    
    // Shader-based rotation and position offsets should probably go here!
    // Since you're digging here, you probably already know what you are doing, so who am I to say things x>
    float3 corrected_pos = 0;

    #ifdef LUTBEAM_CALLBACK_VERTEX
        corrected_pos = LUTBEAM_CALLBACK_VERTEX(float3(0, 0, 0));
        beam.vertex.xyz = LUTBEAM_CALLBACK_VERTEX(beam.vertex.xyz);
        forward = LUTBEAM_CALLBACK_VERTEX(forward) - corrected_pos;
        right = LUTBEAM_CALLBACK_VERTEX(right) - corrected_pos;
        up = LUTBEAM_CALLBACK_VERTEX(up) - corrected_pos;
    #endif

    forward = normalize(mul(unity_ObjectToWorld, float4(forward, 0)).xyz);
    right = normalize(mul(unity_ObjectToWorld, float4(right, 0)).xyz);
    up = normalize(mul(unity_ObjectToWorld, float4(up, 0)).xyz);
    
    float3 worldPos = mul(unity_ObjectToWorld, beam.vertex);
    beam.worldPos = worldPos;
    beam.vertex = mul(UNITY_MATRIX_VP, float4(worldPos, 1));

    beam.screenPosition = ComputeScreenPos(beam.vertex).xy;

    float3 apex = mul(unity_ObjectToWorld, float4(corrected_pos + float3(0, 0, frustumOffset), 1)).xyz;

    beam.frustumCorrection = dot(beam.vertex, CalculateFrustumCorrection());
    beam.frustumNearZ  = frustumNearZ;
    beam.frustumFarZ   = frustumFarZ;
    beam.frustumOffset = frustumOffset;

    float3 rayDir = normalize(worldPos - _WorldSpaceCameraPos);
    float3 rayOrigin = _WorldSpaceCameraPos;
    float3 cameraForward = unity_CameraToWorld._m02_m12_m22;

    float3 objectPos = mul(unity_ObjectToWorld, float4(0, 0, 0, 1));

    beam.cameraForward = WorldToFrustumVector(apex, forward, right, up, cameraForward);
    beam.rayOrigin = WorldToFrustumPosition(apex, forward, right, up, rayOrigin);
    beam.worldPosLocal.xyz = WorldToFrustumPosition(apex, forward, right, up, worldPos.xyz);
    
    beam.colorGobo = color * brightnessGobo * 1;
    beam.colorVolume = color * brightnessVolume * 0.1;
    
    float e = 0.01;
    float Aa = 1.0 + e;
    float p = beamFalloff + 1e-4;
    float3 q = float3(1.0, 2.0, 3.0) - p;
    float3 G = (pow(Aa, q) - pow(e, q)) / q;
    float  I = Aa*Aa*G.x - 2.0*Aa*G.y + G.z;
    beam.falloffNorm = 3.198 / I;

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
            beam.worldPosLocal.xyz = WorldToFrustumPosition(apex, forward, right, up, worldPos);
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
    
        beam.worldPosLocal.xyz = WorldToFrustumPosition(apex, forward, right, up, wp);
        beam.screenPosition    = ComputeScreenPos(beam.vertex).xy;
        beam.frustumCorrection = dot(beam.vertex, CalculateFrustumCorrection());
    }

    return beam;
 }

float Bayer2(float2 a) { a = floor(a); return frac(a.x * 0.5 + a.y * a.y * 0.75); }
float Bayer4(float2 a) { return Bayer2(0.5 * a) * 0.25 + Bayer2(a); }
float Bayer8(float2 a) { return Bayer4(0.5 * a) * 0.25 + Bayer2(a); }

float3 MagicSample(float2 start, float2 end, float2 pixel, NESTED_STRUCT_TYPE nestedStruct)
{
    #if 1
        float tex_size = start_size * end_size;

        float2 posF          = saturate(start) * (start_size - 1);
        float2 cell          = min(floor(posF), start_size - 2);
        float2 chunkblend    = posF - cell;
        float2 chunkblendInv = 1 - chunkblend;
        float2 chunk         = cell * end_size;
        
        float2 base = chunk + clamp(end * (end_size - 1), 0, end_size - 1) + 0.5;
        
        #ifdef LUTBEAM_CALLBACK_VOLUME
            #ifdef CUSTOM_STRUCT_EXISTS
                float3 s0 = LUTBEAM_CALLBACK_VOLUME(_SamplerClampLinear, (base + float2(0,        0))        / tex_size, nestedStruct);
                float3 s1 = LUTBEAM_CALLBACK_VOLUME(_SamplerClampLinear, (base + float2(end_size, 0))        / tex_size, nestedStruct);
                float3 s2 = LUTBEAM_CALLBACK_VOLUME(_SamplerClampLinear, (base + float2(0,        end_size)) / tex_size, nestedStruct);
                float3 s3 = LUTBEAM_CALLBACK_VOLUME(_SamplerClampLinear, (base + float2(end_size, end_size)) / tex_size, nestedStruct);
            #else
                float3 s0 = LUTBEAM_CALLBACK_VOLUME(_SamplerClampLinear, (base + float2(0,        0))        / tex_size);
                float3 s1 = LUTBEAM_CALLBACK_VOLUME(_SamplerClampLinear, (base + float2(end_size, 0))        / tex_size);
                float3 s2 = LUTBEAM_CALLBACK_VOLUME(_SamplerClampLinear, (base + float2(0,        end_size)) / tex_size);
                float3 s3 = LUTBEAM_CALLBACK_VOLUME(_SamplerClampLinear, (base + float2(end_size, end_size)) / tex_size);
            #endif

            return (s0 * chunkblendInv.x + s1 * chunkblend.x) * chunkblendInv.y
                + (s2 * chunkblendInv.x + s3 * chunkblend.x) * chunkblend.y;
        #else
            return 1;
        #endif
    #else
        // I realized I can sample just once, the angular resolution will look dithery
        // but maybe we can get away with it, ahaha. I left the old verison commented out
        // in case people get upset
        float tex_size = start_size * end_size;
        float2 n = float2(Bayer4(pixel), Bayer4(pixel.yx + 31.0));
        float2 posF  = saturate(start) * (start_size - 1);
        float2 cell  = floor(posF + n);
        float2 chunk = cell * end_size;

        float2 base = chunk + clamp(end * (end_size - 1), 0, end_size - 1) + 0.5;

        #ifdef LUTBEAM_CALLBACK_VOLUME
            #ifdef NESTED_STRUCT_TYPE
                float3 goboResult = LUTBEAM_CALLBACK_VOLUME(_SamplerClampLinear, base / tex_size, nestedStruct);
            #else
                float3 goboResult = LUTBEAM_CALLBACK_VOLUME(_SamplerClampLinear, base / tex_size);
            #endif
        #else
            float3 goboResult = float3(1,1,1);
        #endif
        
        return goboResult;
#endif
}

float2 sphIntersect(float3 ro, float3 rd, float3 ce, float ra)
{
    float3 oc = ro - ce;
    float b = dot( oc, rd );
    float3 qc = oc - b*rd;
    float h = ra*ra - dot( qc, qc );
    if( h < 0.0 )
        return float2(-1.0, -1.0); // no intersection
    h = sqrt( h );
    return float2( -b-h, -b+h );
}

float3 LUTBeamFrag(BeamData beam)
{
    float beamFalloff = beam.falloff;
    float frustumNearZ = beam.frustumNearZ;
    float frustumFarZ = beam.frustumFarZ;
    float frustumOffset = beam.frustumOffset;

    float3 view_delta = beam.worldPosLocal - beam.rayOrigin;
    float sq_view_dist = dot(view_delta, view_delta);
    float view_dist = sqrt(sq_view_dist);

    float3 cameraForward = beam.cameraForward;
    float3 rayDir = view_delta / view_dist;
    float3 rayOrigin = beam.rayOrigin;

    float2 suv = beam.screenPosition.xy / beam.vertex.w;

    float raw_dist = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, suv);
    float SceneDistance = CorrectedLinearEyeDepth(raw_dist, beam.frustumCorrection / beam.vertex.w) / dot(cameraForward, rayDir);
    
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
    
    float4 planes[7] = { leftPlane, rightPlane, bottomPlane, topPlane, nearPlane, farPlane, beam.clipPlane };

    float tMin = -1e30;
    float tMax = 1e30;

    [unroll]
    for(int i = 0; i < 7; i++)
    {
        float denom = dot(planes[i].xyz, rayDir);
        float t = (planes[i].w - dot(planes[i].xyz, rayOrigin)) / denom;

        if (denom < 0)
            tMin = max(tMin, t);
        else
            tMax = min(tMax, t);
    }
    float2 st = sphIntersect(_WorldSpaceCameraPos, normalize(beam.worldPos - _WorldSpaceCameraPos), float3(0, 0, 0), 5);
    

    #ifdef LUTBEAM_CALLBACK_DEPTH
        #ifdef NESTED_STRUCT_TYPE
            LUTBEAM_CALLBACK_DEPTH(tMin, tMax, nestedStruct);
        #else
            LUTBEAM_CALLBACK_DEPTH(tMin, tMax);
        #endif
    #endif
    
     tMin = max(0, tMin);
     tMax = max(0, tMax);
    
    if( st.y<0.0 ) { }
    else
    {
        //return saturate(tMin - st.x);
        st.y = max(0, st.y);
        st.x = max(0, st.x);

        if((tMin > st.x) && (tMin > st.y) && (tMax > st.x) && (tMax > st.y))
        {
            // sphere entirely in front
        }
        else if((tMin < st.x) && (tMin < st.y) && (tMax < st.x) && (tMax < st.y))
        {
            // sphere entirely behind
        }
        else
        {
            if(st.x < tMin && st.y < tMax && st.y > tMin && st.x < tMax)
            {
                tMin = st.y;
                tMax = tMax;
            }
            else if(tMin < st.x && tMin < st.y && tMax > st.x && tMax > st.y)
            {
                tMin = tMin;
                tMax = st.x;
            }
            else if(tMin < st.x && tMin < st.y && tMax > st.x && tMax < st.y)
            {
                tMin = tMin;
                tMax = st.x;
            }
            else if(st.x < tMin && st.y > tMax)
            {
                tMin = 0;
                tMax = 0;
            }
        }
    }

    
    bool hit = (tMax > SceneDistance);

    if(SceneDistance < 0.001)
        hit = false;

    // NOTE(valuef): Regarding the if: Only clamp when the pixel depth isn't approaching the far plane.
    // This should only be false in mirrors due to the oblique frustum correction when the pixel we're drawing
    // hasn't had any depth written to it.
    // 2025-09-23
    if(SceneDistance >= 0)
    {
        tMin = min(tMin, SceneDistance);
        tMax = min(tMax, SceneDistance);
    }

    if(tMax - tMin < 0.01)
        discard;
    
    float3 entryPos = rayOrigin + rayDir * tMin;
    float3 exitPos = rayOrigin + rayDir * tMax;
    
    entryPos.xyz = -entryPos.zxy;
    exitPos.xyz = -exitPos.zxy;
    

    float3 entryNormalized = entryPos.yzx;
    float3 exitNormalized = exitPos.yzx;
    
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
    float3 A  = entryPos - float3(frustumNearZ, 0, 0);
    float3 B  = exitPos  - float3(frustumNearZ, 0, 0);
    float3 AB = B - A;
    float  d2 = max(dot(AB, AB), 1e-5);
    float  ct = saturate(dot(-A, AB) / d2);
    float3 closest = A + ct * AB;
    float distToSource = length(closest);

    // Normalize to 0-1
    t = saturate(inverselerp(frustumNearZ-0.06, frustumFarZ, distToSource + frustumNearZ));

    float volFac = (1 - t) * (1 - t) * pow(t + 0.01, -beamFalloff);
    float volFacNotHot = (1 - t) * (1 - t) * pow(t + 0.01, -1);
    float3 volColor = volFac * beam.colorVolume * beam.falloffNorm;

    // early out if the fade would kill the anyways
    if(volFac < 0.001)
        discard;

    col = MagicSample(entryNormalized.xy, exitNormalized.xy, beam.vertex.xy, beam.nestedStruct);

     col *= volColor;

    // gobo on the surface
    if(hit && (any(beam.colorGobo)))
    {
        #ifdef LUTBEAM_CALLBACK_PROJECTION
            #ifdef CUSTOM_STRUCT_EXISTS
                float3 goboResult = LUTBEAM_CALLBACK_PROJECTION(_SamplerClampLinear, exitNormalized, beam.nestedStruct);
            #else
                float3 goboResult = LUTBEAM_CALLBACK_PROJECTION(_SamplerClampLinear, exitNormalized);
            #endif
        #else
            float3 goboResult = float3(1, 1, 1);
        #endif
        // large parts of gobos are black, so we can skip the heavy grab sample pretty often!
        if(any(goboResult))
        {
            goboResult *= volFacNotHot * beam.colorGobo;

            float4 grab = _GrabTexture.SampleLevel(_SamplerClampLinear, suv, 0);
            #if LUTBEAM_AVATAR
                grab = 1;
            #endif

            col += grab.rgb * goboResult;
        }
    }

    return float4(col, 1);// * float3(1, -100000, 5)
}