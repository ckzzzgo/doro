<#
.SYNOPSIS
    Dororo 一键发版：导出 → 补 .NET → 组装 → 换图标 → 打 zip，每步都带自检。

.DESCRIPTION
    这个脚本存在的理由是发版流程里有两个会「静默出错」的坑：

    1. dotnet 不在 PATH 时，Godot 导出会「成功但少东西」—— 它跳过 .NET 构建，
       只留一行不起眼的 warning，产出的 pck 里没有 .NET 运行时（约 115M 变 39M）。
       这样的包在没装 .NET 的机器上打不开，而你在本机测不出来。
       脚本的对策：不看「导出成功」这句话，直接翻 pck 里有没有 .NET 产物。

    2. 漏掉 rcedit 换图标那步，exe 图标就还是 Godot 默认的。
       脚本的对策：比对换图标前后的哈希，没变就报错。

    另外 rcedit 必须用 1.1.1：2.0 处理不了 Godot 4.4 版权字段里的特殊字符，会失败。

.EXAMPLE
    pwsh -File tools/build_release.ps1

.EXAMPLE
    pwsh -File tools/build_release.ps1 -Godot "D:\Godot\Godot_v4.4.1-stable_mono_win64.exe"
#>
[CmdletBinding()]
param(
    # Godot 4.4.1 **mono（.NET）版**。注意不能用标准版，也不能用 4.7.x。
    [string]$Godot = "$env:USERPROFILE\Desktop\Godot_v4.4.1_mono\Godot_v4.4.1-stable_mono_win64\Godot_v4.4.1-stable_mono_win64_console.exe",

    # rcedit 1.1.1。2.0 不兼容，见上文说明。
    [string]$Rcedit = "$env:USERPROFILE\Desktop\rcedit-x64-1.1.1.exe",

    # dotnet SDK 所在目录，会被临时加进 PATH（Godot 靠它找 SDK）
    [string]$DotnetDir = "C:\Program Files\dotnet",

    # 导出预设名，需与 export_presets.cfg 中的 name 一致
    [string]$Preset = "Windows Desktop",

    # 只组装不打 zip
    [switch]$SkipZip,

    # 把 Godot 的导出日志原样全部打出来（默认只显示进度相关的行）
    [switch]$ShowGodotLog
)

$ErrorActionPreference = 'Stop'
$script:StepNo = 0
$script:StepSw = $null
$script:TotalSw = [System.Diagnostics.Stopwatch]::StartNew()

