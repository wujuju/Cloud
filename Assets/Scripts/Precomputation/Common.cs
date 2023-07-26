using System;
using System.Reflection;
using UnityEngine;
using UnityEngine.Rendering;

public class Common
{
    public static void CheckOrCreateLUT(ref RenderTexture targetLUT, Vector3Int size, RenderTextureFormat format,
        TextureWrapMode mode, FilterMode filterMode)
    {
        if (targetLUT == null || (targetLUT.width != size.x || targetLUT.height != size.y))
        {
            if (targetLUT != null) targetLUT.Release();

            var rt = new RenderTexture(size.x, size.y, 0,
                format, RenderTextureReadWrite.Linear);
            if (size.z > 0)
            {
                rt.dimension = TextureDimension.Tex3D;
                rt.volumeDepth = size.z;
            }

            rt.useMipMap = false;
            rt.filterMode = filterMode;
            rt.enableRandomWrite = true;
            rt.wrapMode = mode;
            rt.Create();
            targetLUT = rt;
        }
    }

    public static void Dispatch(ComputeShader cs, int kernel, Vector3Int lutSize)
    {
        if (lutSize.z == 0)
            lutSize.z = 1;
        cs.GetKernelThreadGroupSizes(kernel, out var threadNumX, out var threadNumY, out var threadNumZ);
        cs.Dispatch(kernel, lutSize.x / (int)threadNumX,
            lutSize.y / (int)threadNumY, lutSize.z);
    }

    public static void Dispatch(CommandBuffer cmd, ComputeShader cs, int kernel, Vector3Int lutSize)
    {
        if (lutSize.z == 0)
            lutSize.z = 1;
        cs.GetKernelThreadGroupSizes(kernel, out var threadNumX, out var threadNumY, out var threadNumZ);
        cmd.DispatchCompute(cs, kernel, lutSize.x / (int)threadNumX,
            lutSize.y / (int)threadNumY, lutSize.z);
    }

    public static void SetComputeShaderConstant(Type structType, object cb, ComputeShader cs)
    {
        FieldInfo[] fields = structType.GetFields(BindingFlags.Public | BindingFlags.Instance);
        foreach (FieldInfo field in fields)
        {
            var value = field.GetValue(cb);
            if (field.FieldType == typeof(float))
            {
                cs.SetFloat(field.Name, (float)value);
            }
            else if (field.FieldType == typeof(int))
            {
                cs.SetInt(field.Name, (int)value);
            }
            else if (field.FieldType == typeof(Vector2))
            {
                cs.SetVector(field.Name, (Vector2)value);
            }
            else if (field.FieldType == typeof(Vector3))
            {
                cs.SetVector(field.Name, (Vector3)value);
            }
            else if (field.FieldType == typeof(Vector4))
            {
                cs.SetVector(field.Name, (Vector4)value);
            }
            else
            {
                throw new Exception("not find type:" + field.FieldType);
            }
        }
    }
    
    public static void SetComputeShaderConstant(Type structType, object cb, Material cs)
    {
        FieldInfo[] fields = structType.GetFields(BindingFlags.Public | BindingFlags.Instance);
        foreach (FieldInfo field in fields)
        {
            var value = field.GetValue(cb);
            if (field.FieldType == typeof(float))
            {
                cs.SetFloat(field.Name, (float)value);
            }
            else if (field.FieldType == typeof(int))
            {
                cs.SetInt(field.Name, (int)value);
            }
            else if (field.FieldType == typeof(Vector2))
            {
                cs.SetVector(field.Name, (Vector2)value);
            }
            else if (field.FieldType == typeof(Vector3))
            {
                cs.SetVector(field.Name, (Vector3)value);
            }
            else if (field.FieldType == typeof(Vector4))
            {
                cs.SetVector(field.Name, (Vector4)value);
            }
            else
            {
                throw new Exception("not find type:" + field.FieldType);
            }
        }
    }
}