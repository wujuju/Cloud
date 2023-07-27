using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class VolumeCloudRenderFeature : ScriptableRendererFeature
{
    public CloudSettings cloudSettings = new CloudSettings();
    CustomRenderPass m_ScriptablePass;
    /// <inheritdoc/>
    public override void Create()
    {
        m_ScriptablePass = new CustomRenderPass(cloudSettings);
        m_ScriptablePass.renderPassEvent = RenderPassEvent.AfterRenderingSkybox;
        cloudSettings.Precompute();
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

            cmd.GetTemporaryRT(downSampleColorRT, rtSize.x, rtSize.y, 0, FilterMode.Bilinear,
                RenderTextureFormat.DefaultHDR);

            cloudSettings.UpdateBuff(cmd);
            // int size = Marshal.SizeOf(typeof(ShaderVariablesClouds));
            // ComputeBuffer computeBuffer = new ComputeBuffer(1, size); // 这里假设结构体有两个float成员
            // computeBuffer.SetData(new ShaderVariablesClouds[] { cloudSettings.shaderVariablesClouds });
            // cmd.SetGlobalBuffer(Shader.PropertyToID("ShaderVariablesClouds"), computeBuffer);
            Common.SetComputeShaderConstant(cloudSettings.shaderVariablesClouds.GetType(),
                cloudSettings.shaderVariablesClouds, cmd);
            // CloudSettings.Material.SetBuffer(Shader.PropertyToID("ShaderVariablesClouds"), computeBuffer);
            // CloudSettings.Material.SetConstantBuffer(Shader.PropertyToID("ShaderVariablesClouds"), computeBuffer, 0,
            //     size);
            // ConstantBuffer.Push(cmd, cloudSettings.shaderVariablesClouds,CloudSettings.Material, Shader.PropertyToID("ShaderVariablesClouds"));
            // ConstantBuffer.PushGlobal(cmd, cloudSettings.shaderVariablesClouds, Shader.PropertyToID("ShaderVariablesClouds"));
            if (cloudSettings.mRTScale > 1)
            {
                cmd.GetTemporaryRT(downSampleDepthRT, rtSize.x, rtSize.y, 0, FilterMode.Point,
                    RenderTextureFormat.RFloat);
                cmd.Blit(null, downSampleDepthRT, CloudSettings.Material, 1);
            }
            cmd.Blit(blitSrc, downSampleColorRT, CloudSettings.Material, 0);
            cmd.Blit(downSampleColorRT, blitSrc, CloudSettings.Material, 2);
            if (cloudSettings.isDebug)
                cmd.Blit(null, blitSrc, CloudSettings.Material, 3);
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
        [HideInInspector] public bool isInitBake;
        [HideInInspector] public Vector3 mBoundsMin;
        [HideInInspector] public Vector3 mBoundsMax;
        [HideInInspector] public Vector4 mPhaseParams;
        [HideInInspector] public RenderTexture CloudBakeTex;
        [HideInInspector] public RenderTexture NewBasicNoiseTex;
        [HideInInspector] public RenderTexture NewDetailNoiseTex;
        public ComputeShader computeShader;
        public Vector3Int resolution = new Vector3Int(512, 64, 512);
        [HideInInspector] public string name = "VolumeCloud";
        public bool isUseBake;
        [HideInInspector] public bool isDebug;

        const string headerDecoration = " --- ";

        [Header(headerDecoration + "Main" + headerDecoration)]
        public Texture NoiseTex;

        public Texture DetailNoiseTex;
        public Texture2D BlueNoise;
        public Texture2D WeatherMap;
        public Vector3 mCloudTestParams = new Vector3(0.9f, 7.29f, 0.64f);

        [Header(headerDecoration + "Optimize" + headerDecoration)] [Range(1, 4)]
        public int mRTScale = 1;

        [Header(headerDecoration + "March settings" + headerDecoration)] [Range(6, 20)]
        public int mNumStepsLight = 8;

        [Range(8, 64)] public int mNumStepsCloud = 8;

        [Range(100, 3000)] public float mNumStepsSDF = 2000;
        public float mRayOffsetStrength = 9.19f;
        [HideInInspector] public Vector2 mBlueNoiseUV;

        [Header(headerDecoration + "Base Shape" + headerDecoration)]
        public float mDensityMultiplier = 0.82f;

        public Vector3 shapeScale = new Vector3(0.002f,0.05f,0.2f);
        public Vector3 detailScale = new Vector3(0.022f,0.3f,0.2f);
        public float mDensityOffset = -3.64f;
        public Vector4 mShapeNoiseWeights = new Vector4(2.51f, 0.89f, 1.37f, 0.57f);

        [Header(headerDecoration + "Detail" + headerDecoration)]
        public float mDetailNoiseWeight = 1.5f;

        public Vector3 mDetailNoiseWeights = new Vector3(2.57f, 0.89f, 1.37f);

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

        [Range(1, 20)] public float mBakeCloudSpeed = 10;

        [Header(headerDecoration + "Sky" + headerDecoration)]
        public Color mColA = new Color(1, 0.1010586f, 0, 1);

        public Color mColB = new Color(0.1165883f, 0.1901837f, 0.2704979f, 1);
        public ShaderVariablesClouds shaderVariablesClouds = new ShaderVariablesClouds();

        public void UpdateBuffer(ref ShaderVariablesClouds cb)
        {
            cb._colA = mColA;
            cb._colB = mColB;
            cb._blueNoiseUV = mBlueNoiseUV;
            cb._numStepsCloud = mNumStepsCloud;
            cb._bakeCloudSpeed = mBakeCloudSpeed;
            cb._timeScale = mTimeScale;
            cb._densityMultiplier = mDensityMultiplier;
            cb._densityOffset = mDensityOffset;
            cb._numStepsLight = mNumStepsLight;
            cb._darknessThreshold = mDarknessThreshold;
            cb._lightAbsorptionTowardSun = mLightAbsorptionTowardSun;
            cb._lightAbsorptionThroughCloud = mLightAbsorptionThroughCloud;
            cb._shapeNoiseWeights = mShapeNoiseWeights;
            cb._detailNoiseWeights = mDetailNoiseWeights;
            cb._detailNoiseWeight = mDetailNoiseWeight;
            cb._boundsMax = mBoundsMax;
            cb._boundsMin = mBoundsMin;
            cb._numStepsSDF = mNumStepsSDF;
            cb._phaseParams = mPhaseParams;
            cb._cloudTestParams = mCloudTestParams;
            cb._rayOffsetStrength = mRayOffsetStrength;
            cb._shapeScale = shapeScale;
            cb._detailScale = detailScale;
        }

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

        public void UpdateBuff(CommandBuffer cmd)
        {
            var material = Material;
            if (isUseBake)
                material.EnableKeyword("BAKE");
            else
                material.DisableKeyword("BAKE");

            if (mRTScale > 1)
                material.EnableKeyword("USE_DOWN_TEX");
            else
                material.DisableKeyword("USE_DOWN_TEX");
#if UNITY_EDITOR
            SetDebugParams();
#endif
            Transform container = GameObject.Find("Container").transform;
            // mMapSize = container.localScale;

            mBoundsMin = container.position - container.localScale / 2;
            mBoundsMax = container.position + container.localScale / 2;
            mPhaseParams = new Vector4(forwardScattering, backScattering, baseBrightness, phaseFactor);

            mBlueNoiseUV = new Vector2((float)(Screen.width * 1.0 / mRTScale / BlueNoise.width),
                (float)(Screen.height * 1f / mRTScale / BlueNoise.height));

            this.UpdateBuffer(ref shaderVariablesClouds);

            cmd.SetGlobalTexture("NoiseTex", NoiseTex);
            cmd.SetGlobalTexture("DetailNoiseTex", DetailNoiseTex);
            cmd.SetGlobalTexture("WeatherMap", WeatherMap);
            cmd.SetGlobalTexture("BlueNoise", BlueNoise);
            
            // cmd.SetGlobalTexture("NoiseTex", NewBasicNoiseTex);
            // cmd.SetGlobalTexture("DetailNoiseTex", NewDetailNoiseTex);

            if (isUseBake)
                PrecomputeCloud(cmd);
        }

        private void PrecomputeCloud(CommandBuffer cmd)
        {
            if (isInitBake && CloudBakeTex)
                return;
            // Common.SetComputeShaderConstant(shaderVariablesClouds.GetType(),
            //     shaderVariablesClouds, computeShader);
            Common.CheckOrCreateLUT(ref CloudBakeTex, resolution, RenderTextureFormat.RGB111110Float,
                TextureWrapMode.Clamp, FilterMode.Bilinear);
            int index = computeShader.FindKernel("CSMain");
            computeShader.SetTexture(index, Shader.PropertyToID("Result"), CloudBakeTex);
            Common.Dispatch(cmd, computeShader, index, resolution);
            cmd.SetGlobalTexture("CloudBakeTex", CloudBakeTex);
            isInitBake = true;
        }

        public void Precompute()
        {
            // PrecomputeBasicNoiseCloud();
            // PrecomputeDetailNoiseCloud();
        }

        private void PrecomputeBasicNoiseCloud()
        {
            var size = Vector3Int.one * 128;
            Common.CheckOrCreateLUT(ref NewBasicNoiseTex, size, RenderTextureFormat.ARGBHalf, TextureWrapMode.Repeat,
                FilterMode.Bilinear);
            int index = computeShader.FindKernel("CSBasicNoise");
            computeShader.SetTexture(index, Shader.PropertyToID("Result"), NewBasicNoiseTex);
            Common.Dispatch(computeShader, index, size);
        }

        private void PrecomputeDetailNoiseCloud()
        {
            var size = Vector3Int.one * 64;
            Common.CheckOrCreateLUT(ref NewDetailNoiseTex, size, RenderTextureFormat.R16, TextureWrapMode.Repeat,
                FilterMode.Bilinear);
            int index = computeShader.FindKernel("CSDetailNoise");
            computeShader.SetTexture(index, Shader.PropertyToID("Result2"), NewDetailNoiseTex);
            Common.Dispatch(computeShader, index, size);
        }

        #region 常量缓冲区

        void SetDebugParams()
        {
            var material = Material;
            var noise = FindObjectOfType<NoiseGenerator>();
            var weatherMapGen = FindObjectOfType<WeatherMap>();
            if (noise == null)
                return;
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
                isDebug = false;
                return;
            }

            isDebug = true;
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

    sealed class HideInBuffer : Attribute
    {
    }

    #endregion
}