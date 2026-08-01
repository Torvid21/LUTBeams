struct ColorGradingPreset {
    float colorTemperature; 
    float colorCastAdjustment; 
    float saturation; 
    float3 brightness; 
    float3 contrast; 
    float3 highlight; 
    float midpoint; 
    float blackCorrection; 
};

class ColourGrading
{
static const float3x3 LIN_2_LMS_MAT = float3x3(
    float3(3.90405e-1, 5.49941e-1, 8.92632e-3),
    float3(7.08416e-2, 9.63172e-1, 1.35775e-3),
    float3(2.31082e-2, 1.28021e-1, 9.36245e-1)
);

static const float3x3 LMS_2_LIN_MAT = float3x3(
    float3(2.85847e+0, -1.62879e+0, -2.48910e-2),
    float3(-2.10182e-1,  1.15820e+0,  3.24281e-4),
    float3(-4.18120e-2, -1.18169e-1,  1.06867e+0)
);

float3 WhiteBalance(float3 c, float temperature, float tint)
{
    float t1 = temperature / 1200.0f;
    float t2 = tint / 180.0f;

    // Get the CIE xy chromaticity of the reference white point.
    // Note: 0.31271 = x value on the D65 white point
    float x = 0.31271f - t1 * (t1 < 0.0f ? 0.1f : 0.05f);
    float standardIlluminantY = 2.87f * x - 3.0f * x * x - 0.27509507f;
    float y = standardIlluminantY + t2 * 0.05;

    // Calculate the coefficients in the LMS space.
    float3 w1 = float3(0.949237, 1.03542, 1.08728); // D65 white point

    // CIExyToLMS
    float Y = 1.0f;
    float X = Y * x / y;
    float Z = Y * (1.0f - x - y) / y;
    float L = 0.7328f * X + 0.4296f * Y - 0.1624f * Z;
    float M = -0.7036f * X + 1.6975f * Y + 0.0061f * Z;
    float S = 0.0030f * X + 0.0136f * Y + 0.9834f * Z;
    float3 w2 = float3(L, M, S);

    float3 balance = w1 / w2;

    float3 lms = mul(LIN_2_LMS_MAT, c);
    lms *= balance;
    return mul(LMS_2_LIN_MAT, lms);
}

float3 CurveAdjust(float3 x, float3 p, float m, float3 c)
{
    return (x < m) ? pow(x, p) / pow(m, p - 1) : c * (x - m) + m;
}

float3 colorGradingProcess(ColorGradingPreset p, float3 c) 
{
    c = WhiteBalance(c, p.colorTemperature, p.colorCastAdjustment);
    
    // Apply saturation adjustment
    float luminance = dot(c, float3(0.2126, 0.7152, 0.0722));
    c = lerp(luminance, c, p.saturation);

    // Apply brightness adjustment
    c *= p.brightness;
    
    // Apply parametric curve for contrast, highlight, and midpoint correction
    c = CurveAdjust(c, p.contrast, p.midpoint, p.highlight);
    
    // Apply black correction
    c = max(0, c + p.blackCorrection);
    
    return c;
}
};