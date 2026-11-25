using System;
using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace PartyWorld.EditorTools
{
    /// <summary>
    /// 웹(WebGL) 빌드. GitHub Actions(GameCI)가 자동으로 부르고, 에디터 메뉴 "Party World → 웹 빌드"로도 실행 가능.
    /// 씬 파일이 없어도 빈 씬을 만들어 넣는다 (게임 내용은 Bootstrap 이 실행할 때 만든다).
    /// GitHub Pages 는 압축 헤더를 못 붙이므로 Gzip + 브라우저에서 풀기(decompression fallback)로 빌드.
    /// </summary>
    public static class BuildScript
    {
        const string ScenePath = "Assets/Scenes/Main.unity";

        [MenuItem("Party World/웹 빌드")]
        public static void BuildWeb()
        {
            string outPath = GetArg("-customBuildPath") ?? Path.GetFullPath(Path.Combine(Application.dataPath, "../../unity-webbuild"));

            if (!File.Exists(ScenePath))
            {
                Directory.CreateDirectory(Path.GetDirectoryName(ScenePath));
                var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
                EditorSceneManager.SaveScene(scene, ScenePath);
            }

            // 도형·재질을 실행 중에 코드로 만들기 때문에 빌드가 셰이더를 "안 쓰는 것"으로 보고 빼 버린다 → 화면이 분홍색.
            EnsureAlwaysIncluded("Standard");

            PlayerSettings.companyName = "jkoe16";
            PlayerSettings.productName = "3D PARTY WORLD";
            PlayerSettings.WebGL.compressionFormat = WebGLCompressionFormat.Gzip;
            PlayerSettings.WebGL.decompressionFallback = true;
            PlayerSettings.WebGL.dataCaching = true;
            PlayerSettings.runInBackground = true;

            var options = new BuildPlayerOptions
            {
                scenes = new[] { ScenePath },
                locationPathName = outPath,
                target = BuildTarget.WebGL,
                options = BuildOptions.None,
            };
            var report = BuildPipeline.BuildPlayer(options);
            Debug.Log($"[BuildScript] 결과: {report.summary.result}, 크기 {report.summary.totalSize / 1048576f:0.0} MB → {outPath}");
            if (Application.isBatchMode)
                EditorApplication.Exit(report.summary.result == UnityEditor.Build.Reporting.BuildResult.Succeeded ? 0 : 1);
        }

        static void EnsureAlwaysIncluded(string shaderName)
        {
            var shader = Shader.Find(shaderName);
            if (shader == null) return;
            var gs = AssetDatabase.LoadAssetAtPath<UnityEngine.Rendering.GraphicsSettings>("ProjectSettings/GraphicsSettings.asset");
            if (gs == null) return;
            var so = new SerializedObject(gs);
            var list = so.FindProperty("m_AlwaysIncludedShaders");
            for (int i = 0; i < list.arraySize; i++)
                if (list.GetArrayElementAtIndex(i).objectReferenceValue == shader) return;
            list.InsertArrayElementAtIndex(list.arraySize);
            list.GetArrayElementAtIndex(list.arraySize - 1).objectReferenceValue = shader;
            so.ApplyModifiedProperties();
            AssetDatabase.SaveAssets();
        }

        static string GetArg(string name)
        {
            string[] args = Environment.GetCommandLineArgs();
            for (int i = 0; i < args.Length - 1; i++)
                if (args[i] == name && !string.IsNullOrEmpty(args[i + 1])) return args[i + 1];
            return null;
        }
    }
}
