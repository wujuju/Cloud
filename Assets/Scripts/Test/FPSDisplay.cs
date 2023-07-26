using UnityEngine;

public class FPSDisplay : MonoBehaviour
{
    private float deltaTime = 0.0f;

    void Update()
    {
        // 计算帧率
        deltaTime += (Time.unscaledDeltaTime - deltaTime) * 0.1f;
    }

    void OnGUI()
    {
        // 设置显示样式
        GUIStyle style = new GUIStyle();
        style.normal.textColor = Color.white;
        style.fontSize = 20;

        // 获取帧率
        float fps = 1.0f / deltaTime;

        // 在屏幕左上角显示帧率
        GUI.Label(new Rect(10, 10, 200, 20), "FPS: " + Mathf.Round(fps), style);
    }
}