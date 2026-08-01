// https://iolite-engine.com/blog_posts/minimal_agx_implementation
//
// MIT License
//
// Copyright (c) 2024 Missing Deadlines (Benjamin Wrensch)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// Values used to derive this implementation are sourced from Troy’s initial AgX implementation/OCIO config file available here:
//   https://github.com/sobotka/AgX

// AgX Tone Mapping implementation based on Three.js,
// which is based on Filament's, which in turn is based
// on Blender's implementation using rec 2020 primaries
// https://github.com/mrdoob/three.js/pull/27366
// https://github.com/google/filament/pull/7236
// Inputs and outputs are encoded as Linear-sRGB.

class AgxTonemapper
{
    #define FLT_EPSILON     1.192092896e-07 // Smallest positive number, such that 1.0 + FLT_EPSILON != 1.0
    #define FLT_MIN         1.175494351e-38 // Minimum representable positive floating-point number
    #define FLT_MAX         3.402823466e+38 // Maximum representable floating-point number

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

    static const float3x3 AgXInsetMatrix = transpose(float3x3(
        float3(0.85662717, 0.13731897, 0.11189821), 
        float3(0.09512124, 0.761242, 0.076799415), 
        float3(0.048251607, 0.10143904, 0.81130236)
    ));
    static const float3x3 AgXOutsetMatrix = transpose(float3x3(
        float3(1.1271006, -0.14132977, -0.14132977), 
        float3(-0.11060664, 1.1578237, -0.11060664), 
        float3(-0.016493939, -0.016493939, 1.2519364)
    ));

    // Mean error^2: 3.6705141e-06
float3 agxDefaultContrastApprox(float3 x) { 
    float3 x2 = x * x;
    float3 x4 = x2 * x2;
    float3 x6 = x4 * x2;
    return  - 17.86f    * x6 * x
            + 78.01f    * x6
            - 126.7f    * x4 * x
            + 92.06f    * x4
            - 28.72f    * x2 * x
            + 4.361f    * x2
            - 0.1718f   * x
            + 0.002857f;
    }

float3 agx(float3 val) {
        
	// LOG2_MIN      = -10.0
	// LOG2_MAX      =  +6.5
	// MIDDLE_GRAY   =  0.18
	const float AgxMinEv = - 12.47393;  // log2( pow( 2, LOG2_MIN ) * MIDDLE_GRAY )
	const float AgxMaxEv = 4.026069;    // log2( pow( 2, LOG2_MAX ) * MIDDLE_GRAY )

    // Input transform (inset);
    val = mul(LINEAR_SRGB_TO_LINEAR_REC2020, val);
    val = mul(AgXInsetMatrix, val);
    
    // Log2 space encoding
    val = max(val, 1e-10); // avoid 0 or negative numbers for log2
    val = log2(val);
	val = ( val - AgxMinEv ) / ( AgxMaxEv - AgxMinEv );

    val = saturate(val);
    
    // Apply sigmoid function approximation
    val = agxDefaultContrastApprox(val);

    return val;
}

float3 agxEotf(float3 val) {
        
    // Inverse input transform (outset)
    val = mul(AgXOutsetMatrix, val);
    
    // sRGB IEC 61966-2-1 2.2 Exponent Reference EOTF Display
    // NOTE: We're linearizing the output here. Comment/adjust when
    // *not* using a sRGB render target
    val = max(val, 0); 
    val = pow(val, 2.2);
    val = mul(LINEAR_REC2020_TO_LINEAR_SRGB, val);

    return val;
}

float3 agxLook(float3 val) {
        const float3 lw = float3(0.2126, 0.7152, 0.0722);
        float luma = dot(val, lw);
        
        float3 offset = (0.0);
        float3 slope =  (1.0);
        float3 power =  (1.0);
        float sat = 1.0;
        
        switch(_AgX_Look)
        {
        case 99: // Custom
        {
            offset = _AgX_Offset;
            slope = _AgX_Slope;
            power = _AgX_Power;
            sat = _AgX_Sat;
            break;
        }
        
        case 1: // Golden
        {
            slope = float3(1.0, 0.9, 0.5);
            power = (0.8);
            sat = 0.8;
            break;
        }
        
        case 2: // Punchy
        {
            slope = (1.0);
            power = float3(1.35, 1.35, 1.35);
            sat = 1.4;
            break;
        }
        }
        
        // ASC CDL
        val = pow(val * slope + offset, power);
        return luma + sat * (val - luma);
}
};