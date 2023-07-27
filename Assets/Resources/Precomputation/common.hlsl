#include "VolumetricCloudsDef.cs.hlsl"

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

float sampleDensity4(float3 rayPos)
{
    float3 boundsCentre = (_boundsMax + _boundsMin) * 0.5;
    float3 size = _boundsMax - _boundsMin;
    float speedShape = _Time.y * _shapeScale.y;
    float speedDetail = _Time.y * _detailScale.y;
    float3 uvwShape = rayPos * _shapeScale.x + float3(speedShape, speedShape * _shapeScale.z, 0);
    float3 uvwDetail = rayPos * _detailScale.x + float3(speedDetail, speedDetail * _detailScale.z, 0);

    float2 uv = (size.xz * 0.5f + (rayPos.xz - boundsCentre.xz)) / max(size.x, size.z);
    float4 weatherMap = SAMPLE_TEXTURE2D_LOD(WeatherMap, samplerWeatherMap, uv, 0);
    float4 shapeNoise = SAMPLE_TEXTURE3D_LOD(NoiseTex, samplerNoiseTex, float4(uvwShape, 0), 0);

    //边缘衰减
    const float containerEdgeFadeDst = 10;
    float dstFromEdgeX = min(containerEdgeFadeDst, min(rayPos.x - _boundsMin.x, _boundsMax.x - rayPos.x));
    float dstFromEdgeZ = min(containerEdgeFadeDst, min(rayPos.z - _boundsMin.z, _boundsMax.z - rayPos.z));
    float edgeWeight = min(dstFromEdgeZ, dstFromEdgeX) / containerEdgeFadeDst;

    float gMin = remap(weatherMap.x, 0, 1, 0.1, 0.6);
    float gMax = remap(weatherMap.x, 0, 1, gMin, 0.9);
    float heightPercent = (rayPos.y - _boundsMin.y) / size.y;
    float heightGradient = saturate(remap(heightPercent, 0.0, gMin, 0, 1)) * saturate(
        remap(heightPercent, 1, gMax, 0, 1));
    float heightGradient2 = saturate(remap(heightPercent, 0.0, weatherMap.r, 1, 0)) * saturate(
        remap(heightPercent, 0.0, gMin, 0, 1));
    heightGradient = saturate(lerp(heightGradient, heightGradient2, 0.5));

    heightGradient *= edgeWeight;

    float4 normalizedShapeWeights = _shapeNoiseWeights / dot(_shapeNoiseWeights, 1);
    float shapeFBM = dot(shapeNoise, normalizedShapeWeights) * heightGradient;
    float baseShapeDensity = shapeFBM + _densityOffset * 0.01;

    if (baseShapeDensity > 0)
    {
        float4 detailNoise = SAMPLE_TEXTURE3D_LOD(DetailNoiseTex, samplerDetailNoiseTex,
                                                  float4(uvwDetail + (shapeNoise.r * 8 * 0.1), 0), 0);
        float detailFBM = pow(detailNoise.r, _detailNoiseWeights.x);
        float oneMinusShape = 1 - baseShapeDensity;
        float detailErodeWeight = oneMinusShape * oneMinusShape * oneMinusShape;
        float cloudDensity = baseShapeDensity - detailFBM * detailErodeWeight * _detailNoiseWeight;

        return saturate(cloudDensity * _densityMultiplier);
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
