// I dedicate this work to the public domain. Do as you will.
// Initial implementation by Torvid
// Optimizations by ValueFactory
// Tweaks and MDMX integration by Micca

#define DMX_MDMX 0
#define DMX_VRSL 0 // TODO?

#if DMX_MDMX
#include "Assets/Micca/DMX/Shared/MDMX.cginc"
#endif

struct appdata
{
    float4 vertex : POSITION;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};
struct v2f
{
    float4 vertex : SV_POSITION;
    float2 screenPosition : TEXCOORD2;
    float4 worldPos : TEXCOORD3;
    
    nointerpolation float3 color : COLOR0;
    nointerpolation uint gobo : TEXCOORD8;
    nointerpolation float angle : TEXCOORD9;
    
    nointerpolation float brightnessGobo : TEXCOORD16;
    nointerpolation float brightnessVolume : TEXCOORD17;
    nointerpolation float farZ : TEXCOORD18;

    float frustumCorrection : TEXCOORD19;
    nointerpolation float frustumNearZ : TEXCOORD20;
    nointerpolation float frustumFarZ : TEXCOORD21;
    nointerpolation float frustumOffset : TEXCOORD22;
    
    float3 cameraPosLocal : TEXCOORD23;
    float3 cameraDirLocal : TEXCOORD24;
    float dimmer : TEXCOORD25;

    float3 rayDir  : TEXCOORD26;
    float3 rayOrigin  : TEXCOORD27;
    float3 cameraForward  : TEXCOORD28;
    float4 worldPosLocal : TEXCOORD29;

    UNITY_VERTEX_OUTPUT_STEREO
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

UNITY_DECLARE_DEPTH_TEXTURE(_CameraDepthTexture);

Texture2DArray _GoboTex;
Texture2DArray _GoboLUT;
//Texture2DArray _GoboSmall;
Texture2D _GoboTex15;
Texture2D _GoboLUT15;
//Texture2D _GoboSmall15;

SamplerState _SamplerClampLinear;

float inverselerp(float a, float b, float value)
{
    return (value - a) / (b - a);
}

UNITY_INSTANCING_BUFFER_START(Props)
    UNITY_DEFINE_INSTANCED_PROP(float, _NearRadius)
    UNITY_DEFINE_INSTANCED_PROP(float, _Offset)
    UNITY_DEFINE_INSTANCED_PROP(float, _FarZ)
    UNITY_DEFINE_INSTANCED_PROP(float, _FarZMaxZoom)

    UNITY_DEFINE_INSTANCED_PROP(float, _BrightnessGoboZoomMin)
    UNITY_DEFINE_INSTANCED_PROP(float, _BrightnessGoboZoomMax)
    UNITY_DEFINE_INSTANCED_PROP(float, _BrightnessVolumeZoomMin)
    UNITY_DEFINE_INSTANCED_PROP(float, _BrightnessVolumeZoomMax)

    UNITY_DEFINE_INSTANCED_PROP(float, _Angle)
    UNITY_DEFINE_INSTANCED_PROP(float, _TiltOffset)
    UNITY_DEFINE_INSTANCED_PROP(float, _TiltMin)
    UNITY_DEFINE_INSTANCED_PROP(float, _TiltMax)
    UNITY_DEFINE_INSTANCED_PROP(float, _PanOffset)
    UNITY_DEFINE_INSTANCED_PROP(float, _PanMin)
    UNITY_DEFINE_INSTANCED_PROP(float, _PanMax)
    UNITY_DEFINE_INSTANCED_PROP(float, _LightEmission)
    UNITY_DEFINE_INSTANCED_PROP(int, _DMXMotionChannel)
    UNITY_DEFINE_INSTANCED_PROP(float4, _MotionScale)
    UNITY_DEFINE_INSTANCED_PROP(float4, _MotionOffset)

    UNITY_DEFINE_INSTANCED_PROP(float, _AngleMin)
    UNITY_DEFINE_INSTANCED_PROP(float, _AngleMax)
    UNITY_DEFINE_INSTANCED_PROP(float, _SpinMult)

