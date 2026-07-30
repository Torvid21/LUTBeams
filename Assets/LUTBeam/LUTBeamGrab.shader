Shader "LUTBeam/Grab"
{
    SubShader
    {
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
