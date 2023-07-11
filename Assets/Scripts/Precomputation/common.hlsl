float remap(float v, float minOld, float maxOld, float minNew, float maxNew)
{
    return minNew + (v - minOld) * (maxNew - minNew) / (maxOld - minOld);
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

SamplerState samplerNoiseTex;
SamplerState samplerDetailNoiseTex;
SamplerState samplerWeatherMap;
SamplerState samplerBlueNoise;
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


float sampleDensity2(float3 rayPos, float timex)
{
    // Constants:
    const int mipLevel = 0;
    const float baseScale = 1 / 1000.0;
    const float offsetSpeed = 1 / 100.0;

    // Calculate texture sample positions
    float time = timex * mTimeScale;
    float3 size = mBoundsMax - mBoundsMin;
    float3 boundsCentre = (mBoundsMin + mBoundsMax) * .5;
    float3 uvw = (size * .5 + rayPos) * baseScale * mCloudScale;
    float3 shapeSamplePos = uvw + mShapeOffset * offsetSpeed + float3(time, time * 0.1, time * 0.2) * mBaseSpeed;

    // Calculate falloff at along x/z edges of the cloud container
    const float containerEdgeFadeDst = 50;
    float dstFromEdgeX = min(containerEdgeFadeDst, min(rayPos.x - mBoundsMin.x, mBoundsMax.x - rayPos.x));
    float dstFromEdgeZ = min(containerEdgeFadeDst, min(rayPos.z - mBoundsMin.z, mBoundsMax.z - rayPos.z));
    float edgeWeight = min(dstFromEdgeZ, dstFromEdgeX) / containerEdgeFadeDst;

    // Calculate height gradient from weather map
    float2 weatherUV = (size.xz * .5 + (rayPos.xz - boundsCentre.xz)) / max(size.x, size.z);
    float weatherMap = WeatherMap.SampleLevel(samplerWeatherMap, weatherUV, mipLevel).x;
    float gMin = remap(weatherMap.x, 0, 1, 0.1, 0.5);
    float gMax = remap(weatherMap.x, 0, 1, gMin, 0.9);
    float heightPercent = (rayPos.y - mBoundsMin.y) / size.y;
    float heightGradient = saturate(remap(heightPercent, 0.0, gMin, 0, 1)) * saturate(
        remap(heightPercent, 1, gMax, 0, 1));
    heightGradient *= edgeWeight;
    // Calculate base shape density
    float4 shapeNoise = NoiseTex.SampleLevel(samplerNoiseTex, shapeSamplePos, mipLevel);
    float4 normalizedShapeWeights = mShapeNoiseWeights / dot(mShapeNoiseWeights, 1);
    float shapeFBM = dot(shapeNoise, normalizedShapeWeights) * heightGradient;
    float baseShapeDensity = shapeFBM + mDensityOffset * .1;
    // Save sampling from detail tex if shape density <= 0
    if (baseShapeDensity > 0)
    {
        // Sample detail noise
        float3 detailSamplePos = uvw * mDetailNoiseScale + mDetailOffset * offsetSpeed + + float3(
            time * .4, -time, time * 0.1) * mDetailSpeed;
        float4 detailNoise = DetailNoiseTex.SampleLevel(samplerDetailNoiseTex, detailSamplePos, mipLevel);
        float3 normalizedDetailWeights = mDetailNoiseWeights / dot(mDetailNoiseWeights, 1);
        float detailFBM = dot(detailNoise, normalizedDetailWeights);

        // Subtract detail noise from base shape (weighted by inverse density so that edges get eroded more than centre)
        float oneMinusShape = 1 - shapeFBM;
        float detailErodeWeight = oneMinusShape * oneMinusShape * oneMinusShape;
        float cloudDensity = baseShapeDensity - (1 - detailFBM) * detailErodeWeight * mDetailNoiseWeight;

        return cloudDensity * mDensityMultiplier * 0.1;
    }
    return 0;
}