    UNITY_DEFINE_INSTANCED_PROP(float, _FadeDist)
    UNITY_DEFINE_INSTANCED_PROP(float, _FadeMult)
UNITY_INSTANCING_BUFFER_END(Props)

float _Udon_DMXSpotDimmer;
float _Udon_DMXGlobalDimmer;

Texture2D _GrabTexture;

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


v2f vert (appdata v)
{
    v2f input;

    UNITY_SETUP_INSTANCE_ID(v);
    UNITY_INITIALIZE_OUTPUT(v2f, input);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(input);
    UNITY_TRANSFER_INSTANCE_ID(v, input);

#if DMX_MDMX
    //funny dmx
    // is it funny? ovo
    //yes
    // nice ^v^
    uint channel = GetDMXChannel();

    float pan = ReadDMX(channel);
    float tilt = ReadDMX(channel+2);
    float zoom = ReadDMX(channel+4);
    float dimmer = smoothstep(0,2,ReadDMX(channel+5))*2; //gives the dimmer a nice curve that makes lds happy
    float strobe = ReadStrobe(channel+6);
    float3 color = ReadColor(channel+7);
    float spinMult = UNITY_ACCESS_INSTANCED_PROP(Props, _SpinMult);
    float goboSpin = ReadSpin(channel+10) * spinMult;
    float gobo = ReadDMX(channel+11) * 16;
#else
    float pan = 0;
    float tilt = 0;
    float zoom = 0.9;
    float dimmer = 0.1;
    float strobe = 1;
    float3 color = 1;
    float spinMult = 0;
    float goboSpin = 0;
    float gobo = 3;
#endif

    input.dimmer = dimmer;
    //cap range
    input.gobo = clamp(gobo, 0, 15);

    float tiltMin = UNITY_ACCESS_INSTANCED_PROP(Props, _TiltMin);
    float tiltMax = UNITY_ACCESS_INSTANCED_PROP(Props, _TiltMax);
    float tiltOffset = UNITY_ACCESS_INSTANCED_PROP(Props, _TiltOffset);

    float panMin = UNITY_ACCESS_INSTANCED_PROP(Props, _PanMin);
    float panMax = UNITY_ACCESS_INSTANCED_PROP(Props, _PanMax);
    float panOffset = UNITY_ACCESS_INSTANCED_PROP(Props, _PanOffset);

    tilt = radians(lerp(tiltMin, tiltMax, tilt) + tiltOffset);
    pan = -radians(lerp(panMin, panMax, pan) + panOffset);

    float brightnessGoboZoomMin = UNITY_ACCESS_INSTANCED_PROP(Props, _BrightnessGoboZoomMin);
    float brightnessGoboZoomMax = UNITY_ACCESS_INSTANCED_PROP(Props, _BrightnessGoboZoomMax);
    float brightnessVolumeZoomMin = UNITY_ACCESS_INSTANCED_PROP(Props, _BrightnessVolumeZoomMin);
    float brightnessVolumeZoomMax = UNITY_ACCESS_INSTANCED_PROP(Props, _BrightnessVolumeZoomMax);

    float zoomStep = smoothstep(-1, 1, zoom);
    input.brightnessGobo = lerp(brightnessGoboZoomMin, brightnessGoboZoomMax, zoomStep);
    input.brightnessVolume = lerp(brightnessVolumeZoomMin, brightnessVolumeZoomMax, zoomStep);

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

    input.color = color * dimmer * strobe * (1.0 - _Udon_DMXSpotDimmer) * (1.0 - _Udon_DMXGlobalDimmer);

    float farZ = UNITY_ACCESS_INSTANCED_PROP(Props, _FarZ);
    float farZMaxZoom = UNITY_ACCESS_INSTANCED_PROP(Props, _FarZMaxZoom);

    input.farZ = lerp(farZ, farZMaxZoom, zoom);

    // NOTE(valuef): Vertex discard if color is close enough to black
    // 2025-09-23
    if(input.color.r + input.color.g + input.color.b <= .0003) {
      return (v2f)asfloat(-1);
    }

    float angleMin = UNITY_ACCESS_INSTANCED_PROP(Props, _AngleMin);
    float angleMax = UNITY_ACCESS_INSTANCED_PROP(Props, _AngleMax);

    input.angle = lerp(angleMin, angleMax, zoom);

    float nearRadius = UNITY_ACCESS_INSTANCED_PROP(Props, _NearRadius);
    float offset = UNITY_ACCESS_INSTANCED_PROP(Props, _Offset);
    float frustumNearZ = (nearRadius / input.angle);
    float frustumFarZ = (nearRadius / input.angle) + input.farZ;
    float frustumOffset = -(nearRadius / input.angle) - offset;

    float t = v.vertex.z+0.5;
    v.vertex.z = lerp(frustumNearZ, frustumFarZ, t);
    v.vertex.xy *= v.vertex.z * input.angle * 2;
    v.vertex.z += frustumOffset;
    
    float3 pos = 0;
    float3 dmxMovement = 0;
    
    int DMXMotionChannel = UNITY_ACCESS_INSTANCED_PROP(Props, _DMXMotionChannel);
    // for moving the whole spotlight around like in stage flight
#if DMX_MDMX
    dmxMovement = float3(ReadDMX(DMXMotionChannel), ReadDMX(DMXMotionChannel+2), ReadDMX(DMXMotionChannel+4));
#endif

    if (DMXMotionChannel >= 0)
    {
        float4 motionOffset = UNITY_ACCESS_INSTANCED_PROP(Props, _MotionOffset);
        float4 motionScale = UNITY_ACCESS_INSTANCED_PROP(Props, _MotionScale);
        pos = (dmxMovement - motionOffset) * motionScale.xyz * GetScale();
    }

    v.vertex.xy = mul(v.vertex.xy, spinMatrix);
    v.vertex.yz = mul(v.vertex.yz, tiltMatrix);
    v.vertex.xy = mul(v.vertex.xy, panMatrix);
    
    float3 forward = 0;
    float3 right = 0;
    float3 up = 0;

    forward = float3(0, 0, -1);
    forward.xy = mul(forward.xy, spinMatrix);
    forward.yz = mul(forward.yz, tiltMatrix);
    forward.xy = mul(forward.xy, panMatrix);
    right = float3(1, 0, 0);
    right.xy = mul(right.xy, spinMatrix);
    right.yz = mul(right.yz, tiltMatrix);
    right.xy = mul(right.xy, panMatrix);
    up = float3(0, 1, 0);
    up.xy = mul(up.xy, spinMatrix);
    up.yz = mul(up.yz, tiltMatrix);
    up.xy = mul(up.xy, panMatrix);
    
    forward = normalize(mul(unity_ObjectToWorld, float4(forward, 0)).xyz);
    right = normalize(mul(unity_ObjectToWorld, float4(right, 0)).xyz);
    up = normalize(mul(unity_ObjectToWorld, float4(up, 0)).xyz);

    input.worldPos = mul(ObjectToWorld_NoScale(), v.vertex);
    input.worldPos.xyz += pos;
    input.vertex = mul(UNITY_MATRIX_VP, input.worldPos);

    input.screenPosition = ComputeScreenPos(input.vertex).xy;

    float3 apex = mul(unity_ObjectToWorld, float4(0, 0, 0, 1)).xyz;
    apex -= forward * frustumOffset;
    
    apex += pos;
    
    float k = input.angle;
    float nearWidth  = 2.0 * k * frustumNearZ;
    float nearHeight = 2.0 * k * frustumNearZ;
    float farWidth   = 2.0 * k * frustumFarZ;
    float farHeight  = 2.0 * k * frustumFarZ;

    input.frustumCorrection = dot(input.vertex, CalculateFrustumCorrection());
    input.frustumNearZ  = frustumNearZ;
    input.frustumFarZ   = frustumFarZ;
    input.frustumOffset = frustumOffset;

    float3 rayDir = normalize(input.worldPos - _WorldSpaceCameraPos);
    float3 rayOrigin = _WorldSpaceCameraPos;
    float3 cameraForward = unity_CameraToWorld._m02_m12_m22;

    input.cameraForward = WorldToFrustumVector(apex, forward, right, up, cameraForward);
    input.rayDir = WorldToFrustumVector(apex, forward, right, up, rayDir);
    input.rayOrigin = WorldToFrustumPosition(apex, forward, right, up, rayOrigin);
    input.worldPosLocal.xyz = WorldToFrustumPosition(apex, forward, right, up, input.worldPos.xyz);
    
    float4 nearPlane   = float4(float3(0, 0,  1), -input.frustumNearZ);
    float4 farPlane    = float4(float3(0, 0, -1),  input.frustumFarZ);
    float4 leftPlane   = float4(normalize(float3( 1, 0, input.angle)), 0);
    float4 rightPlane  = float4(normalize(float3(-1, 0, input.angle)), 0);
    float4 bottomPlane = float4(normalize(float3( 0,-1, input.angle)), 0);
    float4 topPlane    = float4(normalize(float3( 0, 1, input.angle)), 0);
    
    
    float4 planes[6] = { leftPlane, rightPlane, bottomPlane, topPlane, nearPlane, farPlane };
    float tMin = 1e30;
    for(int i = 0; i < 6; i++) {
        tMin = min(tMin, planes[i].w - dot(planes[i].xyz, input.rayOrigin));
    }
    
    //#if !defined(SHOW_WHEN_OUTSIDE)
    //if(tMin < 0.0)
    //    return (v2f)asfloat(-1); // YEET
    //#endif
    //
    //#if !defined(SHOW_WHEN_INSIDE)
    //if(tMin > 0.0)
    //    return (v2f)asfloat(-1); // YEET
    //#endif

    return input;
}

#define chunk_size 32

float2 RotateUVs(float2 UV, float Angle)
{
	float2 Direction = float2(sin(Angle * 6.28318548), cos(Angle * 6.28318548));
	return mul(float2x2(Direction.y, -Direction.x, Direction.x, Direction.y), UV - 0.5) + 0.5;
}

float3 MagicSample(float2 start, float2 end, int gobo, float t)
{
    float tex_size = chunk_size * chunk_size;
    
    // NOTE(torvid): Impossible beam :)
    // I like this. -Micca
#if 0
    t = sqrt(t);
    t *= sin(_Time.g);
    start = RotateUVs(((start-0.5)*0.75)+0.5, t);
    end = RotateUVs(((end-0.5)*0.75)+0.5, t);
    start = saturate(start);
    end = saturate(end);
#endif

    int2 chunk = floor(start*(chunk_size-1))*chunk_size;
    float2 chunkblend = frac(start*(chunk_size-1));
    float2 chunkblendInv = 1-chunkblend;

    int2 pixel = floor(end*(chunk_size-1));
    float2 pixelblend = frac(end*(chunk_size-1));

    float4 sample4D0 = 0;
    float4 sample4D1 = 0;
    float4 sample4D2 = 0;
    float4 sample4D3 = 0;
    
    if (gobo != 15) {
        // NOTE(valuef): +0.5 to move the sample from the center of the pixel to a corner so that pixelblend becomes the bilinear blend coefficient.
        sample4D0 = _GoboLUT.SampleLevel(_SamplerClampLinear, float3(float2(chunk + float2(0,          0)          + pixel + pixelblend + .5) / tex_size, gobo), 0);
        sample4D1 = _GoboLUT.SampleLevel(_SamplerClampLinear, float3(float2(chunk + float2(chunk_size, 0)          + pixel + pixelblend + .5) / tex_size, gobo), 0);
        sample4D2 = _GoboLUT.SampleLevel(_SamplerClampLinear, float3(float2(chunk + float2(0,          chunk_size) + pixel + pixelblend + .5) / tex_size, gobo), 0);
        sample4D3 = _GoboLUT.SampleLevel(_SamplerClampLinear, float3(float2(chunk + float2(chunk_size, chunk_size) + pixel + pixelblend + .5) / tex_size, gobo), 0);
    } else {
        sample4D0 = _GoboLUT15.SampleLevel(_SamplerClampLinear, float2(chunk + float2(0,          0)          + pixel + pixelblend + .5) / tex_size, 0);
        sample4D1 = _GoboLUT15.SampleLevel(_SamplerClampLinear, float2(chunk + float2(chunk_size, 0)          + pixel + pixelblend + .5) / tex_size, 0);
        sample4D2 = _GoboLUT15.SampleLevel(_SamplerClampLinear, float2(chunk + float2(0,          chunk_size) + pixel + pixelblend + .5) / tex_size, 0);
        sample4D3 = _GoboLUT15.SampleLevel(_SamplerClampLinear, float2(chunk + float2(chunk_size, chunk_size) + pixel + pixelblend + .5) / tex_size, 0);
    }

    float3 sample4D = (sample4D0 * chunkblendInv.x + sample4D1 * chunkblend.x) * chunkblendInv.y + (sample4D2 * chunkblendInv.x + sample4D3 * chunkblend.x) * chunkblend.y;

    // gobo 15 is RGB
    if(gobo != 15)
        sample4D.rgb = sample4D.r;
    
    // NOTE(torvid) Mitigation of PIXELYNESS you can see when the light is pointing up at the night sky
    // fades out end and adds a glowy blob. not amazing but works for nowwwwwww
    //float2 t = abs(end*(2.7)-(2.7 / 2.0f));
    //float fade = saturate(pow(sqrt(t.x * t.x + t.y * t.y), 1));
    //fade = smoothstep(0,1,fade);

    return sample4D;
}

// Maybe useful in the future ikd
float3 GetWorldPosOnNearPlane(float3 rayOriginWS, float3 rayDirWS)
{
    float4 camSpacePlane = UNITY_MATRIX_P[3] + UNITY_MATRIX_P[2];
    float4 worldPlane = mul(transpose(UNITY_MATRIX_I_V), camSpacePlane);
    float3 N = worldPlane.xyz;
    float  W = worldPlane.w;
    float denom = dot(rayDirWS, N);
    if (abs(denom) < 1e-6)
        return rayOriginWS;

    float t = -(dot(rayOriginWS, N) + W) / denom;
    return rayOriginWS + rayDirWS * t;
}

float4 frag(v2f input) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
    
