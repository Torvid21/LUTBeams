Shader "LUTBeam/Grab"
{
    SubShader
    {
        Tags {"RenderType"="Transparent" "Queue"="Transparent+300" }

        GrabPass
        {
            "_GrabTexture"
        }

        Pass
        {
            COLORMASK 0
		    ZWrite Off
        }
    }
}
