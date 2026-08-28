#if UNITY_EDITOR 
using System.Collections;
using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEditor.Build;
using UnityEngine;
using UnityEngine.SceneManagement;

public class LUTBeamMaterialManager : MonoBehaviour
{

    public Texture[] gobos;
    public Material[] materials;

    public Texture videoGobo;
    //TODO: Make this a fixture so these CRTs can be made to only update when needed!
    public CustomRenderTexture videoLUT;
    public CustomRenderTexture videoLUTSmall;

    Texture2D Compute(Texture Gobo, Material material, int sizeX, int sizeY, bool small)
    {
        RenderTexture tempRT = new RenderTexture(sizeX, sizeY, 32, RenderTextureFormat.ARGBFloat);

        material.SetTexture("_MainTex", Gobo);
        material.SetFloat("_Small", small ? 1 : 0);
        
        Graphics.Blit(null, tempRT, material);

        RenderTexture.active = tempRT;
        Texture2D tex = new Texture2D(sizeX, sizeY, TextureFormat.RGBAFloat, false);
        tex.ReadPixels(new Rect(0, 0, sizeX, sizeY), 0, 0);
        tex.Apply();
        RenderTexture.active = null;

        //convert linear to srgb in the texture
        for (int x = 0; x < sizeX; x++)
        {
            for (int y = 0; y < sizeY; y++)
            {
                Color c = tex.GetPixel(x, y);
                c.r = Mathf.LinearToGammaSpace(c.r);
                c.g = Mathf.LinearToGammaSpace(c.g);
                c.b = Mathf.LinearToGammaSpace(c.b);
                tex.SetPixel(x, y, c);
            }
        }
        tex.Apply();

        return tex;
    }

