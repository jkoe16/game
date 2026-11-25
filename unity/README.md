# 3D PARTY WORLD — Unity 판 (이전 중)

Godot 판(저장소 루트)을 Unity로 옮기는 중입니다. Godot 판은 Unity 판이 따라잡을 때까지 그대로 운영합니다.

## 지금 단계: 1단계 혼자 이동
- 캐릭터 이동·점프·계단·경사 (`Assets/Scripts/Player/PlayerBody.cs`, 수치는 Godot `player_body.gd`와 동일)
- 3인칭 카메라: 수평 즉시 따라가기, 수직만 부드럽게 (`Assets/Scripts/Camera/ThirdPersonCamera.cs`)
- PC 키보드·마우스 / 휴대폰 터치 조이스틱 (`Assets/Scripts/UI/TouchControls.cs`)
- 씬 파일 없이 재생하면 연습장이 자동으로 만들어짐 (`Assets/Scripts/Main/Bootstrap.cs`, `PracticeMap.cs`)

## 열어 보기
1. Unity Hub 설치 → Unity 6 LTS 설치 (모듈: WebGL Build Support, Linux Dedicated Server Build Support, Android Build Support)
2. Unity Hub → **Add → Add project from disk** → 이 `unity` 폴더 선택 → 버전은 설치한 Unity 6 LTS
3. 열리면 아무 씬(기본 SampleScene 또는 File → New Scene)에서 ▶ 재생
   - "새 Input System을 켤까요?" 창이 뜨면 Yes (어느 쪽이든 동작함)

## 웹사이트로 올리기 (자동)
`unity/` 를 고쳐서 푸시하면 GitHub Actions(**Unity 웹 배포**)가 웹 빌드를 만들어 **https://jkoe16.github.io/game/unity/** 에 올립니다.
처음 한 번만 GitHub 저장소 → Settings → Secrets and variables → Actions 에 비밀값 3개를 넣어야 합니다:
`UNITY_EMAIL`, `UNITY_PASSWORD`, `UNITY_LICENSE`(Unity Hub 로그인한 PC의 `C:\ProgramData\Unity\Unity_lic.ulf` 내용 전체).
에디터에서 직접 만들 때는 메뉴 **Party World → 웹 빌드** (결과: 저장소의 `build/unity-web`).

## 조작
| | PC | 휴대폰 |
|---|---|---|
| 이동 | WASD / 방향키 (Shift = 걷기) | 왼쪽 화면 누르고 끌기 |
| 점프 | Space | 오른쪽 아래 동그라미 |
| 카메라 | 화면 클릭 후 마우스, 휠 줌, Esc = 마우스 풀기 | 오른쪽 화면 드래그, 두 손가락 줌 |

왼쪽 위에 속도·fps·바닥 여부가 보입니다 (Godot 판과 이동 느낌 비교용).

## 연습장 구성
- 앞쪽: 0.3m 계단(오를 수 있음), 0.4m 계단(못 오름), 30° 경사(오름), 55° 경사(미끄러짐)
- 뒤쪽: 높이 1.2 / 1.6 / 1.9m 점프 발판, 간격이 점점 넓어지는 징검다리
- 오른쪽: 긴 벽, 앞쪽 멀리: 떨어지면 처음 자리로

## 다음 단계
2단계 광장 + 온라인(전용 서버, 예측·보정) → 3단계 로그인 → 4단계 미니게임 5종. 전체 계획은 이전 계획 문서 참고.
