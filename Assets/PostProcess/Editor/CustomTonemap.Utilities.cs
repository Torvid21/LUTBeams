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

        public static void WithGroupVertical(Action action)
        {
            EditorGUILayout.BeginVertical();
            action();
            EditorGUILayout.EndVertical();
        }

		// Warning: Do not use BeginHorizontal with ShaderProperty because it causes issues with the layout.
        public static void WithGroupHorizontal(Action action)
        {
            EditorGUILayout.BeginHorizontal();
            action();
            EditorGUILayout.EndHorizontal();
        }

		public static bool WithChangeCheck(Action action)
		{
			EditorGUI.BeginChangeCheck();
			action();
			return EditorGUI.EndChangeCheck();
		}

		public static void WithGUIDisable(bool disable, Action action)
		{
			bool prevState = GUI.enabled;
			GUI.enabled = disable;
			action();
			GUI.enabled = prevState;
		}

		public static Material[] WithMaterialPropertyDropdown(MaterialProperty prop, string[] options, MaterialEditor editor)
		{
			int selection = (int)prop.floatValue;
			EditorGUI.BeginChangeCheck(); 
			selection = EditorGUILayout.Popup(prop.displayName, (int)selection, options);

			if (EditorGUI.EndChangeCheck())
			{
				editor.RegisterPropertyChangeUndo(prop.displayName);
				prop.floatValue = (float)selection;
				return Array.ConvertAll(prop.targets, target => (Material)target);
			}

			return new Material[0];

		}
		
		public static Material[] WithMaterialPropertyDropdownNoLabel(MaterialProperty prop, string[] options, MaterialEditor editor)
		{
			int selection = (int)prop.floatValue;
			EditorGUI.BeginChangeCheck();
			selection = EditorGUILayout.Popup((int)selection, options);

			if (EditorGUI.EndChangeCheck())
			{
				editor.RegisterPropertyChangeUndo(prop.displayName);
				prop.floatValue = (float)selection;
				return Array.ConvertAll(prop.targets, target => (Material)target);
			}

			return new Material[0];

		}

		protected Rect TexturePropertySingleLine(string i)
		{
			GUIContent style;
			if (styles.TryGetValue(i, out style))
			{
				return editor.TexturePropertySingleLine(style, props[i]);
			} 
			return editor.TexturePropertySingleLine(new GUIContent(i), props[i]);
		}

		protected Rect TexturePropertySingleLine(string i, string i2)
		{
			GUIContent style;
			if (styles.TryGetValue(i, out style))
			{
				return editor.TexturePropertySingleLine(style, props[i], props[i2]);
			} 
			return editor.TexturePropertySingleLine(new GUIContent(i), props[i], props[i2]);
		}

		protected Rect TexturePropertySingleLine(string i, string i2, string i3)
		{
			GUIContent style;
			if (styles.TryGetValue(i, out style))
			{
				return editor.TexturePropertySingleLine(style, props[i], props[i2], props[i3]);
			} 
			return editor.TexturePropertySingleLine(new GUIContent(i), props[i], props[i2], props[i3]);
		}

		protected Rect TextureColorPropertyWithColorReset(string tex, string col)
		{
            bool hadTexture = props[tex].textureValue != null;
			Rect returnRect = TexturePropertySingleLine(tex, col);
			
            float brightness = props[col].colorValue.maxColorComponent;
            if (props[tex].textureValue != null && !hadTexture && brightness <= 0f)
                props[col].colorValue = Color.white;
			return returnRect;
		}

		protected Rect TextureColorPropertyWithColorReset(string tex, string col, string prop)
		{
            bool hadTexture = props[tex].textureValue != null;
			Rect returnRect = TexturePropertySingleLine(tex, col, prop);
			
            float brightness = props[col].colorValue.maxColorComponent;
            if (props[tex].textureValue != null && !hadTexture && brightness <= 0f)
                props[col].colorValue = Color.white;
			return returnRect;
		}

		protected Rect TexturePropertyWithHDRColor(string i, string i2)
		{
			GUIContent style;
			if (styles.TryGetValue(i, out style))
			{
				return editor.TexturePropertyWithHDRColor(style, props[i], props[i2], false);
			} 
			return editor.TexturePropertyWithHDRColor(new GUIContent(i), props[i], props[i2], false);
		}

		protected void ShaderProperty(string i)
		{
			GUIContent style;
			if (styles.TryGetValue(i, out style))
			{
				editor.ShaderProperty(props[i], style);
			} else {
				editor.ShaderProperty(props[i], new GUIContent(i));
			}
		}
		

        public static void Vector2Property(MaterialProperty property, GUIContent name)
        {
            EditorGUI.BeginChangeCheck();
            // Align to match scale/offset property
            float kLineHeight = 16;
            float kIndentPerLevel = 15;
            float kVerticalSpacingMultiField = 0;
            Vector2 propValue = new Vector2(property.vectorValue.x, property.vectorValue.y);
            Rect position = EditorGUILayout.GetControlRect(true, 2 * (kLineHeight + kVerticalSpacingMultiField), 
                EditorStyles.layerMaskField);
            float indent = EditorGUI.indentLevel * kIndentPerLevel;
            float labelWidth = EditorGUIUtility.labelWidth;
            float controlStartX = position.x + labelWidth;
            float labelStartX = position.x + indent;
            int oldIndentLevel = EditorGUI.indentLevel;
            EditorGUI.indentLevel = 0;

            Rect labelRect = new Rect(labelStartX, position.y, labelWidth, kLineHeight);
            Rect valueRect = new Rect(controlStartX, position.y, position.width - labelWidth, kLineHeight);
            EditorGUI.PrefixLabel(labelRect, name);
            propValue = EditorGUI.Vector2Field(valueRect, GUIContent.none, propValue);
            if (EditorGUI.EndChangeCheck())
                property.vectorValue = new Vector4(propValue.x, propValue.y, property.vectorValue.z, property.vectorValue.w);
        }

        public static void Vector2PropertyZW(MaterialProperty property, GUIContent name)
        {
            EditorGUI.BeginChangeCheck();
            // Align to match scale/offset property
            float kLineHeight = 16;
            float kIndentPerLevel = 15;
            float kVerticalSpacingMultiField = 0;
            Vector2 propValue = new Vector2(property.vectorValue.x, property.vectorValue.y);
            Rect position = EditorGUILayout.GetControlRect(true, 2 * (kLineHeight + kVerticalSpacingMultiField), 
                EditorStyles.layerMaskField);
            float indent = EditorGUI.indentLevel * kIndentPerLevel;
            float labelWidth = EditorGUIUtility.labelWidth;
            float controlStartX = position.x + labelWidth;
            float labelStartX = position.x + indent;
            int oldIndentLevel = EditorGUI.indentLevel;
            EditorGUI.indentLevel = 0;

            Rect labelRect = new Rect(labelStartX, position.y, labelWidth, kLineHeight);
            Rect valueRect = new Rect(controlStartX, position.y, position.width - labelWidth, kLineHeight);
            EditorGUI.PrefixLabel(labelRect, name);
            propValue = EditorGUI.Vector2Field(valueRect, GUIContent.none, propValue);
            if (EditorGUI.EndChangeCheck())
                property.vectorValue = new Vector4(property.vectorValue.x, property.vectorValue.y, propValue.x, propValue.y);
        }

        protected void DrawShaderPropertySameLine(string i) {
        	int HEADER_HEIGHT = 22; // Arktoon default
            Rect r = EditorGUILayout.GetControlRect(true,0,EditorStyles.layerMaskField);
            r.y -= HEADER_HEIGHT;
            r.height = MaterialEditor.GetDefaultPropertyHeight(props[i]);
            editor.ShaderProperty(r, props[i], " ");
        }
	} // Utilities

} // namespace SilentCustomTonemap.Unity