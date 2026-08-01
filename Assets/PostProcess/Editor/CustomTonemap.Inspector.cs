using UnityEditor;
using UnityEngine;
using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine.Rendering;
using Object = UnityEngine.Object;
using System.Linq;

namespace SilentCustomTonemap.Unity
{
	public partial class CustomTonemapInspector : ShaderGUI
	{
		public class SCFBoot : AssetPostprocessor {
			private static void OnPostprocessAllAssets(string[] importedAssets, string[] deletedAssets, string[] movedAssets,
			string[] movedFromAssetPaths) {
			var isUpdated = importedAssets.Any(path => path.StartsWith("Assets/")) &&
							importedAssets.Any(path => path.Contains("SCT_InspectorData"));

			if (isUpdated) {
				InitializeOnLoad();
			}
			}

			[InitializeOnLoadMethod]
			private static void InitializeOnLoad() {
			CustomTonemapInspector.LoadInspectorData();
			}
		}

		static private TextAsset inspectorData;
		public static Dictionary<string, GUIContent> styles = new Dictionary<string, GUIContent>();

		protected MaterialProperty renderQueueOverride;

		protected GUIContent Content(string i)
		{
			GUIContent style;
			if (styles.TryGetValue(i, out style))
			{
				return style;
			} 
			return new GUIContent(i);
		}

		protected Material target;
		protected MaterialEditor editor;
		Dictionary<string, MaterialProperty> props = new Dictionary<string, MaterialProperty>();

		protected MaterialProperty Property(string i)
		{
			MaterialProperty prop;
			if (props.TryGetValue(i, out prop))
			{
				return prop;
			} 
			return new MaterialProperty();
		}

		public static void LoadInspectorData()
		{
			char[] recordSep = new char[] {'\n'};
			char[] fieldSep = new char[] {'\t'};
			//if (styles.Count == 0)
			{
					string[] guids = AssetDatabase.FindAssets("t:TextAsset SCT_InspectorData." + Application.systemLanguage);
					if (guids.Length == 0)
					{
						guids = AssetDatabase.FindAssets("t:TextAsset SCT_InspectorData.English");
						// If there's no file at all, leave
						if (guids.Length == 0) return;
					}
					inspectorData = (TextAsset)AssetDatabase.LoadAssetAtPath(AssetDatabase.GUIDToAssetPath(guids[0]), typeof(TextAsset));

				string[] records = inspectorData.text.Split(recordSep, System.StringSplitOptions.RemoveEmptyEntries);
				foreach (string record in records)
				{
					string[] fields = record.Split(fieldSep, 3, System.StringSplitOptions.None); 
					if (fields.Length != 3) {Debug.LogWarning("Field " + fields[0] + " only has " + fields.Length + " fields!");};
					if (fields[0] != null) styles[fields[0]] = new GUIContent(fields[1], fields[2]);  
					
				}	
			}		
		}

		protected void FindProperties(MaterialProperty[] matProps, Material material)
		{ 	
			foreach (MaterialProperty prop in matProps)
			{
				props[prop.name] = FindProperty(prop.name, matProps, false);
			}
		}
        
        protected bool initialised;

        protected void Initialise(Material material)
        {
            if (!initialised)
            {
                MaterialChanged(material, true);
                initialised = true;
            }
        }

        protected virtual void MaterialChanged(Material material, bool overrideRenderQueue)
        {
        	// Do nothing
        }	

// https://github.com/Unity-Technologies/UnityCsReference/blob/61f92bd79ae862c4465d35270f9d1d57befd1761/Editor/Mono/Inspector/MaterialEditor.cs#L1468
		public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] matProps)
		{ 
			this.target = materialEditor.target as Material;
			this.editor = materialEditor;
			Material material = this.target;
		
            FindProperties(matProps,material);

			int propertyIndex = 0;
			foreach (MaterialProperty prop in matProps)
			{
				if (!ShaderUtil.IsShaderPropertyHidden(material.shader, propertyIndex)) 
				{
	                if (!styles.ContainsKey(prop.name) ) 
	                {
	                editor.ShaderProperty(prop, prop.displayName);
	                } else {
					ShaderProperty(prop.name);
	                }
				}
				propertyIndex++;
			}
			// No need for the footer; this inspector is for a rendertexture shader.
			// FooterOptions();
        }

		protected void FooterOptions()
		{
			EditorGUILayout.Space();

			if (WithChangeCheck(() => 
			{
				//editor.ShaderProperty(renderQueueOverride, Content(BaseStyles.renderQueueOverrideName));
				editor.RenderQueueField();
			})) {
				MaterialChanged(target, true);
			}
			editor.EnableInstancingField();
		}
    }
}
