using UnityEngine;

namespace PartyWorld
{
    /// <summary>
    /// 내 캐릭터 조작 (Godot scripts/player/local_player_controller.gd 의 오프라인 부분 이식).
    /// 매 물리 틱(60Hz): 입력 모으기 → PlayerBody.Simulate().
    /// 온라인 예측·보정(서버와 맞추기)은 3단계에서 이 클래스에 추가한다.
    /// </summary>
    public class LocalPlayerController : MonoBehaviour
    {
        public PlayerBody body;
        public ThirdPersonCamera cam;
        /// <summary>모바일 가상 조이스틱 등 외부 입력 (x = 오른쪽, y = 앞). 키보드와 합산.</summary>
        public Vector2 externalMove;
        public bool externalJump;
        public float killHeight = -25f;
        public Vector3 spawnPoint = new Vector3(0f, 1f, 0f);

        uint _seq;
        int _jumpHold;
        bool _jumpQueued;

        void Update()
        {
            // 키 누름은 화면 프레임에서 잡아 두었다가 다음 물리 틱에 넘긴다 (틱 사이 입력을 놓치지 않게)
            if (InputReader.JumpPressedThisFrame() || externalJump)
                _jumpQueued = true;
            externalJump = false;
        }

        void FixedUpdate()
        {
            if (body == null) return;
            PlayerInput input = GatherInput();
            _seq++;
            input.seq = _seq;
            body.Simulate(input, Time.fixedDeltaTime);
            if (body.transform.position.y < killHeight)
                body.Teleport(spawnPoint);
        }

        PlayerInput GatherInput()
        {
            var inp = new PlayerInput();
            Vector2 v = Vector2.ClampMagnitude(InputReader.Move() + externalMove, 1f);
            if (InputReader.WalkHeld()) v *= 0.5f;
            // 카메라 방향 기준 → 월드 방향
            float yaw = cam != null ? cam.yaw : 0f;
            float s = Mathf.Sin(yaw), c = Mathf.Cos(yaw);
            Vector2 world = new Vector2(v.x * c + v.y * s, -v.x * s + v.y * c);
            inp.SetMove(world);

            if (_jumpQueued)
            {
                _jumpHold = PlayerBody.JumpHoldTicks;
                _jumpQueued = false;
            }
            inp.jump = _jumpHold > 0;
            _jumpHold = Mathf.Max(_jumpHold - 1, 0);
            if (inp.jump && body.velocity.y > 2f)
                _jumpHold = 0; // 이미 뛰어올랐으면 남은 유지 입력은 버린다
            return inp;
        }
    }
}
