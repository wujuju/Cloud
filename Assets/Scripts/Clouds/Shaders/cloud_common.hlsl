#ifndef VOLUMETRIC_CLOUD_COMMON_GLSL
#define VOLUMETRIC_CLOUD_COMMON_GLSL

// My personal volumetric cloud implement.
// Reference implement from https://www.slideshare.net/guerrillagames/the-realtime-volumetric-cloudscapes-of-horizon-zero-dawn.

#include "../common/shared_functions.glsl"
#include "../common/shared_atmosphere.glsl"

// #define kSkyMsExition 0.5
#define kSkyMsExition frameData.sky.atmosphereConfig.cloudMultiScatterExtinction
#define kGroundOcc 0.5


layout (set = 0, binding = 0, rgba16f) uniform image2D imageHdrSceneColor;
layout (set = 0, binding = 1) uniform texture2D inHdrSceneColor;
layout (set = 0, binding = 2, rgba16f) uniform image2D imageCloudRenderTexture; // quater resolution.
layout (set = 0, binding = 3) uniform texture2D inCloudRenderTexture; // quater resolution.
layout (set = 0, binding = 4) uniform texture2D inDepth;
layout (set = 0, binding = 5) uniform texture2D inGBufferA;
layout (set = 0, binding = 6) uniform texture3D inBasicNoise;
layout (set = 0, binding = 7) uniform texture3D inDetailNoise;
layout (set = 0, binding = 8) uniform texture2D inWeatherTexture;
layout (set = 0, binding = 9) uniform texture2D inCloudCurlNoise;
layout (set = 0, binding = 10) uniform texture2D inTransmittanceLut;
layout (set = 0, binding = 11) uniform texture3D inFroxelScatter;
layout (set = 0, binding = 12, rgba16f) uniform image2D imageCloudReconstructionTexture;  // full resolution.
layout (set = 0, binding = 13) uniform texture2D inCloudReconstructionTexture;  // full resolution.
layout (set = 0, binding = 14, r32f) uniform image2D imageCloudDepthTexture;  // quater resolution.
layout (set = 0, binding = 15) uniform texture2D inCloudDepthTexture;  // quater resolution.
layout (set = 0, binding = 16, r32f) uniform image2D imageCloudDepthReconstructionTexture;  // full resolution.
layout (set = 0, binding = 17) uniform texture2D inCloudDepthReconstructionTexture;  // full resolution.
layout (set = 0, binding = 18) uniform texture2D inCloudReconstructionTextureHistory;
layout (set = 0, binding = 19) uniform texture2D inCloudDepthReconstructionTextureHistory;
layout (set = 0, binding = 20) uniform texture2D inSkyViewLut;
layout (set = 0, binding = 21) uniform UniformFrameData { PerFrameData frameData; };
layout (set = 0, binding = 22, rgba16f) uniform image2D imageCloudFogRenderTexture; // quater resolution.
layout (set = 0, binding = 23) uniform texture2D inCloudFogRenderTexture; // quater resolution.
layout (set = 0, binding = 24, rgba16f) uniform image2D imageCloudFogReconstructionTexture;  // full resolution.
layout (set = 0, binding = 25) uniform texture2D inCloudFogReconstructionTexture;  // full resolution.
layout (set = 0, binding = 26) uniform texture2D inCloudFogReconstructionTextureHistory;
layout (set = 0, binding = 27) uniform textureCube inSkyIrradiance;
layout (set = 0, binding = 28) uniform texture2D inSDSMShadowDepth;
layout (set = 0, binding = 29) buffer SSBOCascadeInfoBuffer{ CascadeInfo cascadeInfos[]; };
layout (set = 0, binding = 30) uniform texture2D inHiz;

#define SHARED_SAMPLER_SET 1
#include "../common/shared_sampler.glsl"

#define BLUE_NOISE_BUFFER_SET 2
#include "../common/shared_bluenoise.glsl"

float getDensity(float heightMeter)
{
    return exp(-heightMeter * 0.001) * 0.001 * 0.001 * frameData.sky.atmosphereConfig.cloudGodRayScale;
}

