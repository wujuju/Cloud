using System;
using System.Reflection;
using System.Text;
using UnityEditor;
using UnityEngine;
using UnityEngine.Windows;

public class GenerateHLSL : MonoBehaviour
{
    // 添加一个自定义菜单项，点击该菜单项会在控制台输出一条消息
    [MenuItem("Tools/GenerateHLSL")]
    private static void GenerateHLSLCode()
    {
        Type structType = typeof(ShaderVariablesClouds);
        string code = GenerateHLSLCode(typeof(ShaderVariablesClouds), "ShaderVariablesClouds_CS_HLSL", false);
        var savePath = "Assets/Resources/Precomputation/VolumetricCloudsDef.cs.hlsl";
        File.WriteAllBytes(savePath, Encoding.UTF8.GetBytes(code));
    }

    static string GenerateHLSLCode(Type structType, string header, bool isStruct)
    {
        StringBuilder sb = new StringBuilder();
        sb.Append(string.Format("#ifndef {0}\n#define {0}\n", header));
        if (isStruct)
        {
            sb.Append(string.Format("struct {0}\n", structType.ToString()));
            sb.Append("{\n");
        }
        else
            sb.Append(string.Format("CBUFFER_START ({0})\n", structType.ToString()));

        FieldInfo[] fields = structType.GetFields(BindingFlags.Public | BindingFlags.Instance);
        foreach (FieldInfo field in fields)
        {
            var fileName = field.Name;
            if (!fileName.StartsWith("_"))
                fileName = "_" + field.Name;
            if (field.FieldType == typeof(float))
            {
                sb.Append(string.Format("float {0};\n", fileName));
            }
            else if (field.FieldType == typeof(int))
            {
                sb.Append(string.Format("int {0};\n", fileName));
            }
            else if (field.FieldType == typeof(Vector2))
            {
                sb.Append(string.Format("float2 {0};\n", fileName));
            }
            else if (field.FieldType == typeof(Vector3))
            {
                sb.Append(string.Format("float3 {0};\n", fileName));
            }
            else if (field.FieldType == typeof(Vector4))
            {
                sb.Append(string.Format("float4 {0};\n", fileName));
            }
            else
            {
                throw new Exception("cant find type:" + field.FieldType);
            }
        }

        if (isStruct)
            sb.Append("}\n");
        else
            sb.Append("CBUFFER_END\n");
        sb.Append("#endif\n");

        return sb.ToString();
    }
}