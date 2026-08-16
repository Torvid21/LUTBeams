using System.Collections;
using System.Collections.Generic;
using UnityEngine;
#if UNITY_EDITOR
using UnityEditor;
#endif

// Written by torvid for Furality.

namespace Furality
{
    public class ToggleGizmos
    {
#if UNITY_EDITOR
        [MenuItem("Furality/Misc/Toggle Gizmos _g")]
        static void Execute()
        {
            SceneView view = SceneView.lastActiveSceneView;
            if (!view)
                return;
            view.drawGizmos = !view.drawGizmos;
        }
#endif
    }

}