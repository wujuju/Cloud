using System;
using System.Reflection;
using Unity.VisualScripting;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Serialization;

public class VolumeCloudRenderFeature : ScriptableRendererFeature
{
    public CloudSettings cloudSettings = new CloudSettings();
    CustomRenderPass m_ScriptablePass;

    /// <inheritdoc/>
    public override void Create()
    {
        m_ScriptablePass = new CustomRenderPass(cloudSettings);
        m_ScriptablePass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
    }

    // Here you can inject one or multiple render passes in the renderer.
    // This method is called when setting up the renderer once per-camera.
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_ScriptablePass);
    }

    class CustomRenderPass : ScriptableRenderPass
    {
        private CloudSettings cloudSettings;

        int downSampleDepthRT;
        int downSampleColorRT;
        RenderTargetIdentifier blitSrc;

        public CustomRenderPass(CloudSettings sets)
        {
            cloudSettings = sets;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var noise = FindObjectOfType<NoiseGenerator>();
            var weatherMapGen = FindObjectOfType<WeatherMap>();
            noise.UpdateNoise();
            weatherMapGen.UpdateMap();
            blitSrc = renderingData.cameraData.renderer.cameraColorTarget;
            downSampleDepthRT = Shader.PropertyToID("_DownSampleDepthTex");
            downSampleColorRT = Shader.PropertyToID("_DownSampleColorTex");
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get(cloudSettings.name);

            var scale = 1.0f / cloudSettings.mRTScale;
            var rtSize = new Vector2Int((int)(Screen.width * scale), (int)(Screen.height * scale));
            RenderTextureDescriptor rtDesc = renderingData.cameraData.cameraTargetDescriptor;
            cmd.GetTemporaryRT(downSampleDepthRT, rtSize.x, rtSize.y, 0, FilterMode.Point, RenderTextureFormat.RFloat);
            cmd.GetTemporaryRT(downSampleColorRT, rtSize.x, rtSize.y, 0, FilterMode.Bilinear, rtDesc.colorFormat);

            cloudSettings.UpdateBuff();
            cmd.Blit(null, downSampleDepthRT, CloudSettings.Material, 1);
            cmd.Blit(blitSrc, downSampleColorRT, CloudSettings.Material, 0);
            cmd.Blit(downSampleColorRT, blitSrc, CloudSettings.Material, 2);
            
            context.ExecuteCommandBuffer(cmd);
            cmd.ReleaseTemporaryRT(downSampleDepthRT);
            cmd.ReleaseTemporaryRT(downSampleColorRT);
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            cmd.ReleaseTemporaryRT(downSampleDepthRT);
            cmd.ReleaseTemporaryRT(downSampleColorRT);
        }
    }


    [System.Serializable]
    public class CloudSettings
    {
        [HideInInspector, HideInBuffer] public bool isInitBake;
        [HideInInspector] public Vector3 mMapSize;
        [HideInInspector] public Vector3 mBoundsMin;
        [HideInInspector] public Vector3 mBoundsMax;
        [HideInInspector] public RenderTexture WeatherMap;
        [HideInInspector] public RenderTexture NoiseTex;
        [HideInInspector] public RenderTexture DetailNoiseTex;
        [HideInInspector] public Vector4 mPhaseParams;
        [HideInInspector] public RenderTexture CloudBakeTex;
        [HideInBuffer] public ComputeShader computeShader;
        [HideInBuffer] public Vector3Int resolution = new Vector3Int(512, 64, 512);
        [HideInInspector, HideInBuffer] public string name = "VolumeCloud";
        [HideInBuffer] public bool isUseBake;


        const string headerDecoration = " --- ";

        [Header(headerDecoration + "Main" + headerDecoration)]
        public Vector3 mCloudTestParams = new Vector3(0.9f, 7.29f, 0.64f);

        [Header(headerDecoration + "Optimize" + headerDecoration)] [Range(1, 4)]
        public int mRTScale = 1;

        [Header(headerDecoration + "March settings" + headerDecoration)] [Range(1, 20)]
        public int mNumStepsLight = 8;

        [Range(100, 3000)] public float mNumStepsSDF = 2000;
        public float mRayOffsetStrength = 9.19f;
        public Texture2D BlueNoise;
        [HideInInspector] public Vector2 mBlueNoiseUV;

        [Header(headerDecoration + "Base Shape" + headerDecoration)]
        public float mCloudScale = 0.6f;

        public float mDensityMultiplier = 0.82f;
        public float mDensityOffset = -3.64f;
        public Vector3 mShapeOffset = new Vector3(29.4f, -47.87f, 1.11f);
        public Vector2 mHeightOffset;
        public Vector4 mShapeNoiseWeights = new Vector4(2.51f, 0.89f, 1.37f, 0.57f);

        [Header(headerDecoration + "Detail" + headerDecoration)]
        public float mDetailNoiseScale = 4;

        public float mDetailNoiseWeight = 1.5f;
        public Vector3 mDetailNoiseWeights = new Vector3(2.57f, 0.89f, 1.37f);
        public Vector3 mDetailOffset = new Vector3(130.23f, 0);


        [Header(headerDecoration + "Lighting" + headerDecoration)]
        public float mLightAbsorptionThroughCloud = 1.05f;

        public float mLightAbsorptionTowardSun = 1.6f;

        [Range(0, 1)] public float mDarknessThreshold = .28f;

        [HideInBuffer, Range(0, 1)] public float forwardScattering = .72f;

        [HideInBuffer, Range(0, 1)] public float backScattering = .33f;

        [HideInBuffer, Range(0, 1)] public float baseBrightness = 1f;

        [HideInBuffer, Range(0, 1)] public float phaseFactor = .83f;

        [Header(headerDecoration + "Animation" + headerDecoration)] [Range(0, 2)]
        public float mTimeScale = 1;

        [Range(0, 2)] public float mBaseSpeed = 0.5f;
        [Range(0, 2)] public float mDetailSpeed = 1;
        [Range(1, 20)] public float mBakeCloudSpeed = 10;

        [Header(headerDecoration + "Sky" + headerDecoration)]
        public Color mColA = new Color(227 / 255f, 246 / 255f, 255 / 255f);

        public Color mColB = new Color(113 / 255f, 164 / 255f, 204 / 255f);


        static Material _Material;

        public static Material Material
        {
            get
            {
                if (_Material == null)
                    _Material = new Material(Shader.Find("Hidden/Clouds"));
                return _Material;
            }
        }

        public void UpdateBuff()
        {
            var material = Material;
            if (isUseBake)
                material.EnableKeyword("BAKE");
            else
                material.DisableKeyword("BAKE");

            var noise = FindObjectOfType<NoiseGenerator>();
            var weatherMapGen = FindObjectOfType<WeatherMap>();
            if (noise == null || weatherMapGen == null)
                return;
#if UNITY_EDITOR
            noise.UpdateNoise();
            weatherMapGen.UpdateMap();
            SetDebugParams();
#endif
            NoiseTex = noise.shapeTexture;
            DetailNoiseTex = noise.detailTexture;
            WeatherMap = weatherMapGen.weatherMap;

            Transform container = GameObject.Find("Container").transform;
            mMapSize = container.localScale;

            mBoundsMin = container.position - container.localScale / 2;
            mBoundsMax = container.position + container.localScale / 2;
            mPhaseParams = new Vector4(forwardScattering, backScattering, baseBrightness, phaseFactor);

            mBlueNoiseUV = new Vector2((float)(Screen.width * 1.0 / mRTScale / BlueNoise.width),
                (float)(Screen.height * 1f / mRTScale / BlueNoise.height));
            SetComputeShaderConstant(GetType(), this);

            PrecomputeCloud();
        }

        private void PrecomputeCloud()
        {
            if (isInitBake && CloudBakeTex)
                return;
            CheckOrCreateLUT(ref CloudBakeTex, resolution, RenderTextureFormat.RGB111110Float, TextureWrapMode.Clamp);
            int index = computeShader.FindKernel("CSMain");
            computeShader.SetTexture(index, Shader.PropertyToID("Result"), CloudBakeTex);
            Dispatch(computeShader, index, resolution);
            isInitBake = true;
        }

        #region 常量缓冲区

        int SetComputeShaderConstant(Type structType, object cb)
        {
            var currMaterial = Material;
            FieldInfo[] fields = structType.GetFields(BindingFlags.Public | BindingFlags.Instance);
            int size = 0;
            foreach (FieldInfo field in fields)
            {
                var attribute = Attribute.GetCustomAttribute(field, typeof(HideInBuffer));
                if (attribute != null)
                    continue;
                var value = field.GetValue(cb);
                if (field.FieldType == typeof(float))
                {
                    computeShader.SetFloat(field.Name, (float)value);
                    currMaterial.SetFloat(field.Name, (float)value);
                    size++;
                }
                else if (field.FieldType == typeof(int))
                {
                    computeShader.SetInt(field.Name, (int)value);
                    currMaterial.SetInt(field.Name, (int)value);
                    size++;
                }
                else if (field.FieldType == typeof(float[]))
                {
                    currMaterial.SetFloatArray(field.Name, (float[])value);
                    size += ((float[])value).Length;
                }
                else if (field.FieldType == typeof(Vector2))
                {
                    computeShader.SetVector(field.Name, (Vector2)value);
                    currMaterial.SetVector(field.Name, (Vector2)value);
                    size += 2;
                }
                else if (field.FieldType == typeof(Vector3))
                {
                    computeShader.SetVector(field.Name, (Vector3)value);
                    currMaterial.SetVector(field.Name, (Vector3)value);
                    size += 3;
                }
                else if (field.FieldType == typeof(Vector4))
                {
                    computeShader.SetVector(field.Name, (Vector4)value);
                    currMaterial.SetVector(field.Name, (Vector4)value);
                    size += 4;
                }
                else if (field.FieldType == typeof(Color))
                {
                    currMaterial.SetColor(field.Name, (Color)value);
                    size += 4;
                }
                else if (field.FieldType == typeof(Texture2D))
                {
                    computeShader.SetTexture(0, field.Name, (Texture2D)value);
                    currMaterial.SetTexture(field.Name, (Texture2D)value);
                }
                else if (field.FieldType == typeof(Matrix4x4))
                {
                    currMaterial.SetMatrix(field.Name, (Matrix4x4)value);
                    size += 16;
                }
                else if (field.FieldType == typeof(RenderTexture))
                {
                    var texture = (RenderTexture)value;
                    if (texture)
                    {
                        computeShader.SetTexture(0, Shader.PropertyToID(field.Name), texture);
                        currMaterial.SetTexture(field.Name, texture);
                    }
                }
                else
                {
                    throw new Exception("not find type:" + field.FieldType);
                }
            }

            // ComputeBuffer buffer = new ComputeBuffer(1,,size);
            // buffer.SetData("cloudSettings",);

            return size;
        }

        void SetDebugParams()
        {
            var material = Material;
            var noise = FindObjectOfType<NoiseGenerator>();
            var weatherMapGen = FindObjectOfType<WeatherMap>();

            int debugModeIndex = 0;
            if (noise.viewerEnabled)
            {
                debugModeIndex = (noise.activeTextureType == NoiseGenerator.CloudNoiseType.Shape) ? 1 : 2;
            }

            if (weatherMapGen.viewerEnabled)
            {
                debugModeIndex = 3;
            }

            if (debugModeIndex == 0)
            {
                material.DisableKeyword("DEBUG_MODE");
                return;
            }

            material.EnableKeyword("DEBUG_MODE");
            material.SetInt("debugViewMode", debugModeIndex);
            material.SetFloat("debugNoiseSliceDepth", noise.viewerSliceDepth);
            material.SetFloat("debugTileAmount", noise.viewerTileAmount);
            material.SetFloat("viewerSize", noise.viewerSize);
            material.SetVector("debugChannelWeight", noise.ChannelMask);
            material.SetInt("debugGreyscale", (noise.viewerGreyscale) ? 1 : 0);
            material.SetInt("debugShowAllChannels", (noise.viewerShowAllChannels) ? 1 : 0);
        }

        #endregion
    }

    #region 工具

    public static void CheckOrCreateLUT(ref RenderTexture targetLUT, Vector3Int size, RenderTextureFormat format,
        TextureWrapMode mode)
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
            rt.filterMode = FilterMode.Bilinear;
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

    sealed class HideInBuffer : Attribute
    {
    }

    #endregion
}