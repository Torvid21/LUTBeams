
using UdonSharp;
using UnityEngine;
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
    public VRCUrlInputField inputField;
    BaseVRCVideoPlayer player;

    public VRCAVProVideoPlayer proVideoPlayer;
    public bool Sycned = false;
    public bool Autoplay = false;

    public AudioSource audioSource;

    public void Start()
    {
#if UNITY_EDITOR
        screenMaterial.SetFloat("_AVPRO", 0);
        player = unityVideoPlayer;
        unityVideoPlayer.enabled = true;
#else
        screenMaterial.SetFloat("_AVPRO", 1);
        player = proVideoPlayer;
        proVideoPlayer.enabled = true;
        //proScreen.enabled = true;
        //proSpeaker.enabled = true;
#endif

        audioSource.volume = 0.5f;

        if (Autoplay)
        {
            inputField.SetUrl(Url);
            OnURLChanged();
        }
    }
    public override void OnPlayerRespawn(VRCPlayerApi player)
    {
        if (Networking.LocalPlayer != player)
            return;
    }

    void Update()
    {
#if UNITY_EDITOR
#else
        VRCGraphics.Blit(null, Target, screenMaterial);
#endif
    }

    public VRCUnityVideoPlayer unityVideoPlayer;

    public RenderTexture Target;

    public Material screenMaterial;

    [UdonSynced, FieldChangeCallback(nameof(Url))]
    public VRCUrl url;

    [UdonSynced, FieldChangeCallback(nameof(TimeAndOffset))]
    public Vector2 timeAndOffset;

    public float syncFrequency = 15;

    // Play URL when it Changes
    public VRCUrl Url
    {
        set
        {
            if (Sycned)
                player.PlayURL(value);
            url = value;
        }
        get
        {
            return url;
        }
    }
    // Play URL when it Changes
    public Vector2 TimeAndOffset
    {
        set
        {
            if (!Networking.IsOwner(this.gameObject))
            {
                Resync();
                //SendCustomEvent(nameof(Resync));
            }
            timeAndOffset = value;
        }
        get
        {
            return timeAndOffset;
        }
    }


    // When URL Field Changed, Become Owner and update synced URL
    public void OnURLChanged()
    {
        if (!Sycned)
        {
            player.PlayURL(inputField.GetUrl());
            return;
        }

        Debug.Log("OnURLChanged");
        Networking.SetOwner(Networking.LocalPlayer, this.gameObject);
        Url = inputField.GetUrl();
        RequestSerialization();
    }

    // On Video Start, Update offset on Onwer, Resync on Others.
    public override void OnVideoStart()
    {
        UpdateTimeAndOffset();
        //SendCustomEvent(nameof(UpdateTimeAndOffset));
    }

    public void UpdateTimeAndOffset()
    {
        if (!Sycned)
            return;

        if (Networking.IsOwner(this.gameObject))
        {
            TimeAndOffset = new Vector2(player.GetTime(), (float)Networking.GetServerTimeInSeconds());
            RequestSerialization();

            if (syncFrequency > 0)
            {
                SendCustomEventDelayedSeconds(nameof(UpdateTimeAndOffset), syncFrequency);
            }
        }
        else
        {
            Resync();
        }
    }

    public void Resync()
    {
        if (!Sycned)
            return;

        player.SetTime(TimeAndOffset.x + ((float)Networking.GetServerTimeInSeconds() - TimeAndOffset.y));
    }
}
