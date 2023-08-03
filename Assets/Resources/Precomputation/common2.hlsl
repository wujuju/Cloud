#include "VolumetricCloudsDef2.cs.hlsl"

#define PI          3.14159265358979323846
#define kMsCount 2
// Distance until which the erosion texture i used
#define MIN_EROSION_DISTANCE 3000.0
#define MAX_EROSION_DISTANCE 300000.0
#define CLOUD_DENSITY_TRESHOLD 0.001f
#define EMPTY_STEPS_BEFORE_LARGE_STEPS 8

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


// Structure that describes the ray marching ranges that we should be iterating on
struct RayMarchRange
{
    // The start of the range
    float start;
    // The length of the range
    float distance;
};


float EvaluateNormalizedCloudHeight(float3 positionPS)
{
    return (length(positionPS) - _EarthRadius - _LowestCloudAltitude) / (_HighestCloudAltitude - _LowestCloudAltitude);
}

float Remap(float original_value, float original_min, float original_max, float new_min, float new_max)
{
    return new_min + (((original_value - original_min) / (original_max - original_min)) * (new_max - new_min));
}

float HenyeyGreenstein(float cosAngle, float g)
{
    // There is a mistake in the GPU Gem7 Paper, the result should be divided by 1/(4.PI)
    float g2 = g * g;
    return (1.0 / (4.0 * PI)) * (1.0 - g2) / PositivePow(1.0 + g2 - 2.0 * g * cosAngle, 1.5);
}

float PowderEffect(float cloudDensity, float cosAngle, float intensity)
{
    float powderEffect = 1.0 - exp(-cloudDensity * 4.0);
    powderEffect = saturate(powderEffect * 2.0);
    return lerp(1.0, lerp(1.0, powderEffect, smoothstep(0.5, -0.5, cosAngle)), intensity);
}

int RaySphereIntersection(float3 startPS, float3 dir, float radius, out float2 result)
{
    float a = dot(dir, dir);
    float b = 2.0 * dot(dir, startPS);
    float c = dot(startPS, startPS) - (radius * radius);
    float d = (b * b) - 4.0 * a * c;
    result = 0.0;
    int numSolutions = 0;
    if (d >= 0.0)
    {
        // Compute the values required for the solution eval
        float sqrtD = sqrt(d);
        float q = -0.5 * (b + FastSign(b) * sqrtD);
        result = float2(c / q, q / a);
        // Remove the solutions we do not want
        numSolutions = 2;
        if (result.x < 0.0)
        {
            numSolutions--;
            result.x = result.y;
        }
        if (result.y < 0.0)
            numSolutions--;
    }
    // Return the number of solutions
    return numSolutions;
}

bool RaySphereIntersection(float3 startWS, float3 dir, float radius)
{
    float3 startPS = startWS;
    float a = dot(dir, dir);
    float b = 2.0 * dot(dir, startPS);
    float c = dot(startPS, startPS) - (radius * radius);
    float d = (b * b) - 4.0 * a * c;
    bool flag = false;
    if (d >= 0.0)
    {
        // Compute the values required for the solution eval
        float sqrtD = sqrt(d);
        float q = -0.5 * (b + FastSign(b) * sqrtD);
        float2 result = float2(c / q, q / a);
        flag = result.x > 0.0 || result.y > 0.0;
    }
    return flag;
}

float3 AnimateBaseNoisePosition(float3 positionPS)
{
    // We reduce the top-view repetition of the pattern
    positionPS.y += (positionPS.x / 3.0f + positionPS.z / 7.0f);
    // We add the contribution of the wind displacements
    return positionPS + float3(_WindVector.x, 0.0, _WindVector.y) * _BasicNoiseWindSpeed + float3(0.0, _VerticalShapeWindDisplacement, 0.0);
}

float3 AnimateCloudMapPosition(float3 positionPS)
{
    return positionPS + float3(_WindVector.x, 0.0, _WindVector.y) * _WeatherWindSpeed;
}

float3 AnimateFineNoisePosition(float3 positionPS)
{
    return positionPS + float3(_WindVector.x, 0.0, _WindVector.y) * _DetailNoiseWindSpeed + float3(0.0, _VerticalErosionWindDisplacement, 0.0);
}

float SampleCloudDensity(float3 positionPS, const float height_fraction)
{
    float3 baseNoiseSamplingCoordinates = AnimateBaseNoisePosition(positionPS).xzy * _BasicNoiseScale;
    baseNoiseSamplingCoordinates += height_fraction * float3(_WindDirection.x, _WindDirection.y, 0.0f) * _AltitudeDistortion;
    float base_cloud = SAMPLE_TEXTURE3D_LOD(NoiseTex, samplerNoiseTex, baseNoiseSamplingCoordinates, 0);

    const float2 normalizedPosition = AnimateCloudMapPosition(positionPS).xz * _WeatherUVScale * _WeatherTiling.xy + _WeatherTiling.zw - 0.5;
    const float4 weather_data = SAMPLE_TEXTURE2D_LOD(WeatherMap, samplerWeatherMap, normalizedPosition, 0);
    const float gradien_shape = Remap(height_fraction, 0.00, 0.10, 0.1, 1.0) * Remap(height_fraction, 0.10, 0.80, 1.0, 0.2);

    base_cloud *= gradien_shape;
    float2 curl_noise = SAMPLE_TEXTURE3D_LOD(CurlNoise, samplerCurlNoise, (_Time.x * 50.0 + positionPS.xz) *1e-2 + 0.5, 0);
    // float2 localCoverage = saturate(curl_noise.x * 3.0 - 0.75) * 0.2;
    // const float coverage = saturate(_Coverage * (localCoverage + weather_data.x));
    const float coverage = saturate(_Coverage * weather_data.x);
    const float base_cloud_with_coverage = coverage * Remap(base_cloud, 1.0 - coverage, 1, 0, 1);
    positionPS.xy += curl_noise.xy * (1.0 - height_fraction);
    const float high_freq_FBM = SAMPLE_TEXTURE3D_LOD(DetailNoiseTex, samplerDetailNoiseTex, AnimateFineNoisePosition(positionPS ) * _DetailNoiseScale, 0).r;
    const float high_freq_noise_modifier = lerp(high_freq_FBM, 1.0 - high_freq_FBM, saturate(height_fraction * 10.0));
    const float final_cloud = Remap(base_cloud_with_coverage, high_freq_noise_modifier, 1.0, 0.0, 1.0);
    float density = max(0, final_cloud) * _DensityMultiplier;
    return Remap(density, .5, 1., 0., 1.);
}

