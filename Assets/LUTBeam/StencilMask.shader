Shader "Unlit/StencilMask"
{
    Properties
    {
        [Header(Stencil)]
        [IntRange] _StencilRef ("Ref", Range(0, 255)) = 142
        [IntRange] _StencilReadMask ("Read Mask", Range(0, 255)) = 255
        [IntRange] _StencilWriteMask ("Write Mask", Range(0, 255)) = 255
        [Enum(UnityEngine.Rendering.CompareFunction)] _StencilCompareFunction ("Compare Function", Float) = 8
        [Enum(UnityEngine.Rendering.StencilOp)] _StencilPassOp ("Pass Op", Float) = 2
        [Enum(UnityEngine.Rendering.StencilOp)] _StencilFailOp ("Fail Op", Float) = 0
        [Enum(UnityEngine.Rendering.StencilOp)] _StencilZFailOp ("ZFail Op", Float) = 0
    }
    SubShader
    {
        Tags {"RenderType"="Transparent" "Queue"="Transparent+302" }
        Pass
        {

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

            Cull Back
            ZTest LEqual
            ZWrite Off
            ColorMask 0
            
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            float4 vert(float4 v : POSITION) : SV_POSITION
            {
                return UnityObjectToClipPos(v);
            }

            fixed4 frag() : SV_Target
            {
                return 0.01;
            }
            ENDCG
        }
    }
}
