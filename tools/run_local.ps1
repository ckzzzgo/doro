<#
    本地试跑 Doro —— 默认跑【打好的包】，也就是用户下载到的那个东西。

    为什么默认跑包而不是跑源码：
      这两者不是同一个东西。1.4.1 就栽在这上面 —— 跑源码走 Vulkan 渲染器，
      一切正常；用户下载的包走 OpenGL，整个窗口变成不透明黑底。我们本机测了
      无数遍都没发现，因为测的从来不是他们跑的那一套。
      凡是「只在导出版生效」的设置，跑源码永远盖不住。

    为什么还留着跑源码这条路：
      导出一次要 10 分钟（几乎全花在 Godot 导出那一步，后面所有步骤合起来才 24 秒）。
      改一行 GDScript 就等 10 分钟没法干活。所以改代码的循环用源码，
      改完要下结论之前用包过一遍。

    这个脚本的核心职责是：绝不让你在不知情的情况下测一个旧包。
    只要源码比包新，它就拦住问一句，而不是默默启动。
#>
[CmdletBinding()]
param(
    # 直接跑源码，不问
    [switch]$Source,
    # 直接跑包，即使包比源码旧也不问
    [switch]$Package,
    [string]$Godot = "$env:USERPROFILE\Desktop\Godot_v4.4.1_mono\Godot_v4.4.1-stable_mono_win64\Godot_v4.4.1-stable_mono_win64_console.exe",
    [string]$DotnetDir = "C:\Program Files\dotnet"
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

function Info($m) { Write-Host ("     " + $m) -ForegroundColor DarkGray }
function Ok($m)   { Write-Host ("  OK  " + $m) -ForegroundColor Green }
function Warn($m) { Write-Host ("  !   " + $m) -ForegroundColor Yellow }
function Die($m)  { Write-Host ""; Write-Host ("失败：" + $m) -ForegroundColor Red; Write-Host ""; Read-Host "回车退出" | Out-Null; exit 1 }

if (-not (Test-Path (Join-Path $repo "project.godot"))) {
    Die "这里不像项目目录（找不到 project.godot）：`n     $repo"
}

# ---------------------------------------------------------------- 找包

# 只认当前版本号对应的那个包。不用「最新目录」是因为那会在版本刚 bump、还没导出时
# 悄悄跑上一个版本的包 —— 恰好是最容易看错的时候。
$verLine = Select-String -Path (Join-Path $repo "project.godot") -Pattern '^config/version="(.+)"' | Select-Object -First 1
if (-not $verLine) { Die "读不出 project.godot 里的 config/version" }
$version = $verLine.Matches[0].Groups[1].Value

$pkgExe = Join-Path $repo ("export\Dororo_v{0}_win\dororo.exe" -f $version)
$pkgExists = Test-Path $pkgExe

# ---------------------------------------------------------------- 比新旧

# 源码里任何一个文件比包的 exe 新，就说明这个包不含你最近的改动。
# 排除的目录：.godot 是导入缓存、export 是产物、obj/bin 是 C# 中间产物，
# 它们都会被构建过程本身touch，拿来比会永远显示「源码更新」。
$newestSrc = $null
if ($pkgExists) {
    # tools\ 和 docs\ 不进包，改它们不影响跑起来是什么样，不该触发警告。
    # 其余一律参与比较 —— 宁可多问一句，也别漏掉真的改动。
    $skip = @('\.godot\', '\export\', '\obj\', '\bin\', '\.git\', '\tools\', '\docs\')
    $newestSrc = Get-ChildItem $repo -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $p = $_.FullName
            -not ($skip | Where-Object { $p -like "*$_*" })
        } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

$mode = $null
if ($Source)  { $mode = 'source' }
elseif ($Package) { $mode = 'package' }
elseif (-not $pkgExists) {
    Write-Host ""
    Warn ("还没有 {0} 的包" -f $version)
    Info ("期望位置：export\Dororo_v{0}_win\dororo.exe" -f $version)
    Info "先跑一次 pwsh -File tools/build_release.ps1 打包（约 10 分钟），"
    Info "或者现在直接跑源码看效果。"
    Write-Host ""
    $c = Read-Host "  跑源码吗？(Y=跑源码 / N=退出)"
    if ($c -match '^[Yy]') { $mode = 'source' } else { exit 0 }
}
elseif ($newestSrc -and $newestSrc.LastWriteTime -gt (Get-Item $pkgExe).LastWriteTime) {
    Write-Host ""
    Warn "你的代码比这个包新 —— 包里没有你最近的改动。"
    Info ("最近改的：{0}" -f $newestSrc.FullName.Substring($repo.Length + 1))
    Info ("          {0:yyyy-MM-dd HH:mm:ss}" -f $newestSrc.LastWriteTime)
    Info ("包的时间：{0:yyyy-MM-dd HH:mm:ss}" -f (Get-Item $pkgExe).LastWriteTime)
    Write-Host ""
    Info "1 = 跑源码       改动是你刚写的，但渲染路径可能和发布版不同"
    Info "2 = 还是跑这个包  测的不是你刚改的东西，只适合看旧行为"
    Info "3 = 退出，先重新打包"
    Write-Host ""
    switch (Read-Host "  选哪个") {
        '1' { $mode = 'source' }
        '2' { $mode = 'package' }
        default { exit 0 }
    }
}
else {
    $mode = 'package'
}

# ---------------------------------------------------------------- 跑

Get-Process dororo -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

if ($mode -eq 'package') {
    Write-Host ""
    Ok ("跑打好的包 v{0} —— 和用户下载到的完全一致" -f $version)
    Info $pkgExe
    Write-Host ""
    Info "关掉窗口或从托盘退出。这一版的日志在："
    Info "$env:APPDATA\Godot\app_userdata\Dororo\logs"
    Write-Host ""
    $p = Start-Process -FilePath $pkgExe -PassThru
    $p.WaitForExit()
    Write-Host ""
    Info "Doro 已退出。启动时用的渲染器："
    $log = Get-ChildItem "$env:APPDATA\Godot\app_userdata\Dororo\logs" -Filter *.log -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($log) {
        $l = Get-Content $log.FullName -TotalCount 2
        if ($l.Count -ge 2) { Info ("  " + $l[1]) }
    }
    exit 0
}

# 源码模式
if (-not (Test-Path $Godot)) { Die "找不到 Godot：`n     $Godot" }
$env:PATH = "$DotnetDir;$env:PATH"

Write-Host ""
Info "[1/2] 编译 C# ..."
Push-Location $repo
try {
    & dotnet build -v quiet -nologo
    if ($LASTEXITCODE -ne 0) { Die "C# 编译失败，看上面的错误。" }

    Write-Host ""
    Warn "这是源码模式，走的渲染路径可能和发布包不同。"
    Info "要下结论之前，用包再过一遍（打包后重新双击这个脚本即可）。"
    Write-Host ""
    Info "[2/2] 启动 Doro ..."
    Write-Host ""
    & $Godot --path .
}
finally { Pop-Location }

Write-Host ""
Info "Doro 已退出。"
