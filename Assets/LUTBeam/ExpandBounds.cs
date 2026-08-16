using UdonSharp;
using UnityEngine;

[UdonBehaviourSyncMode(BehaviourSyncMode.None)]
public class ExpandBounds : UdonSharpBehaviour
{
    public float expandSize = 10.0f;

    void Start()
    {
        MeshRenderer meshRenderer = GetComponent<MeshRenderer>();
        meshRenderer.ResetBounds();
        meshRenderer.localBounds = new Bounds(Vector3.zero, Vector3.one * expandSize);
    }
}
