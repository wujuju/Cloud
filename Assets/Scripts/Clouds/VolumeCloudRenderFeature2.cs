using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Serialization;

public class VolumeCloudRenderFeature2 : ScriptableRendererFeature
{
    public VolumetricClouds cloudSettings = new VolumetricClouds();
    private ShaderVariablesClouds2 clouds = new ShaderVariablesClouds2();
    CustomRenderPass m_ScriptablePass;
    public ComputeShader computeShader;
    [HideInInspector] public RenderTexture NewBasicNoiseTex;
    [HideInInspector] public RenderTexture NewDetailNoiseTex;
    public Texture2D BlueNoise;
    public Texture2D WeatherMap;
    public Texture2D CurlNoise;

    static Material _Material;

    public static Material Material
    {
        get
        {
            if (_Material == null)
                _Material = new Material(Shader.Find("Hidden/Clouds2"));
            return _Material;
        }
    }

    public void UpdateBuffer(CommandBuffer cmd)
    {
        if (cloudSettings.RTScale > 1)
            cmd.EnableShaderKeyword("USE_DOWN_TEX");
        else
            cmd.DisableShaderKeyword("USE_DOWN_TEX");

        cloudSettings.UpdateBuffer(ref clouds);
        cmd.SetGlobalTexture("NoiseTex", NewBasicNoiseTex);
        cmd.SetGlobalTexture("DetailNoiseTex", NewDetailNoiseTex);
        cmd.SetGlobalTexture("WeatherMap", WeatherMap);
        cmd.SetGlobalTexture("BlueNoise", BlueNoise);
        cmd.SetGlobalTexture("CurlNoise", CurlNoise);
        Common.SetComputeShaderConstant(clouds.GetType(), clouds, cmd);
    }

    private void Precompute()
    {
        PrecomputeBasicNoiseCloud();
        PrecomputeDetailNoiseCloud();
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

    /// <inheritdoc/>
    public override void Create()
    {
        m_ScriptablePass = new CustomRenderPass(cloudSettings);
        m_ScriptablePass.callbackRender = delegate(CommandBuffer cmd) { UpdateBuffer(cmd); };
        m_ScriptablePass.renderPassEvent = RenderPassEvent.AfterRenderingSkybox;
        Precompute();
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_ScriptablePass);
    }

    class CustomRenderPass : ScriptableRenderPass
    {
        private VolumetricClouds cloudSettings;
        public Action<CommandBuffer> callbackRender;
        int downSampleDepthRT;
        int downSampleColorRT;
        RenderTargetIdentifier blitSrc;

        public CustomRenderPass(VolumetricClouds sets)
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
            CommandBuffer cmd = CommandBufferPool.Get("VolumeCloud");

            var mainMaterial = VolumeCloudRenderFeature2.Material;
            var scale = 1.0f / cloudSettings.RTScale;
            var rtSize = new Vector2Int((int)(Screen.width * scale), (int)(Screen.height * scale));
            RenderTextureDescriptor rtDesc = renderingData.cameraData.cameraTargetDescriptor;

            cmd.GetTemporaryRT(downSampleColorRT, rtSize.x, rtSize.y, 0, FilterMode.Bilinear,
                RenderTextureFormat.DefaultHDR);

            callbackRender?.Invoke(cmd);
            if (cloudSettings.RTScale > 1)
            {
                cmd.GetTemporaryRT(downSampleDepthRT, rtSize.x, rtSize.y, 0, FilterMode.Point,
                    RenderTextureFormat.RFloat);
                cmd.Blit(null, downSampleDepthRT, mainMaterial, 1);
            }

            cmd.Blit(blitSrc, downSampleColorRT, mainMaterial, 0);
            cmd.Blit(downSampleColorRT, blitSrc, mainMaterial, 2);
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
}