///////////////////////////////////////////////////////////////////////////////////////
//////////////// Paramters ///////////////////////////



// NOTE: 0 is fbm cloud.
//       1 is model based cloud.
// 1 is cute shape and easy get beautiful image.
// 0 is radom shape hard to control shape, but can get a spectacular result in some times.
#define CLOUD_SHAPE 1

// Min max sample count define.
#define kMsCount 2
struct ParticipatingMedia
{
	float extinctionCoefficients[kMsCount];
    float transmittanceToLight[kMsCount];
    float extinctionAcc[kMsCount];
};

// FBM cloud shape, reference from Continuum 2.0  
float calculate3DNoise(vec3 position)
{
    vec3 p = floor(position);
    vec3 b = cubeSmooth(fract(position));
    vec2 uv = 17.0 * p.z + p.xy + b.xy;
    vec2 rg = texture(sampler2D(inCloudCurlNoise, linearRepeatSampler), (uv + 0.5) / 64.0).xy;
    return mix(rg.x, rg.y, b.z);
}

// Calculate cloud noise using FBM.
float calculateCloudFBM(vec3 position, vec3 windDirection, const int octaves)
{
    const float octAlpha = 0.5; // The ratio of visibility between successive octaves
    const float octScale = 3.0; // The downscaling factor between successive octaves
    const float octShift = (octAlpha / octScale) / octaves; // Shift the FBM brightness based on how many octaves are active

    float accum = 0.0;
    float alpha = 0.5;
    vec3  shift = windDirection;
	position += windDirection;
    for (int i = 0; i < octaves; ++i) 
    {
        accum += alpha * calculate3DNoise(position);
        position = (position + shift) * octScale;
        alpha *= octAlpha;
    }
    return accum + octShift;
}

float remap(float value, float orignalMin, float orignalMax, float newMin, float newMax)
{
    return newMin + (saturate((value - orignalMin) / (orignalMax - orignalMin)) * (newMax - newMin));
}

float cloudMap(vec3 posMeter, float normalizeHeight)  // Meter
{
    const float kCoverage = frameData.sky.atmosphereConfig.cloudCoverage;
    const float kDensity  = frameData.sky.atmosphereConfig.cloudDensity;

    const vec3 windDirection = frameData.sky.atmosphereConfig.cloudDirection;
    const float cloudSpeed = frameData.sky.atmosphereConfig.cloudSpeed;

#if CLOUD_SHAPE == 1
    posMeter += windDirection * normalizeHeight * 500.0f;
    vec3 posKm = posMeter * 0.001; 

    vec3 windOffset = (windDirection + vec3(0.0, 0.1, 0.0)) * frameData.appTime.x * cloudSpeed;

    vec2 sampleUv = posKm.xz * frameData.sky.atmosphereConfig.cloudWeatherUVScale;
    vec4 weatherValue = texture(sampler2D(inWeatherTexture, linearRepeatSampler), sampleUv);

    float localCoverage = texture(sampler2D(inCloudCurlNoise, linearRepeatSampler), (frameData.appTime.x * cloudSpeed * 50.0 + posMeter.xz) * 0.000001 + 0.5).x;
    localCoverage = saturate(localCoverage * 3.0 - 0.75) * 0.2;

    float coverage = saturate(kCoverage * (localCoverage + weatherValue.x));
	float gradienShape = remap(normalizeHeight, 0.00, 0.10, 0.1, 1.0) * remap(normalizeHeight, 0.10, 0.80, 1.0, 0.2);

    float basicNoise = texture(sampler3D(inBasicNoise, linearRepeatSampler), (posKm + windOffset) * vec3(frameData.sky.atmosphereConfig.cloudBasicNoiseScale)).r;
    float basicCloudNoise = gradienShape * basicNoise;

	float basicCloudWithCoverage = coverage * remap(basicCloudNoise, 1.0 - coverage, 1, 0, 1);

    vec3 sampleDetailNoise = posKm - windOffset * 0.15;
    float detailNoiseComposite = texture(sampler3D(inDetailNoise, linearRepeatSampler), sampleDetailNoise * frameData.sky.atmosphereConfig.cloudDetailNoiseScale).r;
	float detailNoiseMixByHeight = 0.2 * mix(detailNoiseComposite, 1 - detailNoiseComposite, saturate(normalizeHeight * 10.0));
    
    float densityShape = saturate(0.01 + normalizeHeight * 1.15) * kDensity *
        remap(normalizeHeight, 0.0, 0.1, 0.0, 1.0) * 
        remap(normalizeHeight, 0.8, 1.0, 1.0, 0.0);

    float cloudDensity = remap(basicCloudWithCoverage, detailNoiseMixByHeight, 1.0, 0.0, 1.0);
	return cloudDensity * densityShape;
#else
    float wind = frameData.appTime.x * cloudSpeed *  -0.006125;
    vec3  windOffset = vec3(wind, 0.0, wind);

    vec3  cloudPos = posMeter * 0.00045;
    float clouds = calculateCloudFBM(cloudPos, windOffset, 5);
    
    float localCoverage = texture(sampler2D(inCloudCurlNoise, linearRepeatSampler), (frameData.appTime.x * cloudSpeed * 50.0 + posMeter.xz) * 0.000001 + 0.5).x;
    localCoverage = saturate(localCoverage * 3.0 - 0.75) * 0.5 + 0.5;

    float heightAttenuation = remap(normalizeHeight, 0.0, 0.2, 0.0, 1.0) * remap(normalizeHeight, 0.8, 1.0, 1.0, 0.0);

    clouds  = clouds * heightAttenuation * localCoverage * kCoverage * 4.0 - (0.9 * heightAttenuation + normalizeHeight * 0.5 + 0.1);
    clouds  = saturate(clouds);

    return clouds * kDensity;
#endif
 
}