function Step([string]$msg) {
    if ($script:StepSw) { Took }
    $script:StepNo++
    $script:StepSw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host ""
    Write-Host ("[{0}] {1}" -f $script:StepNo, $msg) -ForegroundColor Cyan
}
function Took() {
    if (-not $script:StepSw) { return }
    Write-Host ("          （上一步耗时 {0:N0} 秒，累计 {1:N0} 秒）" -f `
        $script:StepSw.Elapsed.TotalSeconds, $script:TotalSw.Elapsed.TotalSeconds) -ForegroundColor DarkGray
    $script:StepSw = $null
}
function Ok([string]$msg)   { Write-Host ("     OK   " + $msg) -ForegroundColor Green }
function Info([string]$msg) { Write-Host ("          " + $msg) -ForegroundColor DarkGray }
function Fail([string]$msg) {
    Write-Host ""
    Write-Host ("失败：" + $msg) -ForegroundColor Red
    exit 1
}

function Md5([string]$path) {
    (Get-FileHash -Path $path -Algorithm MD5).Hash
}

# 在文件的前 N 字节里找一个 ASCII 串。Godot 的 pck 把文件路径表放在开头，
# 所以只读前几 MB 就够判断某个资源在不在包里，不必读完 100 多 MB。
function PckContains([string]$pck, [string]$needle, [int]$scanBytes = 8MB) {
    $fs = [System.IO.File]::OpenRead($pck)
    try {
        $len = [Math]::Min($scanBytes, $fs.Length)
        $buf = New-Object byte[] $len
        [void]$fs.Read($buf, 0, $len)
        $text = [System.Text.Encoding]::ASCII.GetString($buf)
        return $text.Contains($needle)
    } finally { $fs.Dispose() }
}

# ---------------------------------------------------------------- 准备与自检

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Step "检查工具与项目"

if (-not (Test-Path $Godot))  { Fail "找不到 Godot：$Godot`n     用 -Godot 指定 mono 版 Godot 4.4.1 的路径。" }
if (-not (Test-Path $Rcedit)) { Fail "找不到 rcedit：$Rcedit`n     必须是 1.1.1 版，2.0 不兼容 Godot 4.4。" }
if ($Rcedit -notmatch '1\.1\.1') {
    Write-Host "     警告  rcedit 文件名里没有 1.1.1，若换图标失败请确认版本" -ForegroundColor Yellow
}

$dotnetExe = Join-Path $DotnetDir "dotnet.exe"
if (-not (Test-Path $dotnetExe)) { Fail "找不到 dotnet：$dotnetExe`n     用 -DotnetDir 指定 .NET SDK 目录。" }

# 关键一步：把 dotnet 加进本进程 PATH。缺了这个，Godot 会静默跳过 .NET 构建。
if ($env:PATH -notlike "*$DotnetDir*") {
    $env:PATH = "$DotnetDir;$env:PATH"
    Info "已把 $DotnetDir 临时加入 PATH"
}
Ok ("dotnet " + (& $dotnetExe --version))

# gd_cubism 的原生库不入库（bin/.gitignore 是 *），新克隆的仓库必须先自行编译
$cubism = "addons\gd_cubism\bin\libgd_cubism.windows.release.x86_64.dll"
if (-not (Test-Path $cubism)) {
    Fail "缺少 Live2D 原生库：$cubism`n     该文件不入库，需先自行编译 gd_cubism 并放到该位置。"
}
Ok "Live2D 原生库就位"

$icon = "app_icon.ico"
if (-not (Test-Path $icon)) { Fail "缺少图标文件：$icon" }

# 版本号以 project.godot 为准，避免脚本里再抄一遍
$verLine = Select-String -Path "project.godot" -Pattern '^config/version="(.+)"' | Select-Object -First 1
if (-not $verLine) { Fail "无法从 project.godot 读取 config/version" }
$version = $verLine.Matches[0].Groups[1].Value
Ok "版本号 $version（取自 project.godot）"

$expVer = Select-String -Path "export_presets.cfg" -Pattern '^application/file_version="(.+)"' | Select-Object -First 1
if ($expVer -and $expVer.Matches[0].Groups[1].Value -ne $version) {
    Write-Host ("     警告  export_presets.cfg 里的 file_version 是 {0}，与 project.godot 的 {1} 不一致" -f `
        $expVer.Matches[0].Groups[1].Value, $version) -ForegroundColor Yellow
}

$exportDir = Join-Path $root "export"
$stageExe  = Join-Path $exportDir "dororo.exe"
$stagePck  = Join-Path $exportDir "dororo.pck"
$pubDir    = Join-Path $exportDir "dotnet_publish"
$outDir    = Join-Path $exportDir "Dororo_v$version"
$zipPath   = Join-Path $exportDir "Dororo_v$version.zip"

[void][System.IO.Directory]::CreateDirectory($exportDir)

# ------------------------------------------------------------------ 导出

Step "Godot 导出（release）"

Write-Host "     这一步通常要 10~15 分钟。" -ForegroundColor Yellow
Write-Host "     其中最久的是 Godot 内部调用 dotnet publish 编译 C# 项目，" -ForegroundColor Yellow
Write-Host "     那段时间它自己不打任何日志，屏幕会静默几分钟，属正常现象。" -ForegroundColor Yellow
Write-Host "     下面每 15 秒会报一次已用时间，能看出它还活着。" -ForegroundColor Yellow
Write-Host ""

# 边流式打印边收集：整段捕获（| Out-String）会让最慢的一步彻底没有输出，
# 干等十几分钟不知道是在跑还是卡死了。这里逐行处理 —— 收进 $lines 供后面做
# 失败特征检查，同时把有意义的行打到屏幕上。
$lines = [System.Collections.Generic.List[string]]::new()
$script:quiet = 0
$beat = [System.Diagnostics.Stopwatch]::StartNew()

& $Godot --headless --path . --export-release $Preset $stageExe 2>&1 | ForEach-Object {
    $line = ([string]$_).TrimEnd()
    $lines.Add($line)

    # 这几类行能说明进展：错误、警告、.NET 发布阶段、打包阶段的起止
    $interesting = $ShowGodotLog -or
        ($line -match 'ERROR|WARNING|dotnet_publish|Publishing|savepack: (begin|end)|export_project|Sdk')

    if ($interesting -and $line -ne '') {
        if ($script:quiet -gt 0) {
            Write-Host ("     |  …（另有 {0} 行细节已折叠）" -f $script:quiet) -ForegroundColor DarkGray
            $script:quiet = 0
        }
        Write-Host ("     |  " + $line) -ForegroundColor DarkGray
    } else {
        $script:quiet++
    }

    # 心跳：Godot 内部编译 C# 的那几分钟一行输出都没有，靠这个证明进程还活着
    if ($beat.Elapsed.TotalSeconds -ge 15) {
        Write-Host ("     |  …… 已用 {0:N0} 秒" -f $script:StepSw.Elapsed.TotalSeconds) -ForegroundColor DarkGray
        $beat.Restart()
    }
}
if ($script:quiet -gt 0) { Write-Host ("     |  …（另有 {0} 行细节已折叠）" -f $script:quiet) -ForegroundColor DarkGray }

$log = $lines -join "`n"

# 不信「导出成功」这句话，直接找已知的失败特征
foreach ($bad in @('.NET Sdk not found', 'Failed to build project', 'Could not load file or assembly')) {
    if ($log -match [regex]::Escape($bad)) {
        Info "Godot 输出片段："
        ($log -split "`n" | Select-String -Pattern 'ERROR|WARNING' | Select-Object -First 8) | ForEach-Object { Info ("  " + $_) }
        Fail "Godot 没能构建 .NET 项目（命中：$bad）。`n     通常是 dotnet 不在 PATH。请确认 -DotnetDir 指向正确的 SDK 目录。"
    }
}
if (-not (Test-Path $stageExe) -or -not (Test-Path $stagePck)) { Fail "导出没有产出 exe/pck" }

$pckMB = [Math]::Round((Get-Item $stagePck).Length / 1MB, 1)
Ok ("产出 dororo.exe / dororo.pck（pck {0} MB）" -f $pckMB)

Step "检查 pck 内容"

# 这两条是上次静默出错的正面照：.NET 产物没打进去，模型文件没打进去
if (-not (PckContains $stagePck "mono/publish")) {
    Fail "pck 里没有 .NET 发布产物（找不到 mono/publish 路径）。`n     说明 Godot 跳过了 .NET 构建，这个包在没装 .NET 的机器上打不开。"
}
Ok ".NET 发布产物已打进 pck"

if (-not (PckContains $stagePck "Doro.moc3")) {
    Fail "pck 里没有 Doro.moc3。`n     Live2D 的非资源文件必须在 export_presets.cfg 的 include_filter 里显式列出。"
}
Ok "Live2D 模型已打进 pck"

# ---------------------------------------------------- 自包含 .NET（散装一份）

Step "dotnet publish（自包含）"

# pck 里那份用于 Godot 内部加载，但原生宿主（coreclr/hostfxr）需要真实文件系统上的
# 副本，所以另外发布一份散装放到 exe 同级目录 —— 这是 v1.0.1 已验证可用的布局。
if (Test-Path $pubDir) { [System.IO.Directory]::Delete($pubDir, $true) }
& $dotnetExe publish "Dororo.csproj" -c ExportRelease -r win-x64 --self-contained true -o $pubDir | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "dotnet publish 失败" }

foreach ($f in @('coreclr.dll','hostfxr.dll','hostpolicy.dll','System.Private.CoreLib.dll','Dororo.dll','Dororo.runtimeconfig.json')) {
    if (-not (Test-Path (Join-Path $pubDir $f))) { Fail "publish 产物缺少 $f" }
}
$rc = Get-Content (Join-Path $pubDir "Dororo.runtimeconfig.json") -Raw
if ($rc -notmatch 'includedFrameworks') {
    Fail "publish 不是自包含的（runtimeconfig 里没有 includedFrameworks），目标机器会需要自行安装 .NET"
}
Ok ("自包含 .NET 就位（{0} 个文件）" -f (Get-ChildItem $pubDir -File).Count)

# ------------------------------------------------------------------ 组装

Step "组装 $outDir"

if (Test-Path $outDir) { [System.IO.Directory]::Delete($outDir, $true) }
[void][System.IO.Directory]::CreateDirectory($outDir)

Copy-Item $stageExe, $stagePck -Destination $outDir
Copy-Item $cubism -Destination $outDir
# 全局键盘/鼠标监听的小助手。它是 .NET Framework 编译的，Windows 自带 4.8，
# 目标机器无需额外安装。程序按 exe 同级目录找它，所以必须散装放这里。
Copy-Item "helpers\DoroInputBridge.exe" -Destination $outDir
Copy-Item (Join-Path $pubDir "*") -Destination $outDir -Recurse

foreach ($f in @('dororo.exe','dororo.pck','libgd_cubism.windows.release.x86_64.dll','DoroInputBridge.exe','coreclr.dll','hostfxr.dll')) {
    if (-not (Test-Path (Join-Path $outDir $f))) { Fail "组装后缺少 $f" }
}
Ok ("{0} 个文件，{1} MB" -f (Get-ChildItem $outDir -File).Count,
    [Math]::Round(((Get-ChildItem $outDir -File -Recurse | Measure-Object Length -Sum).Sum / 1MB), 0))

# ---------------------------------------------------------------- 换图标

Step "rcedit 换图标"

$targetExe = Join-Path $outDir "dororo.exe"
$before = Md5 $targetExe
& $Rcedit $targetExe --set-icon (Join-Path $root $icon)
if ($LASTEXITCODE -ne 0) { Fail "rcedit 返回非零退出码" }
$after = Md5 $targetExe
if ($before -eq $after) {
    Fail "rcedit 没有改动 exe（哈希未变），图标可能仍是 Godot 默认。`n     确认使用的是 rcedit 1.1.1；2.0 对 Godot 4.4 会失败。"
}
Ok ("图标已写入（$($before.Substring(0,8)) -> $($after.Substring(0,8))）")

# ------------------------------------------------------------------ 打包

if ($SkipZip) {
    Step "已跳过打 zip（-SkipZip）"
} else {
    Step "打 zip"
    Compress-Archive -Path $outDir -DestinationPath $zipPath -CompressionLevel Optimal -Force

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $names = $z.Entries | ForEach-Object { $_.FullName }
        foreach ($f in @('dororo.exe','dororo.pck','libgd_cubism.windows.release.x86_64.dll','DoroInputBridge.exe','coreclr.dll','hostfxr.dll')) {
            if ($names -notcontains "Dororo_v$version/$f") { Fail "zip 内缺少 $f" }
        }
        Ok ("{0} 个条目，{1} MB" -f $z.Entries.Count, [Math]::Round((Get-Item $zipPath).Length / 1MB, 1))
    } finally { $z.Dispose() }
}

# ------------------------------------------------------------------ 收尾

Took

Write-Host ""
Write-Host ("全部检查通过（总耗时 {0:N0} 分 {1:N0} 秒）" -f `
    [Math]::Floor($script:TotalSw.Elapsed.TotalMinutes), $script:TotalSw.Elapsed.Seconds) -ForegroundColor Green
Write-Host ("  目录：{0}" -f $outDir)
if (-not $SkipZip) { Write-Host ("  安装包：{0}" -f $zipPath) }
Write-Host ""
Write-Host "下一步（如需发版）：" -ForegroundColor DarkGray
Write-Host ("  gh release create v{0} --target main --title `"Dororo v{0}`" --notes-file <说明文件> `"{1}`"" -f $version, $zipPath) -ForegroundColor DarkGray
Write-Host ""
Write-Host "提醒：导出版与编辑器共用同一个配置文件" -ForegroundColor DarkGray
Write-Host "  %APPDATA%\Godot\app_userdata\Dororo\config.ini" -ForegroundColor DarkGray
Write-Host "  要复现「新用户第一次打开」的效果，先删掉它。" -ForegroundColor DarkGray
