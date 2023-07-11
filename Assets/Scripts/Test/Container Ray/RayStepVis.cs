using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using Visualisation;

[ExecuteInEditMode]
public class RayStepVis : MonoBehaviour
{
    public Transform container;
    public Transform eye;

    public float dstToBox;
    public float dstInsideBox;


    [Space()] public bool useUV;
    public Vector2 uv;
    public float speed = .1f;
    public float inc = .1f;

    public bool showSamplePoints;
    public int numSamples = 5;
    public Color sampleCol;
    public float ssss = 0;

    void Update()
    {
        if (useUV && Application.isPlaying)
        {
            uv.x += Time.deltaTime * speed;
            if (uv.x > 1)
            {
                uv.x = 0;
                uv.y += inc;
                if (uv.y > 1)
                {
                    uv.y = 1;
                    speed = 0;
                }
            }

            transform.forward = RayDir(uv);
        }

        transform.forward = RayDir(uv);
        var col = Color.red;

        var aa = container.position - container.localScale / 2;
        var bb = container.position + container.localScale / 2;
        var cc = aa + (bb - aa);
        var d = container.localScale;

        RayBox(container.position, container.localScale, eye.position, eye.forward);
        if (dstInsideBox == 0)
        {
            col = Color.grey;
            dstToBox = 999;
        }


        int SQRTSAMPLECOUNT = 8;
        float sqrtSample = SQRTSAMPLECOUNT;
        Vector3 WorldDir;
        Vector3[] RandomSphereSamples =
        {
            new Vector3(-0.7838f, -0.620933f, 0.00996137f),
            new Vector3(0.106751f, 0.965982f, 0.235549f),
            new Vector3(-0.215177f, -0.687115f, -0.693954f),
            new Vector3(0.318002f, 0.0640084f, -0.945927f),
            new Vector3(0.357396f, 0.555673f, 0.750664f),
            new Vector3(0.866397f, -0.19756f, 0.458613f),
            new Vector3(0.130216f, 0.232736f, -0.963783f),
            new Vector3(-0.00174431f, 0.376657f, 0.926351f),
            new Vector3(0.663478f, 0.704806f, -0.251089f),
            new Vector3(0.0327851f, 0.110534f, -0.993331f),
            new Vector3(0.0561973f, 0.0234288f, 0.998145f),
            new Vector3(0.0905264f, -0.169771f, 0.981317f),
            new Vector3(0.26694f, 0.95222f, -0.148393f),
            new Vector3(-0.812874f, -0.559051f, -0.163393f),
            new Vector3(-0.323378f, -0.25855f, -0.910263f),
            new Vector3(-0.1333f, 0.591356f, -0.795317f),
            new Vector3(0.480876f, 0.408711f, 0.775702f),
            new Vector3(-0.332263f, -0.533895f, -0.777533f),
            new Vector3(-0.0392473f, -0.704457f, -0.708661f),
            new Vector3(0.427015f, 0.239811f, 0.871865f),
            new Vector3(-0.416624f, -0.563856f, 0.713085f),
            new Vector3(0.12793f, 0.334479f, -0.933679f),
            new Vector3(-0.0343373f, -0.160593f, -0.986423f),
            new Vector3(0.580614f, 0.0692947f, 0.811225f),
            new Vector3(-0.459187f, 0.43944f, 0.772036f),
            new Vector3(0.215474f, -0.539436f, -0.81399f),
            new Vector3(-0.378969f, -0.31988f, -0.868366f),
            new Vector3(-0.279978f, -0.0109692f, 0.959944f),
            new Vector3(0.692547f, 0.690058f, 0.210234f),
            new Vector3(0.53227f, -0.123044f, -0.837585f),
            new Vector3(-0.772313f, -0.283334f, -0.568555f),
            new Vector3(-0.0311218f, 0.995988f, -0.0838977f),
            new Vector3(-0.366931f, -0.276531f, -0.888196f),
            new Vector3(0.488778f, 0.367878f, -0.791051f),
            new Vector3(-0.885561f, -0.453445f, 0.100842f),
            new Vector3(0.71656f, 0.443635f, 0.538265f),
            new Vector3(0.645383f, -0.152576f, -0.748466f),
            new Vector3(-0.171259f, 0.91907f, 0.354939f),
            new Vector3(-0.0031122f, 0.9457f, 0.325026f),
            new Vector3(0.731503f, 0.623089f, -0.276881f),
            new Vector3(-0.91466f, 0.186904f, 0.358419f),
            new Vector3(0.15595f, 0.828193f, -0.538309f),
            new Vector3(0.175396f, 0.584732f, 0.792038f),
            new Vector3(-0.0838381f, -0.943461f, 0.320707f),
            new Vector3(0.305876f, 0.727604f, 0.614029f),
            new Vector3(0.754642f, -0.197903f, -0.62558f),
            new Vector3(0.217255f, -0.0177771f, -0.975953f),
            new Vector3(0.140412f, -0.844826f, 0.516287f),
            new Vector3(-0.549042f, 0.574859f, -0.606705f),
            new Vector3(0.570057f, 0.17459f, 0.802841f),
            new Vector3(-0.0330304f, 0.775077f, 0.631003f),
            new Vector3(-0.938091f, 0.138937f, 0.317304f),
            new Vector3(0.483197f, -0.726405f, -0.48873f),
            new Vector3(0.485263f, 0.52926f, 0.695991f),
            new Vector3(0.224189f, 0.742282f, -0.631472f),
            new Vector3(-0.322429f, 0.662214f, -0.676396f),
            new Vector3(0.625577f, -0.12711f, 0.769738f),
            new Vector3(-0.714032f, -0.584461f, -0.385439f),
            new Vector3(-0.0652053f, -0.892579f, -0.446151f),
            new Vector3(0.408421f, -0.912487f, 0.0236566f),
            new Vector3(0.0900381f, 0.319983f, 0.943135f),
            new Vector3(-0.708553f, 0.483646f, 0.513847f),
            new Vector3(0.803855f, -0.0902273f, 0.587942f),
            new Vector3(-0.0555802f, -0.374602f, -0.925519f),
        };
        for (int k = 0; k < 64; ++k)
        {
            float i = 0.5f + (k / SQRTSAMPLECOUNT);
            var j2 = (k / SQRTSAMPLECOUNT) * SQRTSAMPLECOUNT;
            float j = 0.5f + (k - j2);
            float randA = i / sqrtSample;
            float randB = j / sqrtSample;
            float theta = 2.0f * Mathf.PI * randA;
            float phi = Mathf.Acos(1.0f - 2.0f * randB);
            float cosPhi = Mathf.Cos(phi);
            float sinPhi = Mathf.Sin(phi);
            float cosTheta = Mathf.Cos(theta);
            float sinTheta = Mathf.Sin(theta);
            WorldDir.x = cosTheta * sinPhi;
            WorldDir.y = sinTheta * sinPhi;
            WorldDir.z = cosPhi;
            // WorldDir = RandomSphereSamples[k];
            // Debug.LogError(string.Format("randA:{0}  randB：{1}  WorldDir：{2}",randA,randB,WorldDir));
            Debug.DrawRay(eye.position, WorldDir * 0.5f, Color.black);
        }

        Debug.DrawRay(eye.position, eye.forward * dstToBox, col);
        Debug.DrawRay(eye.position + eye.forward * dstToBox, eye.forward * dstInsideBox, Color.white);
        if (dstInsideBox == 0)
        {
            dstToBox = 0;
        }
        else
        {
            var aaa = container.localScale * 0.5f;
            var a2 = eye.position + eye.forward * (dstToBox+0.5f);
            RayBox(container.position, container.localScale, a2, eye.forward);

            Debug.LogError(dstToBox + ":" + dstInsideBox);
            Vis.DrawSphere(eye.position + eye.forward * dstToBox, .06f, col, Style.Unlit);
            Vis.DrawSphere(eye.position + eye.forward * (dstToBox + dstInsideBox), .06f, Color.white, Style.Unlit);

            if (showSamplePoints)
            {
                float step = dstInsideBox / numSamples;
                for (int i = 0; i < numSamples; i++)
                {
                    Vis.DrawSphere(eye.position + eye.forward * (dstToBox + step * i), .06f, sampleCol, Style.Unlit);
                }
            }
        }
    }