// Cloud shape end.
////////////////////////////////////////////////////////////////////////////////////////

struct ParticipatingMediaPhase
{
	float phase[kMsCount];
};

ParticipatingMediaPhase getParticipatingMediaPhase(float basePhase, float baseMsPhaseFactor)
{
	ParticipatingMediaPhase participatingMediaPhase;
	participatingMediaPhase.phase[0] = basePhase;

	const float uniformPhase = getUniformPhase();
	float MsPhaseFactor = baseMsPhaseFactor;
	
	for (int ms = 1; ms < kMsCount; ms++)
	{
		participatingMediaPhase.phase[ms] = mix(uniformPhase, participatingMediaPhase.phase[0], MsPhaseFactor);
		MsPhaseFactor *= MsPhaseFactor;
	}

	return participatingMediaPhase;
}

float powder(float opticalDepth)
{
	return pow(opticalDepth * 20.0, 0.5) * frameData.sky.atmosphereConfig.cloudPowderScale;
}

vec3 lookupSkylight(vec3 worldDir, vec3 worldPos, float viewHeight, vec3 upVector, ivec2 workPos, in const AtmosphereParameters atmosphere, texture2D lutImage)
{
    const vec3 sunDirection = -normalize(frameData.sky.direction);

    float viewZenithCosAngle = dot(worldDir, upVector);
    // Assumes non parallel vectors
	vec3 sideVector = normalize(cross(upVector, worldDir));		

    // aligns toward the sun light but perpendicular to up vector
	vec3 forwardVector = normalize(cross(sideVector, upVector));	

    vec2 lightOnPlane = vec2(dot(sunDirection, forwardVector), dot(sunDirection, sideVector));
	lightOnPlane = normalize(lightOnPlane);
	float lightViewCosAngle = lightOnPlane.x;

    vec2 sampleUv;
    vec3 luminance;

    skyViewLutParamsToUv(atmosphere, false, viewZenithCosAngle, lightViewCosAngle, viewHeight, vec2(textureSize(lutImage, 0)), sampleUv);
	luminance = texture(sampler2D(lutImage, linearClampEdgeSampler), sampleUv).rgb;

    return luminance;
}

