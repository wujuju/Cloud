using UnityEngine;

public struct ShaderVariablesClouds
{
    public float _rayOffsetStrength;
    public float _lightAbsorptionThroughCloud;
    public Vector4 _cloudTestParams;
    public Vector4 _phaseParams;
    public Vector4 _colA;
    public Vector4 _colB;
    public float _numStepsSDF;
    public Vector3 _boundsMin;
    public Vector3 _boundsMax;
    public float _detailNoiseWeight;
    public Vector3 _detailNoiseWeights;
    public Vector4 _shapeNoiseWeights;
    public float _lightAbsorptionTowardSun;
    public float _darknessThreshold;
    public int _numStepsLight;
    public float _densityOffset;
    public float _densityMultiplier;
    public float _timeScale;
    public float _bakeCloudSpeed;
    public float _numStepsCloud;
    public Vector2 _blueNoiseUV;
}