    Vector3 RayDir(Vector2 uv)
    {
        Camera cam = Camera.main;

        Matrix4x4 inv = cam.projectionMatrix.inverse;
        Matrix4x4 camToWorld = cam.cameraToWorldMatrix;
        Vector3 viewVector = inv * new Vector4(uv.x * 2 - 1, uv.y * 2 - 1, 0, 1);
        return (camToWorld * viewVector).normalized;
        //new Vector3 viewVector = mul (unity_CameraInvProjection, float4 (v.uv * 2 - 1, 0, -1));
        //output.viewVector = mul (unity_CameraToWorld, float4 (viewVector, 0));
    }

    // Calculates dstToBox, dstInsideBox
    // If ray misses box, dstInsideBox will be zero, and dstToBox may have any value
    void RayBox(Vector3 centre, Vector3 size, Vector3 rayOrigin, Vector3 rayDir)
    {
        Vector3 boundsMin = (centre - size / 2);
        Vector3 boundsMax = (centre + size / 2);
        Vector3 invRayDirection = new Vector3((rayDir.x == 0) ? float.MaxValue : 1 / rayDir.x,
            (rayDir.y == 0) ? float.MaxValue : 1 / rayDir.y, (rayDir.z == 0) ? float.MaxValue : 1 / rayDir.z);

        Vector3 t0 = Vector3.Scale(boundsMin - rayOrigin, invRayDirection);
        Vector3 t1 = Vector3.Scale(boundsMax - rayOrigin, invRayDirection);
        Vector3 tmin = Vector3.Min(t0, t1);
        Vector3 tmax = Vector3.Max(t0, t1);

        float a = Mathf.Max(tmin.x, tmin.y, tmin.z);
        float b = Mathf.Min(tmax.x, tmax.y, tmax.z);

        // CASE 1: ray intersects box from outside (0 <= a <= b)
        // a is dst to nearest intersection, b dst to far intersection

        // CASE 2: ray intersects box from inside (a < 0 < b)
        // a is dst to intersection behind the ray, b is dst to forward intersection

        // CASE 3: ray misses box (a > b)

        dstToBox = Mathf.Max(0, a);
        dstInsideBox = Mathf.Max(0, b - dstToBox);
    }

    void OnDrawGizmos()
    {
        Gizmos.color = Color.green;
        Gizmos.DrawWireCube(container.position, container.localScale);
    }
}