ParticipatingMedia volumetricShadow(vec3 posKm, vec3 sunDirection, in const AtmosphereParameters atmosphere, int fixNum, float msExtinctionFactor)
{
    ParticipatingMedia participatingMedia;

	int ms = 0;

	float extinctionAccumulation[kMsCount];
    float extinctionCoefficients[kMsCount];

	for (ms = 0; ms < kMsCount; ms++)
	{
		extinctionAccumulation[ms] = 0.0f;
        extinctionCoefficients[ms] = 0.0f;
	}

    const float kStepLMul = frameData.sky.atmosphereConfig.cloudLightStepMul;
    const uint kStepLight = fixNum > 0 ? fixNum : frameData.sky.atmosphereConfig.cloudLightStepNum;
    float stepL = frameData.sky.atmosphereConfig.cloudLightBasicStep; // km
    
    float d = stepL * 0.5;

	// Collect total density along light ray.
	for(uint j = 0; j < kStepLight; j++)
    {
        vec3 samplePosKm = posKm + sunDirection * d; // km

        float sampleHeightKm = length(samplePosKm);
        float sampleDt = sampleHeightKm - atmosphere.cloudAreaStartHeight;

        float normalizeHeight = sampleDt / atmosphere.cloudAreaThickness;
        vec3 samplePosMeter = samplePosKm * 1000.0f;

        extinctionCoefficients[0] = cloudMap(samplePosMeter, normalizeHeight);
        extinctionAccumulation[0] += extinctionCoefficients[0] * stepL;

        float MsExtinctionFactor = msExtinctionFactor;// ;
        for (ms = 1; ms < kMsCount; ms++)
		{
            extinctionCoefficients[ms] = extinctionCoefficients[ms - 1] * MsExtinctionFactor;
            MsExtinctionFactor *= MsExtinctionFactor;
			extinctionAccumulation[ms] += extinctionCoefficients[ms] * stepL;
		}

        d += stepL;
        stepL *= kStepLMul;
	}

    for (ms = 0; ms < kMsCount; ms++)
	{
		participatingMedia.transmittanceToLight[ms] = exp(-extinctionAccumulation[ms] * 1000.0); // to meter.
        participatingMedia.extinctionAcc[ms] = extinctionAccumulation[ms] * 1000.0;
	}

    return participatingMedia;
}

float powderEffectNew(float depth, float height, float VoL)
{
    float r = VoL * 0.5 + 0.5;
    r = r * r;
    height = height * (1.0 - r) + r;
    return depth * height;
}

