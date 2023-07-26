float remap(float v, float minOld, float maxOld, float minNew, float maxNew)
{
    return minNew + (v - minOld) * (maxNew - minNew) / (maxOld - minOld);
}

float basicNoiseComposite(float4 v)
{
    float wfbm = v.y * 0.625 + v.z * 0.25 + v.w * 0.125;
    // cloud shape modeled after the GPU Pro 7 chapter
    return remap(v.x, wfbm - 1.0, 1.0, 0.0, 1.0);
}

float2 rayBoxDst(float3 boundsMin, float3 boundsMax, float3 rayOrigin, float3 invRaydir)
{
    float3 t0 = (boundsMin - rayOrigin) * invRaydir;
    float3 t1 = (boundsMax - rayOrigin) * invRaydir;
    float3 tmin = min(t0, t1);
    float3 tmax = max(t0, t1);
    float dstA = max(max(tmin.x, tmin.y), tmin.z);
    float dstB = min(tmax.x, min(tmax.y, tmax.z));

    float dstToBox = max(0, dstA);
    float dstInsideBox = max(0, dstB - dstToBox);
    return float2(dstToBox, dstInsideBox);
}

Texture3D<float4> NoiseTex;
Texture3D<float4> DetailNoiseTex;
Texture3D<float4> CloudBakeTex;
Texture2D<float4> WeatherMap;
Texture2D<float3> BlueNoise;
Texture2D<float3> CurlNoise;

SamplerState samplerNoiseTex;
SamplerState samplerDetailNoiseTex;
SamplerState samplerWeatherMap;
SamplerState samplerBlueNoise;
SamplerState samplerCurlNoise;
SamplerState samplerCloudBakeTex;

// Shape settings
float4 mCloudTestParams;
int3 mMapSize;
float4 mPhaseParams;
// March settings
float mRayOffsetStrength;
// Light settings
float mLightAbsorptionThroughCloud;
float4 mColA;
float4 mColB;
// Animation settings
float mDetailSpeed;
float mNumStepsSDF;
float3 mBoundsMin;
float3 mBoundsMax;
float mDetailNoiseWeight;
float3 mDetailNoiseWeights;
float4 mShapeNoiseWeights;
float mLightAbsorptionTowardSun;
float mDarknessThreshold;
int mNumStepsLight;
float mCloudScale;
float mBaseSpeed;
float mDensityOffset;
float mDensityMultiplier;
float mDetailNoiseScale;
float3 mShapeOffset;
float3 mDetailOffset;
float mTimeScale;
float mBakeCloudSpeed;
float mNumStepsCloud;
float2 mBlueNoiseUV;


float kMsCount;
float mCloudCoverage;
float mCloudDensity;
float mCloudSpeed;
float mCloudBasicNoiseScale;
float mCloudDetailNoiseScale;
float mCloudPowderPow;
float mCloudPowderScale;
float mCloudShadingSunLightScale;
float mCloudGodRayScale;
float mCloudMultiScatterExtinction;
float mCloudMultiScatterScatter;
float mCloudEnableGroundContribution;
float mCloudWeatherUVScale;
float3 mCloudAlbedo;
float3 mCloudDirection;

float getDensity(float heightMeter)
{
    return exp(-heightMeter * 0.001) * 0.001 * 0.001 * mCloudGodRayScale;
}

float powder(float opticalDepth)
{
    return pow(opticalDepth * 20.0, 0.5) * mCloudPowderScale;
}

float powderEffectNew(float depth, float height, float VoL)
{
    float r = VoL * 0.5 + 0.5;
    r = r * r;
    height = height * (1.0 - r) + r;
    return depth * height;
}

