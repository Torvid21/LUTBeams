// I dedicate this work to the public domain. Do as you will.
// Initial implementation by Torvid
// Optimizations by ValueFactory
// Tweaks and MDMX integration by Micca

// position resolution, IE how many possible places the camera can be.
#define start_size 8
// angular resolution, IE how many angles can the beam be viewed from.
#define end_size 128

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

BeamData LUTBeamVert(float4 vertexPos, float zoomX, float zoomY, float farz, float nearRadiusX, float nearRadiusY, float offset, float3 color, float brightnessVolume, float brightnessGobo, float beamFalloff)
{
    BeamData beam = (BeamData)0;

    zoomX = max(zoomX, 0.0001);
    zoomY = max(zoomY, 0.0001);
    beam.zoomX = zoomX;
    beam.zoomY = zoomY;

    float apexDistX = nearRadiusX / zoomX;      // lens-to-apex distance per axis
    float apexDistY = nearRadiusY / zoomY;
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

    float3 forward = float3(0, 0, -1);
    float3 right = float3(1, 0, 0);
    float3 up = float3(0, 1, 0);

    // Shader-based rotation and position offsets should probably go here!
    // Since you're digging here, you probably already know what you are doing, so who am I to say things x>
    float3 positionOffset = 0;

#if LUTBEAM_CALLBACK_TRANSFORM
    float3x3 rotation = LUTBeamCallbackTransform(beam.vertex, positionOffset);
    beam.vertex.xyz = mul(beam.vertex, rotation).xyz;
    forward = mul(forward, rotation).xyz;
    right = mul(right, rotation).xyz;
    up = mul(up, rotation).xyz;
    // Example
    //float3x3 LUTBeamTransform(float3 vertex, inout float3 offset)
    //{
    //    float goboSpin = _Time.g;
    //    float tilt = _Time.g;
    //    float pan = _Time.g;
    //
    //    float3x3 spinMatrix3 = float3x3(
    //        cos(goboSpin), -sin(goboSpin), 0,
    //        sin(goboSpin),  cos(goboSpin), 0,
    //        0,              0,             1
    //    );
    //
    //    float3x3 tiltMatrix3 = float3x3(
    //        1, 0,           0,
    //        0, cos(tilt), -sin(tilt),
    //        0, sin(tilt),  cos(tilt)
    //    );
    //
    //    float3x3 panMatrix3 = float3x3(
    //        cos(pan), -sin(pan), 0,
    //        sin(pan),  cos(pan), 0,
    //        0,         0,        1
    //    );
    //
    //    float3x3 combined = mul(spinMatrix3, mul(tiltMatrix3, panMatrix3));
    //
    //    offset = float3(cos(_Time.g), 0, sin(_Time.g)) * 5;
    //
    //    return combined;
    //}
#else

#endif

    forward = normalize(mul(unity_ObjectToWorld, float4(forward, 0)).xyz);
    right = normalize(mul(unity_ObjectToWorld, float4(right, 0)).xyz);
    up = normalize(mul(unity_ObjectToWorld, float4(up, 0)).xyz);
    
    float3 worldPos = mul(ObjectToWorld_NoScale(), beam.vertex);
    worldPos.xyz += positionOffset;
    beam.vertex = mul(UNITY_MATRIX_VP, float4(worldPos, 1));

    beam.screenPosition = ComputeScreenPos(beam.vertex).xy;

    float3 apex = mul(unity_ObjectToWorld, float4(0, 0, 0, 1)).xyz;
    apex -= forward * frustumOffset;
    
    apex += positionOffset;

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
    float lengthNorm = 1;//1.0 / (2.0 * max(zoomX, zoomY) * frustumFarZ);
    beam.colorVolume = color * brightnessVolume * 0.1 * lengthNorm;
    
    // Calculate compensation value to 'normalize' falloff so it doesn't explode to a crazy high value.
    float e = 0.01;
    float Aa = 1.0 + e;
    float p = beamFalloff + 1e-4;
    float3 q = float3(1.0, 2.0, 3.0) - p;
    float3 G = (pow(Aa, q) - pow(e, q)) / q;
    float  I = Aa*Aa*G.x - 2.0*Aa*G.y + G.z;
    beam.falloffNorm = 3.198 / I;

    if (!any(color) || (brightnessVolume <= 0 && brightnessGobo <= 0))
    {
        beam.vertex = 1.0 / 0.0;
        return beam;
    }

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

        // If the beam touches the mirror, stretch its far-z vertexes and place them on the surface
        // of the oblique clipping plane, so we don't see the inside of the beam!
        if (vertexPos.z > 0.0)
        {
            float pathW = dot(pl.xyz, forward);
            float sd = dot(pl.xyz, worldPos) + pl.w - 0.001;
            if (sd < 0.0)
            {
                worldPos -= forward * (sd / pathW);
                worldPos += forward * 1;
                beam.vertex = mul(UNITY_MATRIX_VP, float4(worldPos, 1));
                beam.screenPosition = ComputeScreenPos(beam.vertex).xy;
                beam.frustumCorrection = dot(beam.vertex, CalculateFrustumCorrection());
                beam.worldPosLocal.xyz = WorldToFrustumPosition(apex, forward, right, up, worldPos);
            }
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

float3 MagicSample(float2 start, float2 end, float2 pixel)
{
#if 1
    float tex_size = start_size * end_size;

    float2 posF          = saturate(start) * (start_size - 1);
    float2 cell          = min(floor(posF), start_size - 2);
    float2 chunkblend    = posF - cell;
    float2 chunkblendInv = 1 - chunkblend;
    float2 chunk         = cell * end_size;
    
    float2 base = chunk + clamp(end * (end_size - 1), 0, end_size - 1) + 0.5;
    
    #if LUTBEAM_CALLBACK_VOLUME
        float3 s0 = LUTBeamCallbackVolume(_SamplerClampLinear, (base) / tex_size);
        float3 s1 = LUTBeamCallbackVolume(_SamplerClampLinear, (base + float2(end_size, 0)) / tex_size);
        float3 s2 = LUTBeamCallbackVolume(_SamplerClampLinear, (base + float2(0,        end_size)) / tex_size);
        float3 s3 = LUTBeamCallbackVolume(_SamplerClampLinear, (base + float2(end_size, end_size)) / tex_size);
    
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

    #if LUTBEAM_CALLBACK_VOLUME
        return LUTBeamCallbackVolume(_SamplerClampLinear, base / tex_size);
    #else
        return 1;
    #endif
#endif
}

float3 LUTBeamFrag(BeamData beam, float beamFalloff)
{
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
    
    float entryDistance = max(0, tMin);
    float exitDistance = max(0, tMax);
    
    bool hit = (exitDistance > SceneDistance);

    if(SceneDistance < 0.001)
        hit = false;

    // NOTE(valuef): Regarding the if: Only clamp when the pixel depth isn't approaching the far plane.
    // This should only be false in mirrors due to the oblique frustum correction when the pixel we're drawing
    // hasn't had any depth written to it.
    // 2025-09-23
    if(SceneDistance >= 0)
    {
        entryDistance = min(entryDistance, SceneDistance);
        exitDistance = min(exitDistance, SceneDistance);
    }
    
    if(exitDistance - entryDistance < 0.01)
        discard;
    
    float3 entryPos = rayOrigin + rayDir * entryDistance;
    float3 exitPos = rayOrigin + rayDir * exitDistance;
    
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

    col = MagicSample(entryNormalized.xy, exitNormalized.xy, beam.vertex.xy);

    // more correct but dosen't look good ??
    //col *= (exitDistance - entryDistance);

    col *= volColor;

    // gobo on the surface
    if(hit && any(beam.colorGobo))
    {
#if LUTBEAM_CALLBACK_PROJECTION
        float3 goboResult = LUTBeamCallbackProjection(_SamplerClampLinear, exitNormalized.xy);
#else
        float3 goboResult = 1;
#endif
        // large parts of gobos are black, so we can skip the heavy grab sample pretty often!
        if(any(goboResult))
        {
            goboResult *= volFacNotHot * beam.colorGobo;

            float4 grab = _GrabTexture.SampleLevel(_SamplerClampLinear, suv, 0);
            col += grab.rgb * goboResult;
        }
    }

    return float4(col, 1);
    
}