bool GetCloudVolumeIntersection_Light(float3 originWS, float3 dir, out float totalDistance)
{
    float2 intersection;
    RaySphereIntersection(originWS, dir, _HighestCloudAltitude + _EarthRadius, intersection);
    bool intersectEarth = RaySphereIntersection(originWS, dir, _EarthRadius);
    totalDistance = intersection.x;
    return !intersectEarth;
}

float3 SampleLightMarch(float3 positionWS, float3 sunDirection, float3 sunColor)
{
    //获取灯光信息
    float totalLightDistance = 0.0;
    float3 luminance = 0.0;
    if (GetCloudVolumeIntersection_Light(positionWS, sunDirection, totalLightDistance))
    {
        float totalDensity = 0.0;

        totalLightDistance = clamp(totalLightDistance, 0, _NumLightSteps * 1000.0);
        totalLightDistance += 5.0f;

        float stepSize = totalLightDistance / (float)_NumLightSteps;

        for (int j = 0; j < _NumLightSteps; j++)
        {
            float dist = stepSize * (0.25 + j);
            float3 currentSamplePointWS = positionWS + sunDirection * dist;
            totalDensity += max(0, SampleCloudDensity(currentSamplePointWS, EvaluateNormalizedCloudHeight(currentSamplePointWS)));
        }
        float transmittance = exp(-totalDensity * _LightAbsorptionTowardSun);
        float3 cloudColor = lerp(_ColA, sunColor, saturate(transmittance * _ColAMutiplier));
        cloudColor = lerp(_ColB, cloudColor, saturate(transmittance * _ColBMutiplier));
        luminance = _DarknessThreshold + transmittance * (1 - _DarknessThreshold) * cloudColor;
    }
    return luminance;
}

bool GetCloudVolumeIntersection(float3 originWS, float3 dir, float insideClouds, float toEarthCenter, out RayMarchRange rayMarchRange)
{
    ZERO_INITIALIZE(RayMarchRange, rayMarchRange);

    // intersect with all three spheres
    float2 intersectionInter, intersectionOuter;
    int numInterInner = RaySphereIntersection(originWS, dir, _LowestCloudAltitude + _EarthRadius, intersectionInter);
    int numInterOuter = RaySphereIntersection(originWS, dir, _HighestCloudAltitude + _EarthRadius, intersectionOuter);
    bool intersectEarth = RaySphereIntersection(originWS, dir, insideClouds < -1.5 ? toEarthCenter : _EarthRadius);

    // Did we achieve any intersection ?
    bool intersect = numInterInner > 0 || numInterOuter > 0;

    // If we are inside the lower cloud bound
    if (insideClouds < -0.5)
    {
        // The ray starts at the first intersection with the lower bound and goes up to the first intersection with the outer bound
        rayMarchRange.start = intersectionInter.x;
        rayMarchRange.distance = intersectionOuter.x - intersectionInter.x;
    }
    else if (insideClouds == 0.0)
    {
        // If we are inside, the ray always starts at 0
        rayMarchRange.start = 0;

        // if we intersect the earth, this means the ray has only one range
        if (intersectEarth)
            rayMarchRange.distance = intersectionInter.x;
            // if we do not untersect the earth and the lower bound. This means the ray exits to outer space
        else if (numInterInner == 0)
            rayMarchRange.distance = intersectionOuter.x;
            // If we do not intersect the earth, but we do intersect the lower bound, we have two ranges.
        else
            rayMarchRange.distance = intersectionInter.x;
    }
    // We are in outer space
    else
    {
        // We always start from our intersection with the outer bound
        rayMarchRange.start = intersectionOuter.x;

        // If we intersect the earth, ony one range
        if (intersectEarth)
            rayMarchRange.distance = intersectionInter.x - intersectionOuter.x;
        else
        {
            // If we do not intersection the lower bound, the ray exits from the upper bound
            if (numInterInner == 0)
                rayMarchRange.distance = intersectionOuter.y - intersectionOuter.x;
            else
                rayMarchRange.distance = intersectionInter.x - intersectionOuter.x;
        }
    }
    // Mke sure we cannot go beyond what the number of samples
    rayMarchRange.distance = clamp(0, rayMarchRange.distance, _MaxRayMarchingDistance);

    // Pre-return if too far.
    if (rayMarchRange.start >= intersectionOuter.x || rayMarchRange.start > _MaxRayMarchingDistance)
    {
        intersect = false;
    }
    // Return if we have an intersection
    return intersect;
}


float basicNoiseComposite(float4 v)
{
    float wfbm = v.y * 0.625 + v.z * 0.25 + v.w * 0.125;
    // cloud shape modeled after the GPU Pro 7 chapter
    return Remap(v.x, wfbm - 1.0, 1.0, 0.0, 1.0);
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
