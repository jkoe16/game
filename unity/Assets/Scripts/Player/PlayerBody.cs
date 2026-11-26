using UnityEngine;

namespace PartyWorld
{
    /// <summary>
    /// 플레이어 물리 몸체 (Godot scripts/player/player_body.gd 이식).
    /// 서버(권한 시뮬레이션)와 클라이언트(예측)가 같은 Simulate()로 이동을 계산한다.
    /// Simulate() 한 번 = 입력 하나 = 물리 틱 하나 (60Hz). 이 함수의 결과가 곧 게임 규칙이다.
    /// 모습(캐릭터 모델)은 Visual 자식에 두고, 틱 사이를 보간해 부드럽게 보여 준다.
    /// </summary>
    [RequireComponent(typeof(CharacterController))]
    public class PlayerBody : MonoBehaviour
    {
        // ── 이동 수치: Godot 판과 똑같이 유지 (이동 느낌의 기준) ──
        public const float WalkSpeed = 6.5f;
        public const float AccelGround = 60f;
        /// <summary>멈출 때·반대로 돌 때 감속 (높을수록 미끄러지지 않고 딱 선다)</summary>
        public const float DecelGround = 120f;
        /// <summary>키를 뗐을 때 감속 (걷던 속도에서 약 0.08m, 0.025초 만에 선다)</summary>
        public const float DecelStop = 260f;
        public const float AccelAir = 18f;
        public const float StunFriction = 4f;
        public const float Gravity = 26f;
        public const float MaxFallSpeed = 40f;
        public const float JumpVelocity = 10f;
        public const float CoyoteTime = 0.1f;
        /// <summary>점프 입력 여유 틱 수(≈0.12초). 입력 쪽(LocalPlayerController)에서 처리.</summary>
        public const int JumpHoldTicks = 7;
        public const float StepHeight = 0.35f;
        public const float BoostMult = 1.6f;
        public const float JumpBoostMult = 1.3f;
        public const float FloorSnap = 0.3f;
        public const float FloorMaxAngle = 46f;

        public int peerId;
        public Vector3 velocity;
        public float airTime;
        /// <summary>바라보는 방향 (라디안, Unity Y축 회전. 0 = +Z)</summary>
        public float facingYaw;
        public float stunTime;
        public float boostTime;
        public float jumpBoostTime;
        public float shieldTime;
        /// <summary>카운트다운 등에서 이동 금지 (모드가 설정)</summary>
        public bool frozen;
        /// <summary>올라서 있는 이동 발판 번호 (-1 = 없음). 맵의 PostMove 가 정한다.</summary>
        public int floorMover = -1;

        /// <summary>모습 루트 (캐릭터 모델). 몸체 위치와 따로 보간해서 움직인다.</summary>
        public Transform visual;

        CharacterController _cc;
        bool _onFloor;
        Vector3 _prevPos, _currPos;

        public CharacterController Controller => _cc;
        public bool IsOnFloor => _onFloor;

        void Awake()
        {
            _cc = GetComponent<CharacterController>();
            _cc.height = 1.6f;
            _cc.radius = 0.4f;
            _cc.center = new Vector3(0f, 0.8f, 0f);
            _cc.stepOffset = StepHeight;
            _cc.slopeLimit = FloorMaxAngle;
            _cc.skinWidth = 0.02f;
            _cc.minMoveDistance = 0f;
            _prevPos = _currPos = transform.position;
        }

