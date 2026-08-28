// I dedicate this work to the public domain. Do as you will.
// Initial implementation by Torvid
// Optimizations by ValueFactory
// Tweaks and MDMX integration by Micca

Shader "MDMX/LUTBeam Experimental SinglePass Decal"
{
    Properties
    {
        _GoboTex ("Gobo Array", 2DArray) = "white" {}
        _GoboLUT ("LUT Array", 2DArray) = "white" {}
        _GoboSmall ("small Array", 2DArray) = "white" {}
        _GoboTex15 ("Gobo 15 Input", 2D) = "white" {}
        _GoboLUT15 ("LUT 15 Input", 2D) = "white" {}
        _GoboSmall15 ("small 15 Input", 2D) = "white" {}

        _Angle ("_Angle", Float) = 1
        _Offset ("_Offset", Float) = 0.25
        _NearRadius ("_NearRadius", Float) = 10
        _FarZ ("_FarZ", Float) = 10
        _FarZMaxZoom ("_FarZMaxZoom", Float) = 10

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
        Cull Front
        ZTest Off
        ZWrite Off

        Pass
        {
            Name "LUTBeam Experimental SinglePass Decal"

            Blend DstColor One

            CGPROGRAM

            #define DECAL_PASS
            #define SHOW_WHEN_INSIDE
            #define SHOW_WHEN_OUTSIDE

            #pragma multi_compile_instancing
            #include "UnityCG.cginc"
            #include "LUTBeam.cginc"

            #pragma vertex vert
            #pragma fragment frag
            #pragma target 5.0

            ENDCG
        }
    }
}
