# 3D PARTY WORLD — 새 Windows PC 개발 환경 설치
#
# 사용법 (프로젝트 폴더에서 PowerShell):
#   powershell -ExecutionPolicy Bypass -File tools\setup_windows.ps1
#   powershell -ExecutionPolicy Bypass -File tools\setup_windows.ps1 -SkipTemplates   # 웹 빌드 안 할 때 (1.2GB 다운로드 생략)
#
# 하는 일
#   1. Godot 4.7.2 (에디터 + 콘솔) → %USERPROFILE%\Godot\Godot_v4.7.2-stable_win64\
#   2. 웹 내보내기 템플릿 → %APPDATA%\Godot\export_templates\4.7.2.stable\ (web_* 만 추출)
#   3. 에셋 임포트
#   4. Node.js / gh / git 설치 여부 안내
# 이미 설치된 항목은 건너뛴다. 로그인(gh auth login, npx firebase-tools login)은 직접 해야 한다.
param([switch]$SkipTemplates)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # Invoke-WebRequest 진행 표시가 다운로드를 매우 느리게 함
Add-Type -AssemblyName System.IO.Compression.FileSystem

$Version = "4.7.2"
$Base = "https://github.com/godotengine/godot/releases/download/$Version-stable"
$Root = Split-Path -Parent $PSScriptRoot
$GodotDir = Join-Path $env:USERPROFILE "Godot\Godot_v$Version-stable_win64"
$GodotConsole = Join-Path $GodotDir "Godot_v$Version-stable_win64_console.exe"
$TplDir = Join-Path $env:APPDATA "Godot\export_templates\$Version.stable"
$Tmp = Join-Path $env:TEMP "3dpw_setup"
New-Item -ItemType Directory -Force $Tmp | Out-Null

# 1. Godot
if (Test-Path $GodotConsole) {
    Write-Host "[1/4] Godot $Version 이미 있음: $GodotDir"
} else {
    Write-Host "[1/4] Godot $Version 다운로드 (약 86MB)..."
    $zip = Join-Path $Tmp "godot.zip"
    Invoke-WebRequest "$Base/Godot_v$Version-stable_win64.exe.zip" -OutFile $zip
    New-Item -ItemType Directory -Force $GodotDir | Out-Null
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $GodotDir)
    Remove-Item $zip
}

# 2. 웹 내보내기 템플릿 (web_* 만)
if ($SkipTemplates) {
    Write-Host "[2/4] 내보내기 템플릿 생략 (-SkipTemplates)"
} elseif (Test-Path (Join-Path $TplDir "web_nothreads_release.zip")) {
    Write-Host "[2/4] 웹 내보내기 템플릿 이미 있음: $TplDir"
} else {
    Write-Host "[2/4] 내보내기 템플릿 다운로드 (약 1.2GB, 시간이 걸립니다)..."
    $tpz = Join-Path $Tmp "templates.tpz"
    Invoke-WebRequest "$Base/Godot_v$Version-stable_export_templates.tpz" -OutFile $tpz
    New-Item -ItemType Directory -Force $TplDir | Out-Null
    $z = [System.IO.Compression.ZipFile]::OpenRead($tpz)
    try {
        foreach ($e in $z.Entries) {
            if ($e.FullName -match '^templates/(web_.*\.zip|version\.txt)$') {
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, (Join-Path $TplDir $e.Name), $true)
            }
        }
    } finally { $z.Dispose() }
    Remove-Item $tpz
}

# 3. 에셋 임포트
Write-Host "[3/4] 에셋 임포트..."
& $GodotConsole --headless --path $Root --import *> (Join-Path $Tmp "import.log")

# 4. 도구 안내
Write-Host "[4/4] 도구 확인"
foreach ($t in @(@("git", "https://git-scm.com"), @("node", "https://nodejs.org (테스트·Firebase 배포용)"), @("gh", "https://cli.github.com (선택)"))) {
    if (Get-Command $t[0] -ErrorAction SilentlyContinue) { Write-Host "  OK  $($t[0])" } else { Write-Host "  없음 $($t[0]) -> $($t[1])" }
}

$bashPath = "/" + $GodotConsole.Substring(0, 1).ToLower() + $GodotConsole.Substring(2).Replace("\", "/")
Write-Host ""
Write-Host "완료. Godot 에디터: $GodotDir\Godot_v$Version-stable_win64.exe"
Write-Host "Git Bash 에서 테스트/배포 전에:"
Write-Host "  export GODOT=`"$bashPath`""
Write-Host "남은 일 (직접): gh auth login  /  npx firebase-tools login (웹 배포할 때)"
