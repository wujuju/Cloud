#ifndef ShaderVariablesClouds_CS_HLSL
#define ShaderVariablesClouds_CS_HLSL
CBUFFER_START (ShaderVariablesClouds)
float _rayOffsetStrength;
float _lightAbsorptionThroughCloud;
float4 _cloudTestParams;
float4 _phaseParams;
float4 _colA;
float4 _colB;
float _numStepsSDF;
float3 _boundsMin;
float3 _boundsMax;
float _detailNoiseWeight;
float3 _detailNoiseWeights;
float4 _shapeNoiseWeights;
float _lightAbsorptionTowardSun;
float _darknessThreshold;
int _numStepsLight;
float _densityOffset;
float _densityMultiplier;
float _timeScale;
float _bakeCloudSpeed;
float _numStepsCloud;
float2 _blueNoiseUV;
CBUFFER_END
#endif