    public void _GenerateMaterials() {
        Texture2D[] goboTextures = new Texture2D[gobos.Length];
        Texture2D[] lutTextures = new Texture2D[gobos.Length];
        Texture2D[] smallTextures = new Texture2D[gobos.Length];

        // Path to the LUT Generator CRT.
        var path = AssetDatabase.GUIDToAssetPath("b959e6e2642a26549a398a4a7995e953");
        string dir = Path.GetDirectoryName(path);

        // make a copy so the thing in the project doesn't ged edited!
        Material material = new Material(AssetDatabase.LoadAssetAtPath<Shader>(path));

        //use step quality of 100 (TODO: What if we made this even higher for the baked ones? thoughts?) -Happyrobot33
        //100 is ~probably~ more than fine with the resolution of the gobo, but not a huge deal if we wanted to make it bigger I suppose -Micca
        material.SetFloat("_StepCount", 100);

        for (int q = 0; q < gobos.Length; q++)
        {
            if (!(gobos[q] is Texture2D))
                continue;

            Texture2D Gobo = gobos[q] as Texture2D;

            if (!Gobo)
                return;

            Texture2D tex = Compute(Gobo, material, 1024, 1024, false);
            Texture2D smallTex = Compute(Gobo, material, 1024, 32, true);

            goboTextures[q] = Gobo;
            lutTextures[q] = tex;
            smallTextures[q] = smallTex;
        }

        Texture2DArray texArray = new Texture2DArray(1024, 1024, gobos.Length, TextureFormat.BC4, false, false);
        Texture2DArray lutArray = new Texture2DArray(1024, 1024, gobos.Length, TextureFormat.BC4, false, false);
        //Texture2DArray smallArray = new Texture2DArray(1024, 32, gobos.Length, TextureFormat.BC4, false, false);

        for (int i = 0; i < gobos.Length; i++) {
            //if (i < goboTextures.Length && goboTextures[i] != null && lutTextures[i] != null) {

                RenderTexture goboTempRT = new RenderTexture(1024,1024,0,RenderTextureFormat.ARGBFloat);
                Texture2D goboTex = new Texture2D(1024, 1024, TextureFormat.RGBA32, false, false);
                Graphics.Blit(goboTextures[i], goboTempRT);
                goboTex.ReadPixels(new Rect(0, 0, 1024, 1024), 0, 0);
                goboTex.Apply();
                EditorUtility.CompressTexture(goboTex, TextureFormat.BC4, TextureCompressionQuality.Best);
                Graphics.CopyTexture(goboTex, 0, texArray, i);

                RenderTexture lutTempRT = new RenderTexture(1024, 1024, 0, RenderTextureFormat.ARGBFloat);
                Texture2D lutTex = new Texture2D(1024, 1024, TextureFormat.RGBA32, false, false);
                Graphics.Blit(lutTextures[i], lutTempRT);
                lutTex.ReadPixels(new Rect(0, 0, 1024, 1024), 0, 0);
                lutTex.Apply();
                EditorUtility.CompressTexture(lutTex, TextureFormat.BC4, TextureCompressionQuality.Best);
                Graphics.CopyTexture(lutTex, 0, lutArray, i);

                // RenderTexture smallTempRT = new RenderTexture(1024, 32, 0, RenderTextureFormat.ARGBFloat);
                // Texture2D smallTex = new Texture2D(1024, 32, TextureFormat.RGBA32, false, false);
                // Graphics.Blit(smallTextures[i], smallTempRT);
                // smallTex.ReadPixels(new Rect(0, 0, 1024, 32), 0, 0);
                // smallTex.Apply();
                // EditorUtility.CompressTexture(smallTex, TextureFormat.BC4, TextureCompressionQuality.Best);
                // Graphics.CopyTexture(smallTex, 0, smallArray, i);
            //}
        }

        Scene scene = SceneManager.GetActiveScene();
        
        if (!Directory.Exists($"{dir}/Autogenerated/"))
            Directory.CreateDirectory($"{dir}/Autogenerated/");

        string texArrayFilename = $"{dir}/Autogenerated/{scene.name} - Gobo Textures.asset";
        string lutArrayFilename = $"{dir}/Autogenerated/{scene.name} - LUT Textures.asset";
        //string smallArrayFilename = $"{dir}/Autogenerated/{scene.name} - Small Textures.asset";

        AssetDatabase.CreateAsset(texArray, texArrayFilename);
        AssetDatabase.CreateAsset(lutArray, lutArrayFilename);
        //AssetDatabase.CreateAsset(smallArray, smallArrayFilename);
        AssetDatabase.SaveAssets();

        texArray = (Texture2DArray)AssetDatabase.LoadAssetAtPath(texArrayFilename, typeof(Texture2DArray));
        lutArray = (Texture2DArray)AssetDatabase.LoadAssetAtPath(lutArrayFilename, typeof(Texture2DArray));
        //smallArray = (Texture2DArray)AssetDatabase.LoadAssetAtPath(smallArrayFilename, typeof(Texture2DArray));

        videoLUT.material.SetTexture("_MainTex", videoGobo);
        //videoLUTSmall.material.SetTexture("_MainTex", videoGobo);

        foreach (Material mat in materials) {
            mat.SetTexture("_GoboTex", texArray);
            mat.SetTexture("_GoboLUT", lutArray);
            mat.SetTexture("_GoboSmall", null);
            mat.SetTexture("_GoboTex15", videoGobo);
            mat.SetTexture("_GoboLUT15", videoLUT);
            mat.SetTexture("_GoboSmall15", videoLUTSmall);
        }

        AssetDatabase.SaveAssets();
    }
}

[CustomEditor(typeof(LUTBeamMaterialManager))]
public class LUTBeamMaterialManager_Editor : Editor {
    public override void OnInspectorGUI()
    {
        if (GUILayout.Button("Generate Materials"))
        {
            LUTBeamMaterialManager manager = FindObjectOfType<LUTBeamMaterialManager>();

            manager._GenerateMaterials();
        }

        DrawDefaultInspector();
    }
}

#endif
