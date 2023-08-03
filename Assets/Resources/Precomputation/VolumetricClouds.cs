using UnityEngine;
using UnityEngine.Serialization;

[System.Serializable]
public class VolumetricClouds
{
    [Header(headerDecoration + "Main" + headerDecoration)]
    const string headerDecoration = " --- ";

    [Range(1, 4)] public int RTScale = 1;

    [Range(32, 128)] public int NumPrimarySteps = 64;
    [Range(1, 32)] public int NumLightSteps = 6;
    [Range(0, 1)] public float EarthCurvature = 0.5f;
    [Range(1, 8000)] public float LowestCloudAltitude = 1000f;
    [Range(100, 20000)] public float CloudThickness = 8000f;
    [Range(50, 350)] public float MaxRayMarchingDistance = 120;

    [Header(headerDecoration + "Density" + headerDecoration)]
    public Vector4 WeatherTiling = new Vector4(1, 1, 0, 0);

    [Range(0.001f, 0.1f)] public float WeatherUVScale = 0.01f;
    [Range(0.01f, 10)] public float BasicNoiseScale = 0.3f;
    [Range(0.1f, 5)] public float AltitudeDistortion = 0.125f;
    [Range(0.01f, 10)] public float DetailNoiseScale = 0.6f;
    [Range(0.1f, 1)] public float DensityMultiplier = 1;
    [Range(0, 2)] public float CloudCoverage = 0.5f;
    [Range(0.01f, 1)] public float mCloudCoverageUVScale = 0.01f;

    [Header(headerDecoration + "Lighting" + headerDecoration)] [Range(-1f, 1)]
    public float PhaseForward = 0.5f;

    [Range(-1f, 1)] public float PhaseBackward = -0.5f;
    [Range(0.1f, 5f)] public float LightAbsorptionThroughCloud = 1.05f;
    [Range(0.1f, 5f)] public float LightAbsorptionTowardSun = 1.6f;
    [Range(0.0f, 1f)] public float DarknessThreshold = 0.5f;
    public Color ColA = new Color(1, 0.1010586f, 0, 1);
    [Range(0.0f, 5f)] public float ColAMutiplier = 1;
    public Color ColB = new Color(0.1165883f, 0.1901837f, 0.2704979f, 1);
    [Range(0.0f, 5f)] public float ColBMutiplier = 1;

    [Header(headerDecoration + "Wind" + headerDecoration)]
    [Range(0.1f, 1)] public float WindSpeed = 0.05f;
    public Vector2 WindVector = new Vector2(0, 0);
    [Range(0.1f, 1)] public float BasicNoiseWindSpeed = 1f;
    [Range(0.1f, 1)] public float DetailNoiseWindSpeed = 1f;
    [Range(0.0f, 10)] public float VerticalShapeWindDisplacement = 0f;
    [Range(0.0f, 10)] public float VerticalErosionWindDisplacement = 0f;
    [Range(0.1f, 1)] public float WeatherWindSpeed = 0.05f;

    private Vector2 blueNoiseScale;
    const float k_EarthRadius = 6378100.0f;


    public void UpdateBuffer(ref ShaderVariablesClouds2 cb)
    {
        float kmScale = 0.001f;
        cb._EarthRadius = Mathf.Lerp(1.0f, 0.025f, EarthCurvature) * k_EarthRadius * kmScale;
        cb._LowestCloudAltitude = Mathf.Max(LowestCloudAltitude, 1.0f) * kmScale;
        cb._HighestCloudAltitude = cb._LowestCloudAltitude + CloudThickness * kmScale;
        cb._NumPrimarySteps = NumPrimarySteps;
        cb._MaxRayMarchingDistance = MaxRayMarchingDistance;
        cb._WindVector = WindVector;
        cb._WindSpeed = WindSpeed;
        cb._VerticalShapeWindDisplacement = VerticalShapeWindDisplacement;
        cb._VerticalErosionWindDisplacement = VerticalErosionWindDisplacement;
        cb._BasicNoiseWindSpeed = BasicNoiseWindSpeed;
        cb._DetailNoiseWindSpeed = DetailNoiseWindSpeed;
        cb._WeatherWindSpeed = WeatherWindSpeed;
        cb._WeatherTiling = WeatherTiling;

        cb._NumLightSteps = NumLightSteps;
        cb._PhaseForward = PhaseForward;
        cb._PhaseBackward = PhaseBackward;
        cb._ColA = ColA;
        cb._ColAMutiplier = ColAMutiplier;
        cb._ColBMutiplier = ColBMutiplier;
        cb._ColB = ColB;
        cb._LightAbsorptionThroughCloud = LightAbsorptionThroughCloud;
        cb._LightAbsorptionTowardSun = LightAbsorptionTowardSun;
        cb._DarknessThreshold = DarknessThreshold;

        cb._WeatherUVScale = WeatherUVScale;
        cb._BasicNoiseScale = BasicNoiseScale;
        cb._DetailNoiseScale = DetailNoiseScale;
        cb._AltitudeDistortion = AltitudeDistortion;
        cb._Coverage = CloudCoverage;
        cb._DensityMultiplier = DensityMultiplier;
        cb._CloudCoverageUVScale = mCloudCoverageUVScale;
        cb.blueNoiseScale = new Vector2((float)(Screen.width * 1.0 / RTScale / 256f), (Screen.height * 1f / RTScale / 256f));
    }

    float ComputeNormalizationFactor(float earthRadius, float lowerCloudRadius)
    {
        return Mathf.Sqrt((k_EarthRadius + lowerCloudRadius) * (k_EarthRadius + lowerCloudRadius) - k_EarthRadius * earthRadius);
    }

    float Square(float x)
    {
        return x * x;
    }
}