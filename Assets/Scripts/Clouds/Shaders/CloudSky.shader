Shader "Hidden/Clouds"
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
            #include "Assets/Scripts/Precomputation/common.hlsl"

            v2f vert2(appdata v)
            {
                v2f output;
                output.pos = TransformObjectToHClip(v.vertex);
                output.uv = v.uv;
                float3 viewVector = mul(unity_CameraInvProjection, float4(v.uv * 2 - 1, 0, -1));
                output.viewVector = mul(unity_CameraToWorld, float4(viewVector, 0));
                return output;
            }

            // Henyey-Greenstein
            float hg(float a, float g)
            {
                float g2 = g * g;
                return (1.0 - g2) / (4.0 * 3.1415 * pow(1.0 + g2 - 2.0 * g * a, 1.5));
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
                float time = _Time.x * mTimeScale;
                float3 uvw = (rayPos) / size + 0.5f + float3(time, time * 0.1, time * 0.2) * mBakeCloudSpeed * 0.01;
                float4 col = CloudBakeTex.SampleLevel(samplerCloudBakeTex, uvw, 0);
                return col;
            }

            float3 lightmarch(float3 p)
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
                    float density = sampleDensity2(p, _Time.x);
                    totalDensity += max(0, density * stepSize);
                    p += dirToLight * stepSize;
                }

                transmittance = beer(totalDensity * mLightAbsorptionTowardSun);

                float3 cloudColor = lerp(mColA, mainLight.color, saturate(transmittance * 0.86));
                cloudColor = lerp(mColB, cloudColor, saturate(pow(transmittance * 0.82, 3)));

                return mDarknessThreshold + transmittance * (1 - mDarknessThreshold) * cloudColor;
            }


            #if USE_DOWN_TEX
            TEXTURE2D_X_FLOAT(_DownSampleDepthTex);
            SAMPLER(sampler_DownSampleDepthTex);
            #endif

            float4 frag(v2f i) : SV_Target
            {
                // Create ray
                float3 rayPos = _WorldSpaceCameraPos;
                float viewLength = length(i.viewVector);
                float3 rayDir = i.viewVector / viewLength;

                // Depth and cloud container intersection info:
                #if USE_DOWN_TEX
                float nonlin_depth = SAMPLE_DEPTH_TEXTURE(_DownSampleDepthTex, sampler_DownSampleDepthTex, i.uv);
                #else
                float nonlin_depth = SampleSceneDepth(i.uv);
                #endif

                // float nonlin_depth = SampleSceneDepth(i.uv);
                float depth = LinearEyeDepth(nonlin_depth, _ZBufferParams) * viewLength;
                float2 rayToContainerInfo = rayBoxDst(mBoundsMin, mBoundsMax, rayPos, 1 / rayDir);
                float dstToBox = rayToContainerInfo.x;
                float dstInsideBox = rayToContainerInfo.y;

                // point of intersection with the cloud container
                float3 entryPoint = rayPos + rayDir * dstToBox;

                // random starting offset (makes low-res results noisy rather than jagged/glitchy, which is nicer)
                float randomOffset = BlueNoise.SampleLevel(samplerBlueNoise, i.uv * mBlueNoiseUV, 0);
                randomOffset *= mRayOffsetStrength;

                // Phase function makes clouds brighter around sun
                Light mainLight = GetMainLight();
                float cosAngle = dot(rayDir, mainLight.direction);
                float phaseVal = phase(cosAngle);

                float dstTravelled = randomOffset;
                float dstLimit = min(depth - dstToBox, dstInsideBox);


                // March through volume:
                float stepSize = 11;
                float transmittance = 1;
                float3 lightEnergy = 0;
                while (dstTravelled < dstLimit)
                {
                    rayPos = entryPoint + rayDir * dstTravelled;

                    #if BAKE
                        float3 bakeColor=bakeDensity(rayPos);
                        float density = bakeColor.r;
                        float sdf=bakeColor.g*mNumStepsSDF;
                        stepSize=sdf;
                     // stepSize=max(11,sdf);
                        float  lightTransmittance = bakeColor.b;
                        lightEnergy += density * stepSize * transmittance * lightTransmittance * phaseVal;
                        transmittance *= exp(-density * stepSize * mLightAbsorptionThroughCloud);
                        // Early exit
                        if (transmittance < 0.01)
                        {
                            break;
                        }
                    #else
                    float density = sampleDensity2(rayPos, _Time.x);
                    if (density > 0)
                    {
                        float3 lightTransmittance = lightmarch(rayPos);
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

                return float4(lightEnergy, transmittance);
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
            //最终的颜色 = (shader计算的颜色*SrcFactor) + (屏幕已有的颜色*One)
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
            #include "Assets/Scripts/Precomputation/common.hlsl"

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
    }
}