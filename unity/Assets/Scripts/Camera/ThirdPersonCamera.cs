using UnityEngine;

namespace PartyWorld
{
    /// <summary>
    /// 3인칭 카메라 (Godot scripts/camera/third_person_camera.gd 이식).
    /// 수평은 캐릭터를 즉시 따라가고 수직만 느리게 따라간다 (점프 때 덜 흔들리게).
    /// 마우스/터치 회전, 휠·핀치 줌, 벽에 막히면 앞으로 당김, 조작이 없으면 캐릭터 뒤로 천천히 복귀.
    /// </summary>
    public class ThirdPersonCamera : MonoBehaviour
    {
        const float PivotHeight = 1.3f;
        const float MinDistance = 2.5f;
        const float MaxDistance = 10f;
        const float PitchMin = -1.25f;
        const float PitchMax = 0.45f;
        const float ProbeRadius = 0.25f;

        public PlayerBody target;
        public float mouseSensitivity = 0.0028f;
        public float touchSensitivity = 0.006f;
        public float autoRecenterDelay = 1.6f;
        /// <summary>터치 화면에서는 마우스 잠금을 쓰지 않는다</summary>
        public bool touchMode;

        /// <summary>라디안. 0 = +Z 방향을 바라봄</summary>
        public float yaw;
        public float pitch = -0.32f;
        float _distance = 6f;
        float _targetDistance = 6f;
        Vector3 _follow;
        float _idleInputTime;
        bool _snapped;
        Camera _cam;

        void Awake()
        {
            _cam = GetComponent<Camera>();
            if (_cam == null) _cam = gameObject.AddComponent<Camera>();
            _cam.fieldOfView = 68f; // Godot 은 세로 FOV 기준이 같다
            _cam.farClipPlane = 400f;
            _cam.nearClipPlane = 0.05f;
        }

        void Update()
        {
            if (UiKit.MenuOpen)
            {
                if (Cursor.lockState == CursorLockMode.Locked) Cursor.lockState = CursorLockMode.None;
                return;
            }
            if (!touchMode)
            {
                if (Cursor.lockState == CursorLockMode.Locked)
                {
                    Vector2 d = InputReader.MouseDelta();
                    if (d != Vector2.zero) RotateBy(new Vector2(d.x, -d.y), mouseSensitivity);
                }
                if (InputReader.MouseClicked() && !UiKit.PointerOverUi()) Cursor.lockState = CursorLockMode.Locked;
                if (InputReader.EscapePressed()) Cursor.lockState = CursorLockMode.None;
                float sc = InputReader.ScrollY();
                if (sc > 0.01f) Zoom(-0.6f);
                else if (sc < -0.01f) Zoom(0.6f);
            }
        }

        void LateUpdate()
        {
            if (target == null) return;
            float dt = Time.deltaTime;
            Vector3 tp = target.InterpolatedPosition + Vector3.up * PivotHeight;
            if (!_snapped || Vector3.Distance(_follow, tp) > 15f)
            {
                _follow = tp;
                _snapped = true;
            }
            // 수평은 그대로(즉시), 수직만 부드럽게. 수평까지 늦게 따라가면 키를 뗀 뒤에도 화면이 흘러
            // 캐릭터가 밀리는 것처럼 보였다 (Godot 판에서 고친 문제).
            _follow.x = tp.x;
            _follow.z = tp.z;
            _follow.y = Mathf.Lerp(_follow.y, tp.y, 1f - Mathf.Exp(-7f * dt));

            _idleInputTime += dt;
            bool moving = new Vector2(target.velocity.x, target.velocity.z).magnitude > 1f;
            if (moving && _idleInputTime > autoRecenterDelay)
                yaw = Mathf.LerpAngle(yaw * Mathf.Rad2Deg, target.facingYaw * Mathf.Rad2Deg, 1f - Mathf.Exp(-1.2f * dt)) * Mathf.Deg2Rad;

            _distance = Mathf.Lerp(_distance, _targetDistance, 1f - Mathf.Exp(-10f * dt));

            // pitch 음수 = 위에서 내려다봄 (Godot 과 같은 의미)
            Quaternion rot = Quaternion.Euler(-pitch * Mathf.Rad2Deg, yaw * Mathf.Rad2Deg, 0f);
            Vector3 back = rot * Vector3.back;
            float dist = _distance;
            int worldMask = ~(1 << PartyLayers.Player);
            if (Physics.SphereCast(_follow, ProbeRadius, back, out RaycastHit hit, _distance, worldMask, QueryTriggerInteraction.Ignore))
                dist = Mathf.Max(hit.distance - 0.05f, 0.3f);
            transform.SetPositionAndRotation(_follow + back * dist, rot);
        }

        public void RotateBy(Vector2 deltaPx, float sensitivity)
        {
            yaw += deltaPx.x * sensitivity;
            pitch = Mathf.Clamp(pitch - deltaPx.y * sensitivity, PitchMin, PitchMax);
            _idleInputTime = 0f;
        }

        public void Zoom(float step)
        {
            _targetDistance = Mathf.Clamp(_targetDistance + step, MinDistance, MaxDistance);
        }
    }

    public static class PartyLayers
    {
        /// <summary>플레이어 캡슐 레이어 (카메라 충돌에서 제외). Unity 기본 빈 레이어 중 하나.</summary>
        public const int Player = 8;
    }
}