        public void Simulate(PlayerInput input, float delta)
        {
            Vector2 move = input.GetMove();
            bool wantJump = input.jump;
            if (frozen || stunTime > 0f)
            {
                move = Vector2.zero;
                wantJump = false;
            }
            stunTime = Mathf.Max(stunTime - delta, 0f);
            boostTime = Mathf.Max(boostTime - delta, 0f);
            jumpBoostTime = Mathf.Max(jumpBoostTime - delta, 0f);
            shieldTime = Mathf.Max(shieldTime - delta, 0f);
            bool onFloor = _onFloor;

            Vector2 horiz = new Vector2(velocity.x, velocity.z);
            bool moving = move.sqrMagnitude > 0.0001f;
            float topSpeed = WalkSpeed * (boostTime > 0f ? BoostMult : 1f);

            // 최고 속도를 넘은 경우(부스트 끝 등)에만 감속. 0.05 여유가 없으면 부동소수 오차로
            // 이 분기에 걸려 키를 떼도 계속 미끄러졌다 (Godot 판에서 고친 버그).
            if (horiz.magnitude > topSpeed + 0.05f && stunTime <= 0f && onFloor && moving)
            {
                horiz = Vector2.ClampMagnitude(horiz, Mathf.Max(topSpeed, horiz.magnitude - DecelGround * delta));
            }
            else if (stunTime > 0f)
            {
                horiz = Vector2.MoveTowards(horiz, move * topSpeed, StunFriction * delta);
            }
            else if (onFloor && moving)
            {
                // 입력 방향 성분과 옆 성분을 따로: 옆으로 흐르는 속도는 브레이크처럼 없애고 입력 방향으로 가속
                // → 90° 꺾을 때도 비스듬히 미끄러지거나 속도가 푹 꺼지지 않는다.
                Vector2 dir = move.normalized;
                float along = Vector2.Dot(horiz, dir);
                Vector2 side = Vector2.MoveTowards(horiz - dir * along, Vector2.zero, DecelGround * delta);
                along = Mathf.MoveTowards(along, move.magnitude * topSpeed, (along >= 0f ? AccelGround : DecelGround) * delta);
                horiz = dir * along + side;
            }
            else
            {
                horiz = Vector2.MoveTowards(horiz, move * topSpeed, (onFloor ? DecelStop : AccelAir) * delta);
            }

            float vy = velocity.y;
            if (onFloor)
            {
                airTime = 0f;
                if (vy < 0f) vy = 0f;
            }
            else
            {
                airTime += delta;
                vy = Mathf.Max(vy - Gravity * delta, -MaxFallSpeed);
            }

            bool jumped = false;
            if (wantJump && airTime <= CoyoteTime)
            {
                vy = JumpVelocity * (jumpBoostTime > 0f ? JumpBoostMult : 1f);
                airTime = CoyoteTime + 0.001f; // 코요테 구간 소진 → 공중 2단 점프 불가
                jumped = true;
            }

            // 바라보는 방향은 입력 방향 그대로. 부드럽게 도는 건 모습 쪽에서 한 번만.
            if (move.sqrMagnitude > 0.0004f)
                facingYaw = Mathf.Atan2(move.x, move.y);

            // 바닥에 서 있으면 아래로 살짝 붙여서(floor snap) 내리막·계단 내려갈 때 공중에 뜨지 않게 한다.
            Vector3 motion = new Vector3(horiz.x, vy, horiz.y) * delta;
            if (onFloor && !jumped && vy <= 0f)
                motion.y -= FloorSnap;

            Vector3 start = transform.position;
            CollisionFlags flags = _cc.Move(motion);
            Vector3 moved = transform.position - start;

            _onFloor = (flags & CollisionFlags.Below) != 0;
            // 스냅으로 내려가 봤는데 바닥이 없으면(절벽) 스냅만큼 되돌려 떨어지기 시작
            if (!_onFloor && onFloor && !jumped && vy <= 0f)
            {
                _cc.Move(new Vector3(0f, vy * delta - moved.y, 0f));
            }
            if ((flags & CollisionFlags.Above) != 0 && vy > 0f)
                vy = 0f;

            // 벽에 막힌 만큼 수평 속도를 줄인다 (Godot move_and_slide와 같은 효과)
            Vector2 actual = new Vector2(moved.x, moved.z) / delta;
            if ((flags & CollisionFlags.Sides) != 0 && actual.magnitude < horiz.magnitude)
                horiz = actual;

            velocity = new Vector3(horiz.x, vy, horiz.y);
            _prevPos = _currPos;
            _currPos = transform.position;
        }

        /// <summary>넉백: 서버·클라이언트가 같은 조건에서 호출</summary>
        public void Knock(Vector3 impulse, float stun)
        {
            if (shieldTime > 0f && stun > 0f) return; // 보호막: 넘어지지 않음
            velocity = impulse;
            stunTime = Mathf.Max(stunTime, stun);
            airTime = CoyoteTime + 0.001f;
            _onFloor = false;
        }

        /// <summary>이동 발판에 실려 함께 움직임 (Simulate 직전에 맵이 호출)</summary>
        public void Carry(Vector3 delta)
        {
            if (delta.sqrMagnitude > 0f) _cc.Move(delta);
        }

        public void Teleport(Vector3 pos)
        {
            _cc.enabled = false;
            transform.position = pos;
            _cc.enabled = true;
            velocity = Vector3.zero;
            airTime = 0f;
            stunTime = boostTime = jumpBoostTime = shieldTime = 0f;
            _onFloor = false;
            floorMover = -1;
            _prevPos = _currPos = pos;
        }

        /// <summary>
        /// 서버가 알려 준 상태로 되돌린다 (온라인 보정). 위치·속도·타이머를 그대로 받고, 보간은 끊지 않는다.
        /// </summary>
        public void SetNetState(Vector3 pos, Vector3 vel, float air, float stun, float boost, float jumpBoost, float shield, int mover, bool grounded)
        {
            _cc.enabled = false;
            transform.position = pos;
            _cc.enabled = true;
            velocity = vel;
            airTime = air;
            stunTime = stun;
            boostTime = boost;
            jumpBoostTime = jumpBoost;
            shieldTime = shield;
            floorMover = mover;
            _onFloor = grounded;
            _currPos = pos;
        }

        /// <summary>보정 직후 모습만 이전 자리에서 따라오게 하는 오프셋 (빠르게 0으로 줄어든다)</summary>
        public Vector3 visualOffset;

        /// <summary>순간이동처럼 크게 바뀌었을 때: 틱 보간도 끊는다</summary>
        public void SnapInterpolation()
        {
            _prevPos = _currPos = transform.position;
            visualOffset = Vector3.zero;
        }

        /// <summary>틱 사이를 보간한 위치 (카메라·모습이 사용). 물리 틱보다 화면 프레임이 잦아도 부드럽다.</summary>
        public Vector3 InterpolatedPosition
        {
            get
            {
                float a = Mathf.Clamp01((Time.time - Time.fixedTime) / Time.fixedDeltaTime);
                return Vector3.Lerp(_prevPos, _currPos, a);
            }
        }

        const float TurnSpeed = 20f;

        void LateUpdate()
        {
            if (visual == null) return;
            if (visualOffset != Vector3.zero)
            {
                visualOffset = Vector3.Lerp(visualOffset, Vector3.zero, 1f - Mathf.Exp(-28f * Time.deltaTime));
                if (visualOffset.sqrMagnitude < 0.005f * 0.005f) visualOffset = Vector3.zero;
            }
            visual.position = InterpolatedPosition + visualOffset;
            float target = facingYaw * Mathf.Rad2Deg;
            float cur = visual.eulerAngles.y;
            visual.rotation = Quaternion.Euler(0f, Mathf.LerpAngle(cur, target, 1f - Mathf.Exp(-TurnSpeed * Time.deltaTime)), 0f);
        }
    }
}