float sampleDensity4(float3 rayPos)
{
    // return sampleDensity2(rayPos,_Time.y);
    float3 boundsCentre = (mBoundsMax + mBoundsMin) * 0.5;
    float3 size = mBoundsMax - mBoundsMin;
    float speedShape = _Time.y * 0.05;
    float speedDetail = _Time.y * 0.3;
    float3 uvwShape = rayPos * 0.002 + float3(speedShape, speedShape * 0.2, 0);
    float3 uvwDetail = rayPos * 0.022 + float3(speedDetail, speedDetail * 0.2, 0);

    float2 uv = (size.xz * 0.5f + (rayPos.xz - boundsCentre.xz)) / max(size.x, size.z);
    float4 weatherMap = SAMPLE_TEXTURE2D_LOD(WeatherMap, samplerWeatherMap, uv, 0);
    float4 shapeNoise = SAMPLE_TEXTURE3D_LOD(NoiseTex, samplerNoiseTex, float4(uvwShape, 0), 0);

    //边缘衰减
    const float containerEdgeFadeDst = 10;
    float dstFromEdgeX = min(containerEdgeFadeDst, min(rayPos.x - mBoundsMin.x, mBoundsMax.x - rayPos.x));
    float dstFromEdgeZ = min(containerEdgeFadeDst, min(rayPos.z - mBoundsMin.z, mBoundsMax.z - rayPos.z));
    float edgeWeight = min(dstFromEdgeZ, dstFromEdgeX) / containerEdgeFadeDst;

    float gMin = remap(weatherMap.x, 0, 1, 0.1, 0.6);
    float gMax = remap(weatherMap.x, 0, 1, gMin, 0.9);
    float heightPercent = (rayPos.y - mBoundsMin.y) / size.y;
    float heightGradient = saturate(remap(heightPercent, 0.0, gMin, 0, 1)) * saturate(
        remap(heightPercent, 1, gMax, 0, 1));
    float heightGradient2 = saturate(remap(heightPercent, 0.0, weatherMap.r, 1, 0)) * saturate(
        remap(heightPercent, 0.0, gMin, 0, 1));
    heightGradient = saturate(lerp(heightGradient, heightGradient2, 0.5));

    heightGradient *= edgeWeight;

    float4 normalizedShapeWeights = mShapeNoiseWeights / dot(mShapeNoiseWeights, 1);
    float shapeFBM = dot(shapeNoise, normalizedShapeWeights) * heightGradient;
    float baseShapeDensity = shapeFBM + mDensityOffset * 0.01;


    if (baseShapeDensity > 0)
    {
        float4 detailNoise = SAMPLE_TEXTURE3D_LOD(DetailNoiseTex, samplerDetailNoiseTex,
                                                  float4(uvwDetail + (shapeNoise.r * 8 * 0.1), 0), 0);
        float detailFBM = pow(detailNoise.r, mDetailNoiseWeights.x);
        float oneMinusShape = 1 - baseShapeDensity;
        float detailErodeWeight = oneMinusShape * oneMinusShape * oneMinusShape;
        float cloudDensity = baseShapeDensity - detailFBM * detailErodeWeight * mDetailNoiseWeight;

        return saturate(cloudDensity * mDensityMultiplier);
    }
    return 0;
}

// Debug settings:
int debugViewMode;
int debugGreyscale;
int debugShowAllChannels;
float debugNoiseSliceDepth;
float4 debugChannelWeight;
float debugTileAmount;
float viewerSize;

float4 debugDrawNoise(float2 uv)
{
    float4 channels = 0;
    float3 samplePos = float3(uv.x, uv.y, debugNoiseSliceDepth);

    if (debugViewMode == 1)
    {
        channels = NoiseTex.SampleLevel(samplerNoiseTex, samplePos, 0);
    }
    else if (debugViewMode == 2)
    {
        channels = DetailNoiseTex.SampleLevel(samplerDetailNoiseTex, samplePos, 0);
    }
    else if (debugViewMode == 3)
    {
        channels = WeatherMap.SampleLevel(samplerWeatherMap, samplePos.xy, 0);
    }

    if (debugShowAllChannels)
    {
        return channels;
    }
    else
    {
        float4 maskedChannels = (channels * debugChannelWeight);
        if (debugGreyscale || debugChannelWeight.w == 1)
        {
            return dot(maskedChannels, 1);
        }
        else
        {
            return maskedChannels;
        }
    }
}