vec4 cloudColorCompute(
    in const AtmosphereParameters atmosphere, 
    vec2 uv, 
    float blueNoise, 
    inout float cloudZ, 
    ivec2 workPos, 
    vec3 worldDir, 
    bool bFog,
    inout vec4 lightingFog,
    float fogNoise)
{
    float sceneZ = textureLod(sampler2D(inHiz, pointClampEdgeSampler), uv, 3).r;


    // Get camera in atmosphere unit position, it will treat as ray start position.
    vec3 worldPos = convertToAtmosphereUnit(frameData.camWorldPos.xyz, frameData) + vec3(0.0, atmosphere.bottomRadius, 0.0);

    lightingFog.w = -1.0f;

    float earthRadius = atmosphere.bottomRadius;
    float radiusCloudStart = atmosphere.cloudAreaStartHeight;
    float radiusCloudEnd = radiusCloudStart + atmosphere.cloudAreaThickness;

    // Unit is atmosphere unit. km.
    float viewHeight = length(worldPos);

    // Find intersect position so we can do some ray marching.
    float tMin;
    float tMax;
    bool bEarlyOutCloud = false;
    if(viewHeight < radiusCloudStart)
    {
        float tEarth = raySphereIntersectNearest(worldPos, worldDir, vec3(0.0), earthRadius);
        if(tEarth > 0.0)
        {
            // Intersect with earth, pre-return.
            bEarlyOutCloud = true;
        }

        tMin = raySphereIntersectInside(worldPos, worldDir, vec3(0.0), radiusCloudStart);
        tMax = raySphereIntersectInside(worldPos, worldDir, vec3(0.0), radiusCloudEnd);
    }
    else if(viewHeight > radiusCloudEnd)
    {
        // Eye out of cloud area.

        vec2 t0t1 = vec2(0.0);
        const bool bIntersectionEnd = raySphereIntersectOutSide(worldPos, worldDir, vec3(0.0), radiusCloudEnd, t0t1);
        if(!bIntersectionEnd)
        {
            // No intersection.
            bEarlyOutCloud = true;
        }

        vec2 t2t3 = vec2(0.0);
        const bool bIntersectionStart = raySphereIntersectOutSide(worldPos, worldDir, vec3(0.0), radiusCloudStart, t2t3);
        if(bIntersectionStart)
        {
            tMin = t0t1.x;
            tMax = t2t3.x;
        }
        else
        {
            tMin = t0t1.x;
            tMax = t0t1.y;
        }
    }
    else
    {
        // Eye inside cloud area.
        float tStart = raySphereIntersectNearest(worldPos, worldDir, vec3(0.0), radiusCloudStart);
        if(tStart > 0.0)
        {
            tMax = tStart;
        }
        else
        {
            tMax = raySphereIntersectInside(worldPos, worldDir, vec3(0.0), radiusCloudEnd);
        }

        tMin = 0.0f; // From camera.
    }

    tMin = max(tMin, 0.0);
    tMax = max(tMax, 0.0);

    // Pre-return if too far.
    if(tMax <= tMin || tMin > frameData.sky.atmosphereConfig.cloudTracingStartMaxDistance)
    {
        bEarlyOutCloud = true;
    }

    // Clamp marching distance by setting.    
    const float marchingDistance = min(frameData.sky.atmosphereConfig.cloudMaxTraceingDistance, tMax - tMin);
	tMax = tMin + marchingDistance;

    const uint stepCountUnit = frameData.sky.atmosphereConfig.cloudMarchingStepNum;
    const float stepCount = float(stepCountUnit);
    const float stepT = (tMax - tMin) / stepCount; // Per step lenght.

    float sampleT = tMin + 0.001 * stepT; // slightly delta avoid self intersect.

    // Jitter by blue noise.
    sampleT += stepT * blueNoise; 
    
    vec3 sunColor = frameData.sky.color * frameData.sky.intensity;
    vec3 sunDirection = -normalize(frameData.sky.direction);

    float VoL = dot(worldDir, sunDirection);

    // Cloud background sky color.
    vec3 skyBackgroundColor = lookupSkylight(worldDir, worldPos, viewHeight, normalize(worldPos), workPos, atmosphere, inSkyViewLut);

    float transmittance  = 1.0;
    vec3 scatteredLight = vec3(0.0, 0.0, 0.0);

    vec3 groundToCloudTransfertIsoScatter =  texture(samplerCube(inSkyIrradiance, linearClampEdgeSampler), vec3(0, 1, 0)).rgb;

    if(!bEarlyOutCloud)
    {
        // Combine backward and forward scattering to have details in all directions.
        float phase = 
                dualLobPhase(frameData.sky.atmosphereConfig.cloudPhaseForward, frameData.sky.atmosphereConfig.cloudPhaseBackward, frameData.sky.atmosphereConfig.cloudPhaseMixFactor, -VoL);

        ParticipatingMediaPhase participatingMediaPhase = getParticipatingMediaPhase(phase, 0.5);

        // Average ray hit pos to evaluate air perspective and height fog.
        vec3 rayHitPos = vec3(0.0);
        float rayHitPosWeight = 0.0;


        // Second evaluate transmittance due to participating media
        vec3 atmosphereTransmittance0;
        {
            vec3 samplePos = sampleT * worldDir + worldPos;
            float sampleHeight = length(samplePos);

            const vec3 upVector = samplePos / sampleHeight;
            float viewZenithCosAngle = dot(sunDirection, upVector);
            vec2 sampleUv;
            lutTransmittanceParamsToUv(atmosphere, viewHeight, viewZenithCosAngle, sampleUv);
            atmosphereTransmittance0 = texture(sampler2D(inTransmittanceLut, linearClampEdgeSampler), sampleUv).rgb;
        }
        vec3 atmosphereTransmittance1;
        {
            vec3 samplePos = tMax * worldDir + worldPos;
            float sampleHeight = length(samplePos);

            const vec3 upVector = samplePos / sampleHeight;
            float viewZenithCosAngle = dot(sunDirection, upVector);
            vec2 sampleUv;
            lutTransmittanceParamsToUv(atmosphere, viewHeight, viewZenithCosAngle, sampleUv);
            atmosphereTransmittance1 = texture(sampler2D(inTransmittanceLut, linearClampEdgeSampler), sampleUv).rgb;
        }

        // groundToCloudTransfertIsoScatter = skyBackgroundColor;// mix(groundToCloudTransfertIsoScatter, skyBackgroundColor, sunDirection.y);
        const vec3 upScaleColor = texture(samplerCube(inSkyIrradiance, linearClampEdgeSampler), vec3(0, 1, 0)).rgb;

        for(uint i = 0; i < stepCountUnit; i ++)
        {
            // World space sample pos, in km unit.
            vec3 samplePos = sampleT * worldDir + worldPos;

            float sampleHeight = length(samplePos);

            vec3 atmosphereTransmittance = mix(atmosphereTransmittance0, atmosphereTransmittance1, saturate(sampleT / marchingDistance));

            // Get sample normalize height [0.0, 1.0]
            float normalizeHeight = (sampleHeight - atmosphere.cloudAreaStartHeight)  / atmosphere.cloudAreaThickness;

            // Convert to meter.
            vec3 samplePosMeter = samplePos * 1000.0f;
            float stepCloudDensity = cloudMap(samplePosMeter, normalizeHeight);

            // Add ray march pos, so we can do some average fading or atmosphere sample effect.
            rayHitPos += samplePos * transmittance;
            rayHitPosWeight += transmittance;

            if(stepCloudDensity > 0.) 
            {
                float opticalDepth = stepCloudDensity * stepT * 1000.0; // to meter unit.
                // beer's lambert.
                // Siggraph 2017's new step transmittance formula.
                float stepTransmittance = max(exp(-opticalDepth), exp(-opticalDepth * 0.25) * 0.7); 

                ParticipatingMedia participatingMedia = volumetricShadow(samplePos, sunDirection, atmosphere, -1, frameData.sky.atmosphereConfig.cloudMultiScatterExtinction);
                ParticipatingMedia participatingMediaAmbient;
                if(frameData.sky.atmosphereConfig.cloudEnableGroundContribution != 0)
                {
                    participatingMediaAmbient = volumetricShadow(samplePos, vec3(0, 1, 0), atmosphere, -1, kSkyMsExition);
                }

                // Compute powder term.
                float powderEffect;
                {
                    float depthProbability = pow(clamp(stepCloudDensity * 8.0 * frameData.sky.atmosphereConfig.cloudPowderPow, 0.0, frameData.sky.atmosphereConfig.cloudPowderScale), remap(normalizeHeight, 0.3, 0.85, 0.5, 2.0));
                    depthProbability += 0.05;
                    float verticalProbability = pow(remap(normalizeHeight, 0.07, 0.22, 0.1, 1.0), 0.8);
                    powderEffect =  powderEffectNew(depthProbability, verticalProbability, VoL);
                }

                // Amount of sunlight that reaches the sample point through the cloud 
                // is the combination of ambient light and attenuated direct light.
                vec3 sunlightTerm = atmosphereTransmittance * frameData.sky.atmosphereConfig.cloudShadingSunLightScale * sunColor; 

                vec3 groundLit = mix(skyBackgroundColor, groundToCloudTransfertIsoScatter, saturate(frameData.sky.atmosphereConfig.cloudNoiseScale - normalizeHeight))
                    * saturate(1.0 - kGroundOcc + normalizeHeight) * frameData.sky.atmosphereConfig.cloudFogFade;

                vec3 ambientLit = upScaleColor * powderEffect * (1.0 - sunDirection.y)
                * atmosphereTransmittance;// mix(atmosphereTransmittance, vec3(1.0), saturate(1.0 - transmittance));// ;

                float sigmaS = stepCloudDensity;
                float sigmaE = max(sigmaS, 1e-8f);

                vec3 scatteringCoefficients[kMsCount];
                float extinctionCoefficients[kMsCount];

                vec3 albedo = frameData.sky.atmosphereConfig.cloudAlbedo;

                scatteringCoefficients[0] = sigmaS * albedo;
                extinctionCoefficients[0] = sigmaE;

                float MsExtinctionFactor = frameData.sky.atmosphereConfig.cloudMultiScatterExtinction;
                float MsScatterFactor    = frameData.sky.atmosphereConfig.cloudMultiScatterScatter;
                int ms;
                for (ms = 1; ms < kMsCount; ms++)
                {
                    extinctionCoefficients[ms] = extinctionCoefficients[ms - 1] * MsExtinctionFactor;
                    scatteringCoefficients[ms] = scatteringCoefficients[ms - 1] * MsScatterFactor;
                    
                    MsExtinctionFactor *= MsExtinctionFactor;
                    MsScatterFactor    *= MsScatterFactor;
                }

                for (ms = kMsCount - 1; ms >= 0; ms--) // Should terminate at 0
                {
                    float sunVisibilityTerm = participatingMedia.transmittanceToLight[ms];
                    vec3 sunSkyLuminance = sunVisibilityTerm * sunlightTerm * participatingMediaPhase.phase[ms] * powderEffect;

                    if(frameData.sky.atmosphereConfig.cloudEnableGroundContribution != 0)
                    {
                        float skyVisibilityTerm = participatingMediaAmbient.transmittanceToLight[ms];
                        sunSkyLuminance += skyVisibilityTerm * ambientLit;
                    }

                    if(ms == 0)
                    {
                        sunSkyLuminance += groundLit;
                    }

                    vec3 sactterLitStep = sunSkyLuminance * scatteringCoefficients[ms];

                #if 0
                    scatteredLight += transmittance * sactterLitStep * stepT * 1000.0;
                #else
                    // See slide 28 at http://www.frostbite.com/2015/08/physically-based-unified-volumetric-rendering-in-frostbite/
                    vec3 stepScatter = transmittance * (sactterLitStep - sactterLitStep * stepTransmittance) / max(1e-4f, extinctionCoefficients[ms]);
                    scatteredLight += stepScatter;
                #endif
                    if(ms == 0)
                    {
                        // Beer's law.
                        transmittance *= stepTransmittance;
                    }
                }
            }

            if(transmittance <= 0.001)
            {
                break;
            }
            sampleT += stepT;
        }


        // Apply some additional effect.
        if(rayHitPosWeight > 0.0f)
        {
            // Get average hit pos.
            rayHitPos /= rayHitPosWeight;

            vec3 rayHitInRender = convertToCameraUnit(rayHitPos - vec3(0.0, atmosphere.bottomRadius, 0.0), frameData);
            vec4 rayInH = frameData.camViewProj * vec4(rayHitInRender, 1.0);
            cloudZ = rayInH.z / rayInH.w;

            rayHitPos -= worldPos;
            float rayHitHeight = length(rayHitPos);

            // Apply air perspective.
            {
                float slice = aerialPerspectiveDepthToSlice(rayHitHeight);
                float weight = 1.0;
                if (slice < 0.5)
                {
                    // We multiply by weight to fade to 0 at depth 0. That works for luminance and opacity.
                    weight = saturate(slice * 2.0);
                    slice = 0.5;
                }
                ivec3 sliceLutSize = textureSize(inFroxelScatter, 0);
                float w = sqrt(slice / float(sliceLutSize.z));	// squared distribution

                vec4 airPerspective = weight * texture(sampler3D(inFroxelScatter, linearClampEdgeSampler), vec3(uv, w));
                scatteredLight = scatteredLight * (1.0 - airPerspective.a) + airPerspective.rgb * (1.0 - transmittance);
            }


        }

    }


    // God ray for light.
    if(bFog)
    {
        {
            const uint  kGodRaySteps = 36;

            // Meter.
            float stepLength = 1000.0f * (atmosphere.cloudAreaStartHeight -  worldPos.y) / clamp(worldDir.y, 0.1, 1.0) / float(kGodRaySteps);
            vec3 stepRay = worldDir * stepLength;
            vec3 rayPosWP = frameData.camWorldPos.xyz + stepRay * (fogNoise + 0.5);

            vec3 transmittanceTotal  = vec3(1.0);
            vec3 scatteredLightTotal = vec3(0.0, 0.0, 0.0);

            float miePhaseValue = hgPhase(atmosphere.miePhaseG, -VoL);
            float rayleighPhaseValue = rayleighPhase(VoL);

            for(uint i = 0; i < kGodRaySteps; i ++)
            {
                vec3 P0 = convertToAtmosphereUnit(rayPosWP, frameData) + vec3(0.0, atmosphere.bottomRadius, 0.0);  // meter -> kilometers.
                float visibilityTerm = 1.0;
                {
                    const uint kStepLight = 8;
                    float stepL = atmosphere.cloudAreaThickness / float(kStepLight); // km
                    stepL = stepL / abs(sunDirection.y);
                    vec3 position = P0;
                    position += P0.y <= atmosphere.cloudAreaStartHeight ? 
                        sunDirection * (atmosphere.cloudAreaStartHeight - P0.y) / sunDirection.y : vec3(0.0);

                    float d = stepL * 0.01;
                    float transmittanceShadow = 0.0;
                    for(uint j = 0; j < kStepLight; j++)
                    {
                        vec3 samplePosKm = position + sunDirection * d; // km
                        float sampleHeightKm = samplePosKm.y;
                        float sampleDt = sampleHeightKm - atmosphere.cloudAreaStartHeight;
                        float normalizeHeight = sampleDt / atmosphere.cloudAreaThickness;
                        vec3 samplePosMeter = samplePosKm * 1000.0f;

                        transmittanceShadow += cloudMap(samplePosMeter, normalizeHeight);

                        d += stepL;
                    }
                    visibilityTerm = exp(-transmittanceShadow * stepL * 1000.0);
                }

                visibilityTerm = mix(visibilityTerm, 1.0, saturate(1.0 - sunDirection.y * 5.0));

                vec3 phaseTimesScattering = vec3(miePhaseValue + rayleighPhaseValue);

                // Second evaluate transmittance due to participating media
                vec3 atmosphereTransmittance;
                {
                    float viewHeight = length(P0);
                    const vec3 upVector = P0 / viewHeight;
                    float viewZenithCosAngle = dot(sunDirection, upVector);
                    vec2 sampleUv;
                    lutTransmittanceParamsToUv(atmosphere, viewHeight, viewZenithCosAngle, sampleUv);
                    atmosphereTransmittance = texture(sampler2D(inTransmittanceLut, linearClampEdgeSampler), sampleUv).rgb;
                }

                float density = getDensity(distance(rayPosWP, frameData.camWorldPos.xyz));

                vec3 sigmaS = vec3(density);
                const float sigmaA = 0.0;
                vec3 sigmaE = max(vec3(1e-6f), sigmaA + sigmaS);
                vec3 sactterLitStep = (visibilityTerm * sunColor * phaseTimesScattering * atmosphereTransmittance  + skyBackgroundColor) * sigmaS;

                vec3 stepTransmittance = exp(-sigmaS * stepLength);
                scatteredLightTotal += transmittanceTotal * (sactterLitStep - sactterLitStep * stepTransmittance) / sigmaE; 
                transmittanceTotal *= stepTransmittance;

                // Step.
                rayPosWP += stepRay;
            }

            lightingFog.w = mean(transmittanceTotal);
            lightingFog.xyz = scatteredLightTotal;
        }
    }

    // Dual mix transmittance.
    vec4 result = vec4(scatteredLight, transmittance);
    if(any(isnan(result)) || any(isinf(result)))
    {
        result = vec4(0.0, 0.0, 0.0, 1.0);
    }
    return result;
}

#endif