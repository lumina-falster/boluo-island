# 菠萝岛桌宠在线安装器：下载到 %LOCALAPPDATA%\BoluoPet 并启动
$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:LOCALAPPDATA 'BoluoPet'
New-Item -ItemType Directory -Force -Path $dir | Out-Null

$sources = @{
    'boluo_pet.ps1' = @(
        'https://cdn.jsdelivr.net/gh/lumina-falster/boluo-island@main/pet/boluo_pet.ps1',
        'https://raw.githubusercontent.com/lumina-falster/boluo-island/main/pet/boluo_pet.ps1',
        'https://ghproxy.net/https://raw.githubusercontent.com/lumina-falster/boluo-island/main/pet/boluo_pet.ps1'
    )
    'pineapple.ico' = @(
        'https://cdn.jsdelivr.net/gh/lumina-falster/boluo-island@main/pet/pineapple.ico',
        'https://raw.githubusercontent.com/lumina-falster/boluo-island/main/pet/pineapple.ico',
        'https://ghproxy.net/https://raw.githubusercontent.com/lumina-falster/boluo-island/main/pet/pineapple.ico'
    )
}

foreach ($name in $sources.Keys) {
    $dst = Join-Path $dir $name
    $done = $false
    foreach ($u in $sources[$name]) {
        try {
            Invoke-WebRequest -Uri $u -OutFile $dst -TimeoutSec 30 -UseBasicParsing
            $done = $true
            break
        } catch { continue }
    }
    if (-not $done) { throw "下载失败：$name（网络不通？改用 zip 离线包）" }
    Unblock-File $dst -ErrorAction SilentlyContinue
    Write-Host "已下载 $name"
}

Write-Host '启动桌宠…'
Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',(Join-Path $dir 'boluo_pet.ps1')
Write-Host '完成！小菠萝已出现在右下角，桌面也会出现快捷方式。'
