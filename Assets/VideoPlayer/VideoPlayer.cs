
using UdonSharp;
using UnityEngine;
using UnityEngine.UI;
using VRC.SDK3.Components;
using VRC.SDK3.Video.Components;
using VRC.SDK3.Video.Components.AVPro;
using VRC.SDK3.Video.Components.Base;
using VRC.SDKBase;
using VRC.Udon;

// Minimal video player, CC0 / MIT

[UdonBehaviourSyncMode(BehaviourSyncMode.Manual)]
public class VideoPlayer : UdonSharpBehaviour
{
    [Header("Settings")]
    public VRCUrl AutoplayUrl;
    public RenderTexture Target;

    [Header("Misc")]
    public VRCUrlInputField inputField;
    BaseVRCVideoPlayer videoPlayer;
    public VRCAVProVideoPlayer proVideoPlayer;
    public VRCUnityVideoPlayer unityVideoPlayer;
    public AudioSource audioSource;
    public Material screenMaterial;
    public Material clearMaterial;
    public Text debugText;
    public Slider slider;
    float sliderValue = 0;

    [UdonSynced]
    public VRCUrl url;
    public VRCUrl urlPrev = null;

    [UdonSynced]
    public Vector2 timeAndOffset;
    public Vector2 timeAndOffsetPrev;

    public float syncFrequency = 1;

    public void Start()
    {
#if UNITY_EDITOR
        screenMaterial.SetFloat("_AVPRO", 0);
        videoPlayer = unityVideoPlayer;
        unityVideoPlayer.enabled = true;
#else
        screenMaterial.SetFloat("_AVPRO", 1);
        videoPlayer = proVideoPlayer;
        proVideoPlayer.enabled = true;
        //proScreen.enabled = true;
        //proSpeaker.enabled = true;
#endif

        audioSource.volume = 0.5f;
        VRCGraphics.Blit(Texture2D.blackTexture, Target, clearMaterial);
    }

    public override void OnPlayerJoined(VRCPlayerApi player)
    {
        if (player != Networking.LocalPlayer)
            return;

        // If we join and are the owner, play it!
        if (Networking.IsOwner(this.gameObject))
        {
            if (AutoplayUrl != null)
            {
                Debug.Log("_URLFieldChanged");
                url = AutoplayUrl;
                RequestSerialization();
                OnDeserialization();
            }
        }

        _SlowUpdate();
    }

    string UrlToString(VRCUrl url)
    {
        if (url == null)
            return "";
        return url.Get();
    }

    public override void OnDeserialization()
    {
        Debug.Log("OnDeserialization");
        base.OnDeserialization();

        // If the URL changed, play that URL
        if (UrlToString(url) != UrlToString(urlPrev))
        {
            Debug.Log("url: " + url);
            Debug.Log("urlPrev: " + urlPrev);
            urlPrev = url;
            if (url == null)
                videoPlayer.Stop();
            else
                videoPlayer.PlayURL(url);

            VRCGraphics.Blit(Texture2D.blackTexture, Target, clearMaterial);
        }

        // If we are not the owner, and the time changed, sync
        if (!Networking.IsOwner(this.gameObject))
        {
            if (timeAndOffset != timeAndOffsetPrev)
            {
                timeAndOffsetPrev = timeAndOffset;
                Debug.Log("timeAndOffset != timeAndOffsetPrev");

                // If we are more than 2 seconds away from target time, sync!
                float targetTime = timeAndOffset.x + ((float)Networking.GetServerTimeInSeconds() - timeAndOffset.y);
                if (videoPlayer.IsPlaying && Mathf.Abs(videoPlayer.GetTime() - targetTime) > 10)
                    videoPlayer.SetTime(targetTime);
            }
        }
    }
    
    void Update()
    {
#if UNITY_EDITOR
#else
        // AVPRO sometimes inserts fully transparent frames that make the video flicker.
        // Blitting like this resolves it.
        if(videoPlayer.IsPlaying)
            VRCGraphics.Blit(null, Target, screenMaterial);
        else
            VRCGraphics.Blit(Texture2D.blackTexture, Target, clearMaterial);
#endif


        string debug = "";
        debug += "Is owner: " + Networking.IsOwner(this.gameObject) + "\n";
        debug += "GetDuration: " + videoPlayer.GetDuration() + "\n";
        debug += "GetTime: " + videoPlayer.GetTime() + "\n";
        debug += "IsPlaying: " + videoPlayer.IsPlaying + "\n";
        debug += "IsReady: " + videoPlayer.IsReady + "\n";
        debug += "time: " + timeAndOffset.x + "\n";
        debug += "offset: " + timeAndOffset.y + "\n";
        debug += "resyncPressed: " + resyncPressed + "\n";

        debugText.text = debug;
    }

    // If we are not the owner, and the video started playing, update the time.
    public override void OnVideoStart()
    {
        Debug.Log("OnVideoStart");
        if (!Networking.IsOwner(this.gameObject))
        {
            videoPlayer.SetTime(timeAndOffset.x + ((float)Networking.GetServerTimeInSeconds() - timeAndOffset.y));
        }
    }

    public void _SlowUpdate()
    {
        //Debug.Log("_SlowUpdate");
        SendCustomEventDelayedSeconds(nameof(_SlowUpdate), syncFrequency);

        if (Networking.IsOwner(this.gameObject))
        {
            if (videoPlayer.IsPlaying)
            {
                if (resyncPressed)
                {
                    resyncPressed = false;
                    videoPlayer.SetTime(timeAndOffset.x + ((float)Networking.GetServerTimeInSeconds() - timeAndOffset.y));
                }
                else
                {
                    timeAndOffset = new Vector2(videoPlayer.GetTime(), (float)Networking.GetServerTimeInSeconds());
                    RequestSerialization();
                    OnDeserialization();
                }
            }
        }

        if (slider.value != sliderValue)
        {
            sliderValue = slider.value;
            Debug.Log("_SliderChanged");
            Networking.SetOwner(Networking.LocalPlayer, this.gameObject);
            float newUserTime = slider.value * videoPlayer.GetDuration();
            videoPlayer.SetTime(newUserTime);
            RequestSerialization();
            OnDeserialization();
        }

        float newTime = 0;
        if (videoPlayer.GetDuration() > 0)
            newTime = videoPlayer.GetTime() / videoPlayer.GetDuration();

        slider.SetValueWithoutNotify(newTime);
        sliderValue = newTime;
    }

    // When URL Field Changed, Become Owner and update synced URL
    public void _URLFieldChanged()
    {
        Debug.Log("_URLFieldChanged");
        Networking.SetOwner(Networking.LocalPlayer, this.gameObject);
        url = inputField.GetUrl();
        RequestSerialization();
        OnDeserialization();
    }

    bool resyncPressed = false;
    public void _ResyncPressed()
    {
        // If we are the owner, flag that resync was pressed, so we don't throw away the time value.
        resyncPressed = false;
        if (Networking.IsOwner(this.gameObject))
            resyncPressed = true;

        Debug.Log("_ResyncPressed");
        videoPlayer.Stop();
        if(url != null)
            videoPlayer.PlayURL(url);
    }

    public void _StopPressed()
    {
        Debug.Log("_StopPressed");
        Networking.SetOwner(Networking.LocalPlayer, this.gameObject);
        url = null;
        //inputField.SetUrl(null);
        RequestSerialization();
        OnDeserialization();
    }
}
