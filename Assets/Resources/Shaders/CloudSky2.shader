Shader "Hidden/Clouds2"
{
    Properties
    {
        _MainTex("Texture", any) = "" {}
    }
    HLSLINCLUDE
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

    struct appdata
    {
        float4 vertex : POSITION;
        float2 uv : TEXCOORD0;
    };

    struct v2f
    {
        float4 pos : SV_POSITION;
        float2 uv : TEXCOORD0;
        float3 viewVector : TEXCOORD1;
    };

    v2f vert(appdata v)
    {
        v2f o;
        o.pos = TransformObjectToHClip(v.vertex);
        o.uv = v.uv;
        return o;
    }
    ENDHLSL
    SubShader
    {
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert2
            #pragma fragment frag
            #pragma multi_compile _ BAKE
            #pragma multi_compile _ USE_DOWN_TEX


            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Assets/Resources/Precomputation/common2.hlsl"

            v2f vert2(appdata v)
            {
                v2f output;
                output.pos = TransformObjectToHClip(v.vertex);
                output.uv = v.uv;
                float3 viewVector = mul(unity_CameraInvProjection, float4(v.uv * 2 - 1, 0, -1));
                output.viewVector = mul(unity_CameraToWorld, float4(viewVector, 0));
                return output;
            }

            #if USE_DOWN_TEX
            TEXTURE2D_X_FLOAT(_DownSampleDepthTex);
            SAMPLER(sampler_DownSampleDepthTex);
            #endif


            float4 frag(v2f i) : SV_Target
            {
                #if USE_DOWN_TEX
                float depthValue = SAMPLE_DEPTH_TEXTURE(_DownSampleDepthTex, sampler_DownSampleDepthTex, i.uv);
                #else
                float depthValue = SampleSceneDepth(i.uv);
                #endif

                float3 pos = ComputeWorldSpacePosition(i.uv, depthValue,UNITY_MATRIX_I_VP);
                float3 worldPos = _WorldSpaceCameraPos.xyz + float3(0, _EarthRadius, 0);
                float3 worldDir = normalize(pos);
                float toEarthCenter = length(worldPos);
                float insideClouds;
                if (toEarthCenter < _EarthRadius)
                    insideClouds = -2.0;
                else if (toEarthCenter <= (_LowestCloudAltitude + _EarthRadius))
                    insideClouds = -1.0;
                else if (toEarthCenter > (_HighestCloudAltitude + _EarthRadius))
                    insideClouds = 1.0f;
                else
                    insideClouds = 0.0;

                float3 inScattering = 0.0;
                float transmittance = 1.0;

                RayMarchRange rayMarchRange;
                if (GetCloudVolumeIntersection(worldPos, worldDir, insideClouds, toEarthCenter, rayMarchRange))
                {
                    float totalDistance = rayMarchRange.distance;
                    totalDistance = min(totalDistance, 50);
                    float stepS = totalDistance / _NumPrimarySteps;

                    Light mainLight = GetMainLight();
                    float3 sunColor = mainLight.color;
                    float cosAngle = dot(worldDir, mainLight.direction);
                    float a = phase(cosAngle);
                    int currentIndex = 0;
                    float3 currentPositionWS = worldPos + rayMarchRange.start * worldDir;
                    float currentDistance = 0;
                    bool activeSampling = true;
                    int sequentialEmptySamples = 0;
                    // Do the ray march for every step that we can.
                    while (currentIndex < _NumPrimarySteps && currentDistance < totalDistance)
                    {
                        const float height_fraction = EvaluateNormalizedCloudHeight(currentPositionWS);
                        if (activeSampling)
                        {
                            float density = SampleCloudDensity(currentPositionWS, height_fraction);

                            if (density > CLOUD_DENSITY_TRESHOLD)
                            {
                                float opticalDepth = density * stepS; // to meter unit.
                                float3 lightTransmittance = SampleLightMarch(currentPositionWS, mainLight.direction, sunColor);

                                inScattering += opticalDepth * transmittance * lightTransmittance * a;
                                transmittance *= exp(-opticalDepth);
                                if (transmittance < 0.003)
                                {
                                    transmittance = 0.0;
                                    break;
                                }
                                // Reset the empty sample counter
                                sequentialEmptySamples = 0;
                            }
                            else
                                sequentialEmptySamples++;

                            // If it has been more than EMPTY_STEPS_BEFORE_LARGE_STEPS, disable active sampling and start large steps
                            if (sequentialEmptySamples == EMPTY_STEPS_BEFORE_LARGE_STEPS)
                                activeSampling = false;

                            // Do the next step
                            currentPositionWS += worldDir * stepS;
                            currentDistance += stepS;
                        }
                        else
                        {
                            const float density = SampleCloudDensity(currentPositionWS, height_fraction);

                            if (density < CLOUD_DENSITY_TRESHOLD)
                            {
                                currentPositionWS += worldDir * stepS * 2.0f;
                                currentDistance += stepS * 2.0f;
                            }
                            else
                            {
                                currentPositionWS -= worldDir * stepS;
                                currentDistance -= stepS;
                                activeSampling = true;
                                sequentialEmptySamples = 0;
                            }
                        }
                        currentIndex++;
                    }
                }
                return float4(inScattering, transmittance);
            }
            ENDHLSL
        }

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment farg

            float farg(v2f i) : SV_Target
            {
                float2 texelSize = 0.5 * (1.0 / _ScreenParams.xy);
                float2 taps[4] = {
                    float2(i.uv + float2(-1, -1) * texelSize),
                    float2(i.uv + float2(-1, 1) * texelSize),
                    float2(i.uv + float2(1, -1) * texelSize),
                    float2(i.uv + float2(1, 1) * texelSize)
                };

                float depth1 = SampleSceneDepth(taps[0]);
                float depth2 = SampleSceneDepth(taps[1]);
                float depth3 = SampleSceneDepth(taps[2]);
                float depth4 = SampleSceneDepth(taps[3]);

                float result = min(depth1, min(depth2, min(depth3, depth4)));
                return result;
            }
            ENDHLSL
        }

        Pass
        {
            //最终的颜色 = (shader计算的颜色*SrcFactor) + (屏幕已有的颜色*DstFactor)
            Blend One SrcAlpha
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment farg

            TEXTURE2D_X_FLOAT(_DownSampleColorTex);
            SAMPLER(sampler_DownSampleColorTex);

            float4 farg(v2f i) : SV_Target
            {
                return SAMPLE_TEXTURE2D(_DownSampleColorTex, sampler_DownSampleColorTex, i.uv);
            }
            ENDHLSL
        }

        Pass
        {
            Blend One Zero
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment farg
            #include "Assets/Resources/Precomputation/common.hlsl"

            float4 farg(v2f i) : SV_Target
            {
                if (debugViewMode != 0)
                {
                    float width = _ScreenParams.x;
                    float height = _ScreenParams.y;
                    float minDim = min(width, height);
                    float x = i.uv.x * width;
                    float y = (1 - i.uv.y) * height;
                    if (x < minDim * viewerSize && y < minDim * viewerSize)
                    {
                        return debugDrawNoise(float2(x / (minDim * viewerSize) * debugTileAmount,
                                                     y / (minDim * viewerSize) * debugTileAmount));
                    }
                }
                return 0;
            }
            ENDHLSL
        }

        Pass
        {
            //最终的颜色 = (shader计算的颜色*SrcFactor) + (屏幕已有的颜色*DstFactor)
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment farg

            TEXTURE2D_X_FLOAT(_MainTex);
            SAMPLER(sampler_MainTex);

            float4 farg(v2f i) : SV_Target
            {
                return SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
            }
            ENDHLSL
        }
    }
}