//
// HLSL implementation of the GT7 Tone Mapping operator.
// Adapted from the sample C++ implementation.
//
// Version history:
// 1.0    (2025-08-10)    Initial C++ release.
// 1.0h   (2025-08-19)    HLSL adaptation.
//
// -----
// MIT License
//
// Copyright (c) 2025 Polyphony Digital Inc.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// -----------------------------------------------------------------------------
// "GT Tone Mapping" curve with convergent shoulder.
// -----------------------------------------------------------------------------
struct GTToneMappingCurveV2
{
    float peakIntensity_;
    float alpha_;
    float midPoint_;
    float linearSection_;
    float toeStrength_;
    float kA_, kB_, kC_;
};


// -----------------------------------------------------------------------------
// GT7 Tone Mapping struct and functions.
// -----------------------------------------------------------------------------
struct GT7ToneMapping
{
    float sdrCorrectionFactor_;
    float framebufferLuminanceTarget_;
    float framebufferLuminanceTargetUcs_; // Target luminance in UCS space
    GTToneMappingCurveV2 curve_;
    float blendRatio_;
    float fadeStart_;
    float fadeEnd_;
};

class GT7Tonemapper
{
// -----------------------------------------------------------------------------
// Mode options.
// -----------------------------------------------------------------------------
#define TONE_MAPPING_UCS_ICTCP  0
#define TONE_MAPPING_UCS_JZAZBZ 1

#define TONE_MAPPING_UCS TONE_MAPPING_UCS_ICTCP

// -----------------------------------------------------------------------------
// Defines the SDR reference white level used in our tone mapping (typically 250 nits).
// -----------------------------------------------------------------------------
static const float GRAN_TURISMO_SDR_PAPER_WHITE = 250.0f; // cd/m^2

// -----------------------------------------------------------------------------
// Gran Turismo luminance-scale conversion helpers.
// In Gran Turismo, 1.0f in the linear frame-buffer space corresponds to
// REFERENCE_LUMINANCE cd/m^2 of physical luminance (typically 100 cd/m^2).
// -----------------------------------------------------------------------------
static const float REFERENCE_LUMINANCE = 100.0f; // cd/m^2 <-> 1.0f

float frameBufferValueToPhysicalValue(float fbValue)
{
    // Converts linear frame-buffer value to physical luminance (cd/m^2)
    // where 1.0 corresponds to REFERENCE_LUMINANCE (e.g., 100 cd/m^2).
    return fbValue * REFERENCE_LUMINANCE;
}

float physicalValueToFrameBufferValue(float physical)
{
    // Converts physical luminance (cd/m^2) to a linear frame-buffer value
    // where 1.0 corresponds to REFERENCE_LUMINANCE (e.g., 100 cd/m^2).
    return physical / REFERENCE_LUMINANCE;
}

// -----------------------------------------------------------------------------
// Utility functions.
// -----------------------------------------------------------------------------
float chromaCurve(float x, float a, float b)
{
    // Note: The original C++ smoothStep is identical to the HLSL intrinsic.
    return 1.0f - smoothstep(a, b, x);
}

// -----------------------------------------------------------------------------
// "GT Tone Mapping" curve with convergent shoulder.
// -----------------------------------------------------------------------------

void InitializeCurve(inout GTToneMappingCurveV2 curve,
                     float monitorIntensity,
                     float alpha,
                     float grayPoint,
                     float linearSection,
                     float toeStrength)
{
    curve.peakIntensity_ = monitorIntensity;
    curve.alpha_         = alpha;
    curve.midPoint_      = grayPoint;
    curve.linearSection_ = linearSection;
    curve.toeStrength_   = toeStrength;

    // Pre-compute constants for the shoulder region.
    float k = (linearSection - 1.0f) / (alpha - 1.0f);
    curve.kA_ = monitorIntensity * linearSection + monitorIntensity * k;
    curve.kB_ = -monitorIntensity * k * exp(linearSection / k);
    curve.kC_ = -1.0f / (k * monitorIntensity);
}

float EvaluateCurve(in GTToneMappingCurveV2 curve, float x)
{
    if (x < 0.0f)
    {
        return 0.0f;
    }

    float weightLinear = smoothstep(0.0f, curve.midPoint_, x);
    float weightToe    = 1.0f - weightLinear;

    // Shoulder mapping for highlights.
    float shoulder = curve.kA_ + curve.kB_ * exp(x * curve.kC_);

    if (x < curve.linearSection_ * curve.peakIntensity_)
    {
        float toeMapped = curve.midPoint_ * pow(x / curve.midPoint_, curve.toeStrength_);
        return weightToe * toeMapped + weightLinear * x;
    }
    else
    {
        return shoulder;
    }
}

// -----------------------------------------------------------------------------
// EOTF / inverse-EOTF for ST-2084 (PQ).
// Note: Introduce exponentScaleFactor to allow scaling of the exponent in the EOTF for Jzazbz.
// -----------------------------------------------------------------------------
float eotfSt2084(float n, float exponentScaleFactor = 1.0)
{
    n = clamp(n, 0.0f, 1.0f);

    // Base functions from SMPTE ST 2084:2014
    // Converts from normalized PQ (0-1) to absolute luminance in cd/m^2 (linear light)
    // Assumes float input; does not handle integer encoding (Annex)
    // Assumes full-range signal (0-1)
    const float m1  = 0.1593017578125f;                // (2610 / 4096) / 4
    const float m2  = 78.84375f * exponentScaleFactor; // (2523 / 4096) * 128
    const float c1  = 0.8359375f;                      // 3424 / 4096
    const float c2  = 18.8515625f;                     // (2413 / 4096) * 32
    const float c3  = 18.6875f;                        // (2392 / 4096) * 32
    const float pqC = 10000.0f;                        // Maximum luminance supported by PQ (cd/m^2)

    // Does not handle signal range from 2084 - assumes full range (0-1)
    float np = pow(n, 1.0f / m2);
    float l  = max(0.0f, np - c1);
    
    l = l / (c2 - c3 * np);
    l = pow(l, 1.0f / m1);

    // Convert absolute luminance (cd/m^2) into the frame-buffer linear scale.
    return physicalValueToFrameBufferValue(l * pqC);
}

float inverseEotfSt2084(float v, float exponentScaleFactor = 1.0)
{
    const float m1  = 0.1593017578125f;
    const float m2  = 78.84375f * exponentScaleFactor;
    const float c1  = 0.8359375f;
    const float c2  = 18.8515625f;
    const float c3  = 18.6875f;
    const float pqC = 10000.0f;

    // Convert the frame-buffer linear scale into absolute luminance (cd/m^2).
    float physical = frameBufferValueToPhysicalValue(v);
    float y        = physical / pqC; // Normalize for the ST-2084 curve

    float ym = pow(y, m1);
    float numerator = c1 + c2 * ym;
    float denominator = 1.0f + c3 * ym;
    return pow(numerator / denominator, m2);
}

// -----------------------------------------------------------------------------
// ICtCp conversion.
// Reference: ITU-T T.302 (https://www.itu.int/rec/T-REC-T.302/en)
// -----------------------------------------------------------------------------
float3 rgbToICtCp(float3 rgb) // Input: linear Rec.2020
{
    float l = (rgb.r * 1688.0f + rgb.g * 2146.0f + rgb.b * 262.0f) / 4096.0f;
    float m = (rgb.r * 683.0f + rgb.g * 2951.0f + rgb.b * 462.0f) / 4096.0f;
    float s = (rgb.r * 99.0f + rgb.g * 309.0f + rgb.b * 3688.0f) / 4096.0f;

    float lPQ = inverseEotfSt2084(l);
    float mPQ = inverseEotfSt2084(m);
    float sPQ = inverseEotfSt2084(s);

    float I = (2048.0f * lPQ + 2048.0f * mPQ) / 4096.0f;
    float Ct = (6610.0f * lPQ - 13613.0f * mPQ + 7003.0f * sPQ) / 4096.0f;
    float Cp = (17933.0f * lPQ - 17390.0f * mPQ - 543.0f * sPQ) / 4096.0f;
    
    return float3(I, Ct, Cp);
}

float3 iCtCpToRgb(float3 ictCp) // Output: linear Rec.2020
{
    float l = ictCp.x + 0.00860904f * ictCp.y + 0.11103f * ictCp.z;
    float m = ictCp.x - 0.00860904f * ictCp.y - 0.11103f * ictCp.z;
    float s = ictCp.x + 0.560031f * ictCp.y - 0.320627f * ictCp.z;

    float lLin = eotfSt2084(l);
    float mLin = eotfSt2084(m);
    float sLin = eotfSt2084(s);

    float r = max(0.0f, 3.43661f * lLin - 2.50645f * mLin + 0.0698454f * sLin);
    float g = max(0.0f, -0.79133f * lLin + 1.9836f * mLin - 0.192271f * sLin);
    float b = max(0.0f, -0.0259499f * lLin - 0.0989137f * mLin + 1.12486f * sLin);

    return float3(r, g, b);
}

// -----------------------------------------------------------------------------
// Jzazbz conversion.
// Reference:
// Muhammad Safdar, Guihua Cui, Youn Jin Kim, and Ming Ronnier Luo,
// "Perceptually uniform color space for image signals including high dynamic
// range and wide gamut," Opt. Express 25, 15131-15151 (2017)
// Note: Coefficients adjusted for linear Rec.2020
// -----------------------------------------------------------------------------
static const float JZAZBZ_EXPONENT_SCALE_FACTOR = 1.7f;

float3 rgbToJzazbz(float3 rgb) // Input: linear Rec.2020
{
    float l = rgb.r * 0.530004f + rgb.g * 0.355704f + rgb.b * 0.086090f;
    float m = rgb.r * 0.289388f + rgb.g * 0.525395f + rgb.b * 0.157481f;
    float s = rgb.r * 0.091098f + rgb.g * 0.147588f + rgb.b * 0.734234f;

    float lPQ = inverseEotfSt2084(l, JZAZBZ_EXPONENT_SCALE_FACTOR);
    float mPQ = inverseEotfSt2084(m, JZAZBZ_EXPONENT_SCALE_FACTOR);
    float sPQ = inverseEotfSt2084(s, JZAZBZ_EXPONENT_SCALE_FACTOR);

    float iz = 0.5f * lPQ + 0.5f * mPQ;

    float jz = (0.44f * iz) / (1.0f - 0.56f * iz) - 1.6295499532821566e-11f;
    float az = 3.524000f * lPQ - 4.066708f * mPQ + 0.542708f * sPQ;
    float bz = 0.199076f * lPQ + 1.096799f * mPQ - 1.295875f * sPQ;
    
    return float3(jz, az, bz);
}

float3 jzazbzToRgb(float3 jab) // Output: linear Rec.2020
{
    float jz = jab.x + 1.6295499532821566e-11f;
    float iz = jz / (0.44f + 0.56f * jz);
    float a  = jab.y;
    float b  = jab.z;

    float l = iz + a * 1.386050432715393e-1f + b * 5.804731615611869e-2f;
    float m = iz - a * 1.386050432715393e-1f - b * 5.804731615611869e-2f;
    float s = iz - a * 9.601924202631895e-2f - b * 8.118918960560390e-1f;

    float lLin = eotfSt2084(l, JZAZBZ_EXPONENT_SCALE_FACTOR);
    float mLin = eotfSt2084(m, JZAZBZ_EXPONENT_SCALE_FACTOR);
    float sLin = eotfSt2084(s, JZAZBZ_EXPONENT_SCALE_FACTOR);

    float r = lLin * 2.990669f + mLin * -2.049742f + sLin * 0.088977f;
    float g = lLin * -1.634525f + mLin * 3.145627f + sLin * -0.483037f;
    float b_ = lLin * -0.042505f + mLin * -0.377983f + sLin * 1.448019f;
    
    return float3(r, g, b_);
}

// -----------------------------------------------------------------------------
// Unified color space (UCS): ICtCp or Jzazbz.
// -----------------------------------------------------------------------------
#if TONE_MAPPING_UCS == TONE_MAPPING_UCS_ICTCP
float3 rgbToUcs(float3 rgb) { return rgbToICtCp(rgb); }
float3 ucsToRgb(float3 ucs) { return iCtCpToRgb(ucs); }
#elif TONE_MAPPING_UCS == TONE_MAPPING_UCS_JZAZBZ
float3 rgbToUcs(float3 rgb) { return rgbToJzazbz(rgb); }
float3 ucsToRgb(float3 ucs) { return jzazbzToRgb(ucs); }
#else
#error "Unsupported TONE_MAPPING_UCS value. Please define TONE_MAPPING_UCS as either TONE_MAPPING_UCS_ICTCP or TONE_MAPPING_UCS_JZAZBZ."
#endif

// -----------------------------------------------------------------------------
// GT7 Tone Mapping struct and functions.
// -----------------------------------------------------------------------------

// Initializes the tone mapping curve and related parameters based on the target display luminance.
// This method should not be called directly. Use initializeAsHDR() or initializeAsSDR() instead.
void InitializeParameters(inout GT7ToneMapping tm, float physicalTargetLuminance)
{
    tm.framebufferLuminanceTarget_ = physicalValueToFrameBufferValue(physicalTargetLuminance);
    InitializeCurve(tm.curve_, tm.framebufferLuminanceTarget_, 0.25f, 0.538f, 0.444f, 1.280f);
    tm.blendRatio_ = 0.6f;
    tm.fadeStart_  = 0.98f;
    tm.fadeEnd_    = 1.16f;

    float3 ucs = rgbToUcs(float3(tm.framebufferLuminanceTarget_, tm.framebufferLuminanceTarget_, tm.framebufferLuminanceTarget_));
    tm.framebufferLuminanceTargetUcs_ = ucs.x; // Use the first UCS component (I or Jz) as luminance
}

// Initialize for HDR (High Dynamic Range) display.
// Input: target display peak luminance in nits (range: 250 to 10,000)
// Note: The lower limit is 250 because the parameters for GTToneMappingCurveV2
//       were determined based on an SDR paper white assumption of 250 nits (GRAN_TURISMO_SDR_PAPER_WHITE).
void InitializeAsHDR(inout GT7ToneMapping tm, float physicalTargetLuminance)
{
    tm.sdrCorrectionFactor_ = 1.0f;
    InitializeParameters(tm, physicalTargetLuminance);
}

// Initialize for SDR (Standard Dynamic Range) display.
void InitializeAsSDR(inout GT7ToneMapping tm)
{
    // Regarding SDR output:
    // First, in GT (Gran Turismo), it is assumed that a maximum value of 1.0 in SDR output
    // corresponds to GRAN_TURISMO_SDR_PAPER_WHITE (typically 250 nits).
    // Therefore, tone mapping for SDR output is performed based on GRAN_TURISMO_SDR_PAPER_WHITE.
    // However, in the sRGB standard, 1.0f corresponds to 100 nits,
    // so we need to "undo" the tone-mapped values accordingly.
    // To match the sRGB range, the tone-mapped values are scaled using sdrCorrectionFactor_.
    //
    // * These adjustments ensure that the visual appearance (in terms of brightness)
    //   stays generally consistent across both HDR and SDR outputs for the same rendered content.
    tm.sdrCorrectionFactor_ = 1.0f / physicalValueToFrameBufferValue(GRAN_TURISMO_SDR_PAPER_WHITE);
    InitializeParameters(tm, GRAN_TURISMO_SDR_PAPER_WHITE);
}

// Applies the GT7 tonemapping curve.
// Input:  linear Rec.2020 RGB (frame buffer values)
// Output: tone-mapped RGB (frame buffer values);
//         - in SDR mode: mapped to [0, 1], ready for sRGB OETF
//         - in HDR mode: mapped to [0, framebufferLuminanceTarget_], ready for PQ inverse-EOTF
// Note: framebufferLuminanceTarget_ represents the display's target peak luminance converted to a frame buffer value.
//       The returned values are suitable for applying the appropriate OETF to generate final output signal.
float3 ApplyToneMapping(in GT7ToneMapping tm, float3 rgb)
{
    // Convert to UCS to separate luminance and chroma.
    float3 ucs = rgbToUcs(rgb);

    // Per-channel tone mapping ("skewed" color).
    float3 skewedRgb = float3(EvaluateCurve(tm.curve_, rgb.r),
                              EvaluateCurve(tm.curve_, rgb.g),
                              EvaluateCurve(tm.curve_, rgb.b));

    float3 skewedUcs = rgbToUcs(skewedRgb);

    float chromaScale = chromaCurve(ucs.x / tm.framebufferLuminanceTargetUcs_, tm.fadeStart_, tm.fadeEnd_);

    float3 scaledUcs = float3(skewedUcs.x, ucs.y * chromaScale, ucs.z * chromaScale);

    // Convert back to RGB.
    float3 scaledRgb = ucsToRgb(scaledUcs);

    // Final blend between per-channel and UCS-scaled results.
    float3 blended = lerp(skewedRgb, scaledRgb, tm.blendRatio_);
    
    // When using SDR, apply the correction factor.
    // When using HDR, sdrCorrectionFactor_ is 1.0f, so it has no effect.
    float3 out_rgb = tm.sdrCorrectionFactor_ * min(blended, tm.framebufferLuminanceTarget_);
    
    return out_rgb;
}

// Helper functions for Custom Tonemap. 
static const float3x3 LINEAR_REC2020_TO_LINEAR_SRGB = transpose(float3x3(
    float3(1.6605, -0.1246, -0.0182), 
    float3(-0.5876, 1.1329, -0.1006), 
    float3(-0.0728, -0.0083, 1.1187))
);
static const float3x3 LINEAR_SRGB_TO_LINEAR_REC2020 = transpose(float3x3(
    float3(0.6274, 0.0691, 0.0164), 
    float3(0.3293, 0.9195, 0.088), 
    float3(0.0433, 0.0113, 0.8956))
);

float3 ApplyToneMapping(float3 rgb)
{
    rgb = mul(LINEAR_SRGB_TO_LINEAR_REC2020, rgb);

    GT7ToneMapping tm = (GT7ToneMapping) 0;
    InitializeAsSDR(tm);
    rgb = ApplyToneMapping(tm, rgb);
    
    rgb = mul(LINEAR_REC2020_TO_LINEAR_SRGB, rgb);
    return rgb;
}

};