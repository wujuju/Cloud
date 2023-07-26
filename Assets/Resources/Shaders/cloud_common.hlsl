#ifndef VOLUMETRIC_CLOUD_COMMON_GLSL
#define VOLUMETRIC_CLOUD_COMMON_GLSL

// My personal volumetric cloud implement.
// Reference implement from https://www.slideshare.net/guerrillagames/the-realtime-volumetric-cloudscapes-of-horizon-zero-dawn.


#define kSkyMsExition 0.5
#define kGroundOcc 0.5


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
float calculate3DNoise(float3 position)
{
    float3 p = floor(position);
    float3 b = cubeSmooth(fract(position));
    float2 uv = 17.0 * p.z + p.xy + b.xy;
    float2 rg = texture(sampler2D(inCloudCurlNoise, linearRepeatSampler), (uv + 0.5) / 64.0).xy;
    return lerp(rg.x, rg.y, b.z);
}

// Calculate cloud noise using FBM.
float calculateCloudFBM(float3 position, float3 windDirection, const int octaves)
{
    const float octAlpha = 0.5; // The ratio of visibility between successive octaves
    const float octScale = 3.0; // The downscaling factor between successive octaves
    const float octShift = (octAlpha / octScale) / octaves; // Shift the FBM brightness based on how many octaves are active

    float accum = 0.0;
    float alpha = 0.5;
    float3  shift = windDirection;
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
		participatingMediaPhase.phase[ms] = lerp(uniformPhase, participatingMediaPhase.phase[0], MsPhaseFactor);
		MsPhaseFactor *= MsPhaseFactor;
	}

	return participatingMediaPhase;
}

float powder(float opticalDepth)
{
	return pow(opticalDepth * 20.0, 0.5) * frameData.sky.atmosphereConfig.cloudPowderScale;
}

float powderEffectNew(float depth, float height, float VoL)
{
    float r = VoL * 0.5 + 0.5;
    r = r * r;
    height = height * (1.0 - r) + r;
    return depth * height;
}

#endif