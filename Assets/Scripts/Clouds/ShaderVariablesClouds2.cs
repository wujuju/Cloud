using UnityEngine;

public struct ShaderVariablesClouds2
{
    public float _EarthRadius;
    public float _LowestCloudAltitude;
    public float _HighestCloudAltitude;
    public float _MaxRayMarchingDistance;
    public float _NumPrimarySteps;
    public float _PhaseForward;
    public float _PhaseBackward;
    public Vector4 _ColA;
    public Vector4 _ColB;
    public Vector4 _WeatherTiling;
    public float _ColAMutiplier;
    public float _ColBMutiplier;
    public float _NumLightSteps;
    public float _DarknessThreshold;
    public float _LightAbsorptionThroughCloud;
    public float _LightAbsorptionTowardSun;
    
    public Vector2 _WindDirection;
    public Vector2 _WindVector;
    public float _VerticalShapeWindDisplacement;
    public float _VerticalErosionWindDisplacement;
    
    public float _DensityMultiplier;
    public float _WindSpeed;
    public float _BasicNoiseWindSpeed;
    public float _DetailNoiseWindSpeed;
    public float _WeatherWindSpeed;
    
    public float _BasicNoiseScale;
    public float _DetailNoiseScale;
    public float _AltitudeDistortion;
    public float _Coverage;
    public float _WeatherUVScale;
    public float _CloudCoverageUVScale;

    public Vector2 blueNoiseScale;
}