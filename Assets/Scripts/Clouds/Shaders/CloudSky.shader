Shader "Hidden/Clouds"
{

    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {

        // No culling or depth
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ BAKE

             #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Assets/Scripts/Precomputation/common.hlsl"

            // vertex input: position, UV
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
                v2f output;
                output.pos = TransformObjectToHClip(v.vertex);
                output.uv = v.uv;
                // Camera space matches OpenGL convention where cam forward is -z. In unity forward is positive z.
                // (https://docs.unity3d.com/ScriptReference/Camera-cameraToWorldMatrix.html)
                float3 viewVector = mul(unity_CameraInvProjection, float4(v.uv * 2 - 1, 0, -1));
                output.viewVector = mul(unity_CameraToWorld, float4(viewVector, 0));
                return output;
            }


            sampler2D _MainTex;
            TEXTURE2D(_CameraDepthTexture);
            SAMPLER(sampler_LinearClamp);


            // Debug settings:
            int debugViewMode; // 0 = off; 1 = shape tex; 2 = detail tex; 3 = weathermap
            int debugGreyscale;
            int debugShowAllChannels;
            float debugNoiseSliceDepth;
            float4 debugChannelWeight;
            float debugTileAmount;
            float viewerSize;


            float2 squareUV(float2 uv)
            {
                float width = _ScreenParams.x;
                float height = _ScreenParams.y;
                //float minDim = min(width, height);
                float scale = 1000;
                float x = uv.x * width;
                float y = uv.y * height;
                return float2(x / scale, y / scale);
            }


            // Henyey-Greenstein
            float hg(float a, float g)
            {
                float g2 = g * g;
                return (1 - g2) / (4 * 3.1415 * pow(1 + g2 - 2 * g * (a), 1.5));
            }

            float phase(float a)
            {
                float blend = .5;
                float hgBlend = hg(a, mPhaseParams.x) * (1 - blend) + hg(a, -mPhaseParams.y) * blend;
                return mPhaseParams.z + hgBlend * mPhaseParams.w;
            }

            float beer(float d)
            {
                float beer = exp(-d);
                return beer;
            }

            float remap01(float v, float low, float high)
            {
                return (v - low) / (high - low);
            }

            float3 bakeDensity(float3 rayPos)
            {
                float3 size = mBoundsMax - mBoundsMin;
                float3 uvw = (rayPos) / size + 0.5f;
                float4 col = CloudBakeTex.SampleLevel(samplerCloudBakeTex, uvw, 0);
                return col;
            }

            float sampleDensity(float3 rayPos)
            {
                // Constants:
                const int mipLevel = 0;
                const float baseScale = 1 / 1000.0;
                const float offsetSpeed = 1 / 100.0;

                // Calculate texture sample positions
                float time = _Time.x * mTimeScale;
                float3 size = mBoundsMax - mBoundsMin;
                float3 boundsCentre = (mBoundsMin + mBoundsMax) * .5;
                float3 uvw = (size * .5 + rayPos) * baseScale * mCloudScale;
                float3 shapeSamplePos = uvw + mShapeOffset * offsetSpeed + float3(time, time * 0.1, time * 0.2) *
                    mBaseSpeed;

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
                // heightGradient *= edgeWeight;
                heightGradient = 1;
                // Calculate base shape density
                float4 shapeNoise = NoiseTex.SampleLevel(samplerNoiseTex, shapeSamplePos, mipLevel);
                float4 normalizedShapeWeights = mShapeNoiseWeights / dot(mShapeNoiseWeights, 1);
                float shapeFBM = dot(shapeNoise, normalizedShapeWeights) * heightGradient;
                float baseShapeDensity = shapeFBM + mDensityOffset * .1;
                // Save sampling from detail tex if shape density <= 0
                if (baseShapeDensity > 0)
                {
                    // Sample detail noise
                    float3 detailSamplePos = uvw * mDetailNoiseScale + mDetailOffset * offsetSpeed + float3(
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

            // Calculate proportion of light that reaches the given point from the lightsource
            float lightmarch(float3 p)
            {
                //获取灯光信息
                Light mainLight = GetMainLight();
                float3 dirToLight = mainLight.direction;
                float dstInsideBox = rayBoxDst(mBoundsMin, mBoundsMax, p, 1 / dirToLight).y;

                float transmittance = 1;
                float stepSize = dstInsideBox / mNumStepsLight;
                p += dirToLight * stepSize * .5;
                float totalDensity = 0;

                for (int step = 0; step < mNumStepsLight; step ++)
                {
                    float density = sampleDensity2(p, 0);
                    totalDensity += max(0, density * stepSize);
                    p += dirToLight * stepSize;
                }

                transmittance = beer(totalDensity * mLightAbsorptionTowardSun);

                float clampedTransmittance = mDarknessThreshold + transmittance * (1 - mDarknessThreshold);
                return clampedTransmittance;
            }


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

            float4 frag(v2f i) : SV_Target
            {
                #if DEBUG_MODE == 0
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
                #endif
                // Create ra
                float3 rayPos = _WorldSpaceCameraPos;
                float viewLength = length(i.viewVector);
                float3 rayDir = i.viewVector / viewLength;

                // Depth and cloud container intersection info:
                float nonlin_depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_LinearClamp, i.uv);
                float depth = LinearEyeDepth(nonlin_depth, _ZBufferParams) * viewLength;
                float2 rayToContainerInfo = rayBoxDst(mBoundsMin, mBoundsMax, rayPos, 1 / rayDir);
                float dstToBox = rayToContainerInfo.x;
                float dstInsideBox = rayToContainerInfo.y;

                // point of intersection with the cloud container
                float3 entryPoint = rayPos + rayDir * dstToBox;

                // random starting offset (makes low-res results noisy rather than jagged/glitchy, which is nicer)
                float randomOffset = BlueNoise.SampleLevel(samplerBlueNoise, squareUV(i.uv * 3), 0);
                randomOffset *= mRayOffsetStrength;

                // Phase function makes clouds brighter around sun
                 //获取灯光信息
                Light mainLight = GetMainLight();
                float cosAngle = dot(rayDir, mainLight.direction);
                float phaseVal = phase(cosAngle);

                float dstTravelled = randomOffset;
                float dstLimit = min(depth - dstToBox, dstInsideBox);


                // March through volume:
                float stepSize = 11;
                float transmittance = 1;
                float3 lightEnergy = 0;
                dstTravelled = 11;
                while (dstTravelled < dstLimit)
                {
                    rayPos = entryPoint + rayDir * dstTravelled;

                    #if BAKE
                        float3 bakeColor=bakeDensity(rayPos);
                        float density = bakeColor.r;
                        float sdf=bakeColor.g*max_step;
                    // stepSize = max(11,sdf);
                    stepSize=sdf;
                        float  lightTransmittance = bakeColor.b;
                        lightEnergy += density * stepSize * transmittance * lightTransmittance * phaseVal;
                        transmittance *= exp(-density * stepSize * lightAbsorptionThroughCloud);
                        // Early exit
                        if (transmittance < 0.01)
                        {
                            break;
                        }
                    #else
                    // float density = sampleDensity2(rayPos,_Time.x);
                    float density = sampleDensity2(rayPos, 0);
                    if (density > 0)
                    {
                        float lightTransmittance = lightmarch(rayPos);
                        lightEnergy += density * stepSize * transmittance * lightTransmittance * phaseVal;
                        transmittance *= exp(-density * stepSize * mLightAbsorptionThroughCloud);
                        // Early exit
                        if (transmittance < 0.01)
                        {
                            break;
                        }
                    }
                    #endif

                    dstTravelled += stepSize;
                }


                // Composite sky + background
                float3 skyColBase = lerp(mColA, mColB, sqrt(abs(saturate(rayDir.y))));
                float3 backgroundCol = tex2D(_MainTex, i.uv);
                float dstFog = 1 - exp(-max(0, depth) * 8 * .0001);
                float3 sky = dstFog * skyColBase;
                backgroundCol = backgroundCol * (1 - dstFog) + sky;

                // Sun
                float focusedEyeCos = pow(saturate(cosAngle), mCloudTestParams.x);
                float sun = saturate(hg(focusedEyeCos, .9995)) * transmittance;

                // Add clouds
                float3 cloudCol = lightEnergy * mainLight.color;
                float3 col = backgroundCol * transmittance + cloudCol;
                col = saturate(col) * (1 - sun) + mainLight.color * sun;
                return float4(col, 0);
            }
            ENDHLSL
        }
    }
}