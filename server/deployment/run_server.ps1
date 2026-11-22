# 전용 게임 서버 실행 (헤드리스, Windows PowerShell)
# 사용법: .\server\deployment\run_server.ps1 [-Port 7777] [-MaxPlayers 8] [-Map lobby_plaza] [-Godot <경로>]
param(
    [int]$Port = 7777,
    [int]$MaxPlayers = 8,
    [string]$Map = "lobby_plaza",
    [string]$Godot = "$env:USERPROFILE\Desktop\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
)
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
& $Godot --headless --path $root -- --server "--port=$Port" "--max-players=$MaxPlayers" "--map=$Map"