    float frustumNearZ = input.frustumNearZ;
    float frustumFarZ = input.frustumFarZ;
    float frustumOffset = input.frustumOffset;

    float3 view_delta = input.worldPosLocal - input.rayOrigin;
    float sq_view_dist = dot(view_delta, view_delta);
    float view_dist = sqrt(sq_view_dist);

    float3 cameraForward = input.cameraForward;
    float3 rayDir = view_delta / view_dist;
    float3 rayOrigin = input.rayOrigin;// + rayDir * ( _ProjectionParams.y / dot(cameraForward, rayDir));

    float4 nearPlane   = float4(float3(0, 0,  1), -input.frustumNearZ);
    float4 farPlane    = float4(float3(0, 0, -1),  input.frustumFarZ);
    float4 leftPlane   = float4(normalize(float3( 1, 0, input.angle)), 0);
    float4 rightPlane  = float4(normalize(float3(-1, 0, input.angle)), 0);
    float4 bottomPlane = float4(normalize(float3( 0,-1, input.angle)), 0);
    float4 topPlane    = float4(normalize(float3( 0, 1, input.angle)), 0);

    float raw_dist = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, input.screenPosition.xy / input.vertex.w);
    float SceneDistance = CorrectedLinearEyeDepth(raw_dist, input.frustumCorrection / input.vertex.w) / dot(cameraForward, rayDir);
    
    float4 planes[6] = { leftPlane, rightPlane, bottomPlane, topPlane, nearPlane, farPlane };
    float tMin = -1e30;
    float tMax = 1e30;
    //float tMin2 = 1e30;
    for(int i = 0; i < 6; i++) {
        float denom = dot(planes[i].xyz, rayDir);
        float t = (planes[i].w - dot(planes[i].xyz, rayOrigin)) / denom;
        
        //tMin2 = min(tMin2, planes[i].w - dot(planes[i].xyz, rayOrigin));

        if (denom < 0) tMin = max(tMin, t);
        else tMax = min(tMax, t);
    }
    
    
    //#if !defined(SHOW_WHEN_OUTSIDE)
    //if(tMin2 < 0.0)
    //    return 0;
    //#endif
    //
    //#if !defined(SHOW_WHEN_INSIDE)
    //if(tMin2 > 0.0)
    //    return 0;
    //#endif
    float entryDistance = max(0, tMin);
    float exitDistance = max(0, tMax);
    //if(SceneDistance > 10)
    //    SceneDistance = 100000000;
    // 
    //return frac(SceneDistance);

    bool hit = (exitDistance > SceneDistance);

    if(SceneDistance < 0.001)
        hit = false;

    //return SceneDistance < 0.001;

    //if(SceneDistance > 10)
    //    hit = false;

    // NOTE(valuef): Regarding the if: Only clamp when the pixel depth isn't approaching the far plane.
    // This should only be false in mirrors due to the oblique frustum correction when the pixel we're drawing
    // hasn't had any depth written to it.
    // 2025-09-23
    if(SceneDistance >= 0)
    {
        entryDistance = min(entryDistance, SceneDistance);
        exitDistance = min(exitDistance, SceneDistance);
    }

    // NOTE(valuef): Save on a sqrt by just comparing the squared equlidean length instead.
    //  distance(a, b) < dist
    //  sqrt(dot(a - b, a - b)) < dist
    //  dot(a - b, a - b) < (dist*dist)

    float dist = .01;
    float2 delta = entryDistance - exitDistance;
    if(dot(delta, delta) < (dist*dist)) {
        discard;
    }

    float3 entryPos = rayOrigin + rayDir * entryDistance;
    float3 exitPos = rayOrigin + rayDir * exitDistance;

    entryPos.xyz = -entryPos.zxy;
    exitPos.xyz = -exitPos.zxy;
    
    float3 entryNormalized = entryPos.yzx;
    float3 exitNormalized = exitPos.yzx;
    
    entryNormalized.xy /= entryNormalized.z * input.angle * 2;
    entryNormalized.xy = entryNormalized.xy + 0.5;
    entryNormalized.z = inverselerp(frustumNearZ, frustumFarZ, entryNormalized.z);
    
    exitNormalized.xy /= exitNormalized.z * input.angle * 2;
    exitNormalized.xy = exitNormalized.xy + 0.5;
    exitNormalized.z = inverselerp(frustumNearZ, frustumFarZ, exitNormalized.z);
    
    // Hacky way to get a 0-1 gradient from nearZ to farZ for fading the beam
    float alignemnt = cameraForward.z*0.5+0.5;

    float t = lerp(entryNormalized.z, sqrt(exitNormalized.z), alignemnt);
    float t0 = t;
    t += 0.1; // adding 0.1 here mitigates the box issue at the light source
    t *= 0.9;
    t = saturate(t);
    
    float3 col = 0;
    
