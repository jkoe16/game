# Unity 웹 빌드 올리는 곳

PC의 Unity에서 메뉴 **Party World → 웹 빌드**를 누르면 저장소 폴더의 `build/unity-web` 에 웹 파일이 생깁니다.
그 폴더 **안의 내용 전체**(index.html, Build, TemplateData)를 GitHub 웹에서 이 폴더에 끌어다 놓고 커밋하면,
GitHub Actions(**Unity 웹 배포 (PC 빌드)**)가 https://jkoe16.github.io/game/unity/ 에 올립니다.
