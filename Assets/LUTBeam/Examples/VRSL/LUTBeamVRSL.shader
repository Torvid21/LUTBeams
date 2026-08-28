Shader "LUTBeam/VRSL"
{
    Properties
    {
        [NoScaleOffset] _GoboTex ("Gobo Texture", 2DArray) = "white" {}
        [NoScaleOffset] _GoboLUT ("LUT Texture", 2DArray) = "white" {}

        [Header(Shape)]
        _ZoomX ("_ZoomX", Range(0, 2.0)) = 0.1
        _ZoomY ("_ZoomY", Range(0, 2.0)) = 0.1
        _NearSizeX ("_NearSizeX", Range(0,1)) = 0.1
        _NearSizeY ("_NearSizeY", Range(0,1)) = 0.1
        _FarZ ("_FarZ", Float) = 25
        _Gobo ("Gobo Index", Integer) = 0
        _SpinSpeed ("_SpinSpeed", Float) = 0.1
        
        [Header(Color)]
        _Color ("Color", Color) = (1, 1, 1, 1)
        _BeamIntensity ("_BeamIntensity", Range(0, 8.0)) = 1
        _BeamFalloff ("_BeamFalloff", Range(0, 3.0)) = 1
        _GoboIntensity ("_GoboIntensity", Range(0, 8.0)) = 1
    }
    SubShader
    {
        Tags {"RenderType"="Transparent" "Queue"="Transparent+303" }

        LOD 100

        Cull Back
        ZTest LEqual
        ZWrite Off

        Pass
        {
            Name "LUTBeam"
            Blend One One
            CGPROGRAM
            
            #pragma multi_compile_instancing

            #include "UnityCG.cginc"

            Texture2DArray _GoboTex;
            Texture2DArray _GoboLUT;
            float _ZoomX;
            float _ZoomY;
            float _NearSizeX;
            float _NearSizeY;
            float _Gobo;
            float4 _Color;
            float _GoboIntensity;
            float _BeamIntensity;
            float _BeamFalloff;

            //default definitions, at -1 to indicate disabled
            #ifndef DMX_PAN
            #define DMX_PAN -1
            #endif
            #ifndef DMX_PAN_VALUE
            #define DMX_PAN_VALUE 255. / 2. //midway value
            #endif
            #ifndef DMX_TILT
            #define DMX_TILT -1
            #endif
            #ifndef DMX_TILT_VALUE
            #define DMX_TILT_VALUE 255. / 2. //midway value
            #endif
            #ifndef DMX_ZOOM
            #define DMX_ZOOM -1
            #endif
            #ifndef DMX_ZOOM_VALUE
            #define DMX_ZOOM_VALUE 1
            #endif
            #ifndef DMX_DIMMER
            #define DMX_DIMMER -1
            #endif
            #ifndef DMX_DIMMER_VALUE
            #define DMX_DIMMER_VALUE 1 //full brightness
            #endif
            #ifndef DMX_STROBE
            #define DMX_STROBE -1
            #endif
            #ifndef DMX_COLOR
            #define DMX_COLOR -1
            #endif
            #ifndef DMX_COLOR_VALUE
            #define DMX_COLOR_VALUE float3(1,1,1) //white
            #endif
            #ifndef DMX_GOBOSPIN
            #define DMX_GOBOSPIN -1
            #endif
            #ifndef DMX_GOBO
            #define DMX_GOBO -1
            #endif
            #ifndef DMX_GOBO_VALUE
            #define DMX_GOBO_VALUE 0 //first gobo
            #endif
            
            UNITY_INSTANCING_BUFFER_START(Props)
                UNITY_DEFINE_INSTANCED_PROP(float, _NearRadius)
                UNITY_DEFINE_INSTANCED_PROP(float, _Offset)
                UNITY_DEFINE_INSTANCED_PROP(float, _FarZ)
                UNITY_DEFINE_INSTANCED_PROP(float, _FarZMaxZoom)

                UNITY_DEFINE_INSTANCED_PROP(float, _BrightnessGoboZoomMin)
                UNITY_DEFINE_INSTANCED_PROP(float, _BrightnessGoboZoomMax)
                UNITY_DEFINE_INSTANCED_PROP(float, _BrightnessVolumeZoomMin)
                UNITY_DEFINE_INSTANCED_PROP(float, _BrightnessVolumeZoomMax)

                UNITY_DEFINE_INSTANCED_PROP(float, _TiltOffset)
                UNITY_DEFINE_INSTANCED_PROP(float, _PanOffset)
                UNITY_DEFINE_INSTANCED_PROP(float, _LightEmission)

                UNITY_DEFINE_INSTANCED_PROP(float, _AngleMin)
                UNITY_DEFINE_INSTANCED_PROP(float, _AngleMax)

                //VRSL stuff
                UNITY_DEFINE_INSTANCED_PROP(uint, _DMXChannel)
                UNITY_DEFINE_INSTANCED_PROP(uint, _FixtureRotationX)
                UNITY_DEFINE_INSTANCED_PROP(uint, _FixtureBaseRotationY)
                UNITY_DEFINE_INSTANCED_PROP(uint, _PanInvert)
                UNITY_DEFINE_INSTANCED_PROP(uint, _TiltInvert)
                UNITY_DEFINE_INSTANCED_PROP(half, _UniversalIntensity)
                UNITY_DEFINE_INSTANCED_PROP(half, _MaxMinPanAngle)
                UNITY_DEFINE_INSTANCED_PROP(half, _MaxMinTiltAngle)
                UNITY_DEFINE_INSTANCED_PROP(float, _HorizontalWidth)
                UNITY_DEFINE_INSTANCED_PROP(float, _VerticalWidth)
            UNITY_INSTANCING_BUFFER_END(Props)
                
            #define LUTBEAM_CALLBACK_PROJECTION LUTBeamCallbackProjection
            float3 LUTBeamCallbackProjection(SamplerState samp, float2 uv, float mip)
            {
                return _GoboTex.SampleLevel(samp, float3(uv, _Gobo), mip).rrr;
            }

            #define LUTBEAM_CALLBACK_VOLUME LUTBeamCallbackVolume
            float3 LUTBeamCallbackVolume(SamplerState samp, float2 uv, float mip)
            {
                return _GoboLUT.SampleLevel(samp, float3(uv, _Gobo), mip).rrr;
            }
            
            // VRSL STUB
            float GetDMXChannel() {return 0;}
            float GetDMXChannel(float a) {return 0;}
            float GetDMXChannel(float a, float b) {return 0;}
            float GetFineCombo(float a) {return 0;}
            float3 GetDMXColor(float a) {return 0;}
            float _Udon_DMXGridSpinTimer;
            #define IF(a,b,c) a
            float ReadDMX() {return 0;}
            float ReadDMX(float a) {return 0;}
            float ReadDMX(float a, float b) {return 0;}
            float GetStrobeOutput(float a) {return 0;}
            bool isDMX() {return true;}
            float getBaseEmission() {return 0;}
            float getGlobalIntensity() {return 0;}
            float getFinalIntensity() {return 0;}
            float _Udon_DMXGridRenderTexture;
            float getDMXConeWidth(float a) {return 0;}

            #define LUTBEAM_CALLBACK_VERTEX LUTBeamCallbackTransform
            float3 LUTBeamCallbackTransform(float3 vertex)
            {
                float channel = UNITY_ACCESS_INSTANCED_PROP(Props, _DMXChannel);

                float3x3 rotation_matrix = float3x3(
                    1,0,0,
                    0,1,0,
                    0,0,1
                );

                float goboSpin = IF(DMX_GOBOSPIN == -1,
                    0,
                    GetDMXChannel(channel + DMX_GOBOSPIN, _Udon_DMXGridSpinTimer));
                float pan = IF(
                    DMX_PAN == -1,
                    DMX_PAN_VALUE,
                    GetFineCombo(channel + DMX_PAN));
                float tilt = IF(
                    DMX_TILT == -1,
                    DMX_TILT_VALUE,
                    1 - GetFineCombo(channel + DMX_TILT));
                float tiltMin = UNITY_ACCESS_INSTANCED_PROP(Props, _MaxMinTiltAngle);
                float tiltMax = -UNITY_ACCESS_INSTANCED_PROP(Props, _MaxMinTiltAngle);
                float tiltOffset = UNITY_ACCESS_INSTANCED_PROP(Props, _FixtureRotationX) - 90.0;

                float panMin = -UNITY_ACCESS_INSTANCED_PROP(Props, _MaxMinPanAngle);
                float panMax = UNITY_ACCESS_INSTANCED_PROP(Props, _MaxMinPanAngle);
                float panOffset = UNITY_ACCESS_INSTANCED_PROP(Props, _FixtureBaseRotationY);

                tilt = radians(lerp(tiltMin, tiltMax, tilt) + tiltOffset);
                pan = -radians(lerp(panMin, panMax, pan) + panOffset);

                if (UNITY_ACCESS_INSTANCED_PROP(Props, _TiltInvert) == 1) {
                    tilt = -tilt;
                }

                if (UNITY_ACCESS_INSTANCED_PROP(Props, _PanInvert) == 0) {
                    pan = -pan;
                }

                float3x3 spinMatrix = {
                    cos(goboSpin), -sin(goboSpin), 0,
                    sin(goboSpin),  cos(goboSpin), 0,
                    0,              0,             1
                };
                float3x3 tiltMatrix = {
                    1, 0, 0,
                    0, cos(tilt), -sin(tilt),
                    0, sin(tilt),  cos(tilt)
                };
                float3x3 panMatrix = {
                    cos(pan), -sin(pan), 0,
                    sin(pan),  cos(pan), 0,
                    0,              0,             1
                };

                rotation_matrix = mul(rotation_matrix, panMatrix);
                rotation_matrix = mul(rotation_matrix, tiltMatrix);
                rotation_matrix = mul(rotation_matrix, spinMatrix);
                
                vertex = mul(vertex, rotation_matrix);

                // for offsets in the fixture shader
                #ifdef POSITION_OFFSET
                vertex += POSITION_OFFSET;
                #endif

                return vertex;
            }

            #include "Assets/LUTBeam/LUTBeam.cginc"
        
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 5.0

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                BeamData beam;

                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            v2f vert(appdata v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                //Use this for Avatar Shaders
                //int dmx = ConvertToRawDMXChannel(_Channel, _Universe);

                //Use this for World Shaders
                int dmx = GetDMXChannel();

                float intensity = ReadDMX(dmx, _Udon_DMXGridRenderTexture); // 0-1 output

                //this is the same as 3 ReadDMX() calls mapped to a float3 with 1 in the alpha channel
                float3 color = GetDMXColor(dmx+1); 
               
                // a special function for getting strobe output, which is a square wave from 0-1
                float strobe = GetStrobeOutput(dmx + 4); 
                
                //combine them together
                float3 finalColor = (intensity * color) * strobe;
                
                //check to see if dmx capabilities are enabled, if not, output this base emission color.
                finalColor = isDMX() ? finalColor : getBaseEmission();

                //Use the global and final intensity values to control the final strength of the color with udon
                //good for world shaders that want to be controlled by udon-based sliders.
                finalColor *= getGlobalIntensity() * getFinalIntensity();

                float zoomFade = lerp(1, 0.1, saturate((_ZoomX+_ZoomY)*0.25));
                
		        half oscConeWidth = getDMXConeWidth(dmx);

                BeamSettings settings = DefaultBeamSettings();
                settings.zoomX = _ZoomX*oscConeWidth;
                settings.zoomY = _ZoomY*oscConeWidth;
                settings.farz = _FarZ;
                settings.nearSizeX = _NearSizeX;
                settings.nearSizeY = _NearSizeY;
                settings.offset = _Offset;
                settings.color = _Color * finalColor;
                settings.brightnessVolume = _BeamIntensity;
                settings.brightnessGobo = _GoboIntensity;
                settings.beamFalloff = _BeamFalloff;

                o.beam = LUTBeamVert(v.vertex, settings);

                return o;
            }


            float4 frag(v2f i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                
                float3 col = LUTBeamFrag(i.beam);
                return float4(col, 0);
            }
            ENDCG
        }
    }
}