#if defined(VOLUME_PASS)
    //help
    // fluffy

    //if(tMin < 0) // in frustum
    //{
        col = MagicSample(entryNormalized.xy, exitNormalized.xy, input.gobo, t0);
    //}
    //else
    //{
    //    // it didn't do anything ;v;
    //    // omg it did something
    //    float index0 = floor((EdgeEncode(entryNormalized.xy) * (chunk_size-1)));
    //    float index1 = floor((EdgeEncode(entryNormalized.xy) * (chunk_size-1))+1);
    //    float ifrac = frac((EdgeEncode(entryNormalized.xy) * (chunk_size-1)));
    //    
    //    float2 pos0 = floor(float2(exitNormalized.xy * (chunk_size-1))) + float2(index0 * chunk_size, 0);
    //    float2 pos1 = floor(float2(exitNormalized.xy * (chunk_size-1))) + float2(index1 * chunk_size, 0);
    //    float2 pixelBlend0 = frac(float2(exitNormalized.xy * (chunk_size-1)));
    //    float2 pixelBlend1 = frac(float2(exitNormalized.xy * (chunk_size-1)));
    //    
    //    float col0 = _GoboSmall.SampleLevel(_SamplerClampLinear, float3((pos0 + pixelBlend0 + 0.5) / float2(chunk_size*chunk_size, chunk_size), input.gobo), 0);
    //    float col1 = _GoboSmall.SampleLevel(_SamplerClampLinear, float3((pos1 + pixelBlend1 + 0.5) / float2(chunk_size*chunk_size, chunk_size), input.gobo), 0);
    //    col = lerp(col0, col1, ifrac);
    //
    //    if(input.gobo != 15)
    //        col.rgb = col.r;
    //}
        
    col *= pow(1-t,2)*(50/((t*1000)+1));
    col *= input.color * input.brightnessVolume;
    col *= 10;
    // Added a pow falloff here to increase the source brightness. Please teach me optimization tho ty -Micca
    col += col * pow(1-t,30)*(700);
    col *= lerp(0.25,1,alignemnt);
    col = clamp(col, 0, 1000);
        
#endif

#if defined(DECAL_PASS)
    if(hit)
    {
        float3 gobo;
        //help
    
        if (input.gobo != 15) {
            gobo = _GoboTex.SampleLevel(_SamplerClampLinear, float3(exitNormalized.xy, input.gobo), 0).r;
        } else {
            gobo = _GoboTex15.SampleLevel(_SamplerClampLinear, exitNormalized.xy, 0);
        }
    
        float3 scenePos = _WorldSpaceCameraPos + rayDir * SceneDistance;
        
        //float t2 = distance(apex, scenePos) / frustumFarZ;
        //// exponential decay
        gobo *= (1-t0)*(200/((t0*1000)+1));
        gobo *= input.brightnessGobo;
        gobo *= input.color;
        #if defined(IS_GRAB)
            float4 grab = _GrabTexture.SampleLevel(_SamplerClampLinear, input.screenPosition.xy / input.vertex.w, 0);
            col += grab.rgb * gobo * 20; // magic number
        #else
            col += gobo * 6; // more magic number, idk.. something is super weird about the brightness. micca pls help
        #endif
    }
#endif

    return float4(col, 1);
    
}

