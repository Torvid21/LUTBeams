
using UdonSharp;
using UnityEngine;
using UnityEngine.UI;
using VRC.SDKBase;
using VRC.Udon;

public class DemoSceneSettings : UdonSharpBehaviour
{
    public Material focusMat;
    public Slider focus;
    public Light directionalLight;

    public void _FocusChanged()
    {
        focusMat.SetFloat("_Focus", focus.value);
    }

    public void _ToggleShadows()
    {
        if (directionalLight.shadows == LightShadows.None)
            directionalLight.shadows = LightShadows.Soft;
        else
            directionalLight.shadows = LightShadows.None;
    }
}
