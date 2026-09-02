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

    # 发布仓库。源码和发布都在这一个仓库里。
    #
    # 以前分两个：源码仓库私有，匿名请求它的 API 只会得到 404，所以安装包和
    # version.json 单独放在一个公开的 ckzzzgo/dororo-release。2026-08-26 项目开源，
    # 分两处的理由消失，合并回来，那个仓库连同它的 25 个历史 release 一起删掉了
    # —— 那些 zip 里装着未获许可的素材（Awesome-BongoCat 改色键盘图、微软雅黑），
    # 删掉正是清理的目的。累计下载 45 次，影响可忽略。
    [string]$ReleaseRepo = "ckzzzgo/doro",

    # 导出阶段的看门狗阈值：产物已生成、而 Godot 的 CPU 时间连续这么多秒没增长，
    # 就认定它卡在退出阶段，强制结束。设 45 秒是给正常的收尾留足余量。
    [int]$ExportIdleKillSec = 45,

    # 版本清单的签名私钥。绝不入库（.gitignore 排除 tools/keys/）。
    # 没有它就打不了包 —— 这是故意的，见「给 version.json 签名」那一步的说明。
    [string]$SigningKey = "tools/keys/signing_priv.pem",

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
function Warn([string]$msg) { Write-Host ("     警告  " + $msg) -ForegroundColor Yellow }
function Fail([string]$msg) {
    Write-Host ""
    Write-Host ("失败：" + $msg) -ForegroundColor Red
    exit 1
}

function Md5([string]$path) {
    (Get-FileHash -Path $path -Algorithm MD5).Hash
}

# 在文件的前 N 字节里找一个 ASCII 串。Godot 的 pck 把文件路径表放在开头，
# 所以只读前几 MB 就够判断某个资源【在不在】包里，不必读完 100 多 MB。
#
# 注意这只适合证明「某个东西在」，不能用来证明「某个东西不在」—— 路径表不一定全在
# 前 N 字节内。要证明不存在必须全量扫描，见下面文档素材那条检查。
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

Step "自检（版本号 / README 承诺 / 资源路径）"

# 先跑 tools/selfcheck.ps1 再开始打包。
#
# 它专查那类「代码本身没毛病、所以读代码看不出来」的问题：版本号漏改一处、
# README 写了某功能而它的默认值是关的、代码里的资源路径大小写不对（本机跑没事，
# 打进 pck 就找不到）。这些一旦发出去，用户那边才炸。
#
# 挂在这儿而不是做成 CI：反正每次发版都要跑这个脚本，等于强制过一道关，
# 不用额外维护一套 GitHub Actions（那要下一个多 G 的导出模板，对单人项目不划算）。
& (Join-Path $PSScriptRoot 'selfcheck.ps1')
if ($LASTEXITCODE -ne 0) {
    Fail "自检没过（见上面）。修完再打包 —— 这些错误发出去之后只能靠发新版补救。"
}
Ok "自检通过"

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

# 两个辅助 exe 不由本脚本编译（改了 .cs 要先跑 helpers/build_helpers.ps1 并提交 exe）
foreach ($h in @("helpers\DoroInputBridge.exe", "helpers\DoroUpdater.exe")) {
    if (-not (Test-Path $h)) {
        Fail "缺少辅助程序：$h`n     先运行 pwsh -File helpers/build_helpers.ps1 编译它们。"
    }
}
Ok "辅助程序就位（输入桥 / 更新助手）"

$icon = "assets/icons/app_icon.ico"
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
# 发布包命名约定：纯 ASCII + 平台标识，解压出来的目录名与 zip 同名。
# 不要往文件名里加中文，也不要用「绿色版」这类说法 —— 中文名在下载、解压、跨系统
# 传递时容易乱码或被转义，而下载者真正需要的信息是平台。免配置这件事在发布说明
# 正文里写「解压即用、无需安装运行库」即可。
$pkgName   = "Dororo_v${version}_win"
$outDir    = Join-Path $exportDir $pkgName
$zipPath   = Join-Path $exportDir "$pkgName.zip"

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

# 先删掉上一轮的产物。
#
# 这是下面看门狗那条「产物已生成」判定的前提：旧文件若还在，条件从第 0 秒就成立，
# 而 Godot 编译 C# 的那几分钟父进程 CPU 可能不动（活是子进程 dotnet 在干），
# 看门狗会误杀一个健康的构建。删掉之后「产物存在」才真正等于「本次写完了」。
#
# 顺带让后面那条「导出没有产出 exe/pck」的检查变得可信 —— 否则它可能在看上一轮的文件。
foreach ($old in @($stageExe, $stagePck)) {
    if (Test-Path $old) { Remove-Item $old -Force -ErrorAction SilentlyContinue }
}

# 再清掉上一轮留下的进程。
#
# 这些进程会锁住 %APPDATA%\Godot\app_userdata\Dororo\logs\godot.log，
# 后面第 6 步要删那个文件才能确认「本次运行」的渲染器，删不掉整个构建就失败
# （实测遇到过）。
#
# 只清「本脚本用的那个 Godot 可执行文件」和 dororo.exe —— 按可执行文件名匹配，
# 免得把用户自己开着的 Godot 编辑器一起杀了。
$godotLeaf = [System.IO.Path]::GetFileNameWithoutExtension($Godot)
$stale = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $_.ProcessName -eq $godotLeaf -or $_.ProcessName -eq 'dororo'
})
if ($stale.Count -gt 0) {
    Info ("清掉 {0} 个上一轮残留的进程（会锁住日志文件）" -f $stale.Count)
    $stale | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}
$preGodotIds = @(Get-Process -Name $godotLeaf -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })

# 导出期间的看门狗。
#
# 导出那一行是同步管道调用，Godot 一旦不退出就是无限等 —— 实测遇到过：导出其实
# 已经写完（savepack: end 都打了），进程却挂在退出阶段，CPU 时间 0、内存 3.4 MB、
# 空转 6 分半，只能人工杀。
#
# 不能简单套个总时限：Godot 内部编译 C# 那几分钟一行输出都没有，正常也可能跑十几
# 分钟，硬超时会误杀健康的构建。这里认的是那个卡死的确切特征 ——
#   产物 exe/pck 都已经生成（说明该干的活干完了）
#   而且进程的 CPU 时间连续 $ExportIdleKillSec 秒没有增长（说明它没在干活）
# 两条同时成立才动手。只杀本次新起的进程（$preGodotIds 之外的），不碰别的。
$watchdog = Start-Job -ScriptBlock {
    param($leaf, $exe, $pck, $idleLimit, $skipIds)
    $lastCpu = $null
    $idle = 0
    while ($true) {
        Start-Sleep -Seconds 5
        $p = @(Get-Process -Name $leaf -ErrorAction SilentlyContinue |
               Where-Object { $skipIds -notcontains $_.Id }) | Select-Object -First 1
        if (-not $p) { return 'exited' }                  # 自己退了，正常
        if (-not (Test-Path $exe) -or -not (Test-Path $pck)) { $idle = 0; continue }
        $cpu = $p.CPU
        if ($null -ne $lastCpu -and $cpu -eq $lastCpu) { $idle += 5 } else { $idle = 0 }
        $lastCpu = $cpu
        if ($idle -ge $idleLimit) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            return ('killed after {0}s idle' -f $idle)
        }
    }
} -ArgumentList $godotLeaf, $stageExe, $stagePck, $ExportIdleKillSec, $preGodotIds

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

# 收看门狗。它若真出手过，要说出来 —— 那说明这次构建靠外力才走下去，
# 产物本身通常是好的（判定条件就是「产物已生成」），但这事得让人知道。
$wdResult = $null
if ($watchdog) {
    Stop-Job $watchdog -ErrorAction SilentlyContinue | Out-Null
    $wdResult = Receive-Job $watchdog -ErrorAction SilentlyContinue
    Remove-Job $watchdog -Force -ErrorAction SilentlyContinue | Out-Null
}
if ($wdResult -like 'killed*') {
    Warn ("Godot 导出完之后没有自己退出，看门狗强制结束了它（{0}）。" -f $wdResult)
    Warn "产物已生成，后面的检查照常进行；这属于 Godot 的退出问题，不影响包本身。"
}

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

# 反向检查：文档和草稿素材不该跟着发货。
#
# 这条存在的理由是我曾经栽在这上面：exclude_filter 当时写的是 "docs/*"，而过滤器
# 匹配的是完整的 res://docs/... 路径，前缀对不上，等于没排除。而我验证时只扫了 pck
# 的前 40MB，那些路径恰好在更后面，于是「已确认无残留」的结论是错的，一个 154 个文件
# 的参考模型继续跟着每个用户的下载走。
#
# 所以这里全量扫描，不设上限 —— 慢几秒换一个不会骗人的结论。
$pckText = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($stagePck))
$leaks = [regex]::Matches($pckText, 'res://docs/[ -~]{0,60}') | ForEach-Object { $_.Value } | Select-Object -Unique
if ($leaks.Count -gt 0) {
    Info "例如："
    $leaks | Select-Object -First 5 | ForEach-Object { Info ("  " + $_) }
    Fail ("pck 里混进了 {0} 个 res://docs/ 资源。`n     docs/ 下放的是文档和不参与运行的草稿素材，不该发货。`n     检查 export_presets.cfg 的 exclude_filter —— 它匹配的是带 res:// 前缀的完整路径，`n     所以要写 *docs/* 而不是 docs/*。" -f $leaks.Count)
}
Ok "文档与草稿素材未混进 pck（全量扫描）"

# ------------------------------------------------------------------ 组装

Step "组装 $outDir"

# 这里刻意不再单独跑 dotnet publish、也不往包里放散装的 .NET 运行时。
#
# Godot 导出时已经把自包含的 .NET 发布产物打进了 pck（第 3 步会校验），运行时由 Godot
# 自己解压到 %LOCALAPPDATA%\data_Dororo_windows_x86_64 再加载。实测证据：
#   - 进程里 coreclr/hostfxr/hostpolicy/clrjit/System.Private.CoreLib 全部从上述
#     AppData 目录加载，没有一个来自程序目录；
#   - 来自 C:\Program Files\dotnet 的模块数为 0，即不依赖系统安装的 .NET；
#   - 删掉该 AppData 目录（模拟干净机器）后，仅用下面这 4 个文件仍能正常启动，
#     且该目录会被重新解压出来。
# 也就是说旧布局里那 76MB 散装 DLL 一个都没被加载，纯属死重量：整包因此从
# 约 138MB 降到约 104MB，构建也少一步。
if (Test-Path $outDir) { [System.IO.Directory]::Delete($outDir, $true) }
[void][System.IO.Directory]::CreateDirectory($outDir)

Copy-Item $stageExe, $stagePck -Destination $outDir
Copy-Item $cubism -Destination $outDir
# 两个辅助程序都是 .NET Framework 编译的（Windows 10/11 自带 4.8），目标机器无需
# 额外安装。程序按 exe 同级目录找它们，所以必须散装放这里。
#   DoroInputBridge  全局键盘/鼠标监听
#   DoroUpdater      自动更新时替换安装目录（由主程序拷到 user:// 下再启动）
Copy-Item "helpers\DoroInputBridge.exe" -Destination $outDir
Copy-Item "helpers\DoroUpdater.exe" -Destination $outDir
# GPL-3.0 第 4 条：分发二进制必须附带协议原文。以前 zip 里没有，是实打实的不合规。
Copy-Item "LICENSE" -Destination $outDir
# NOTICE 列的是模型、字体、插件各自的来源和条件 —— 拿到安装包的人也该看得到。
Copy-Item "NOTICE" -Destination $outDir

foreach ($f in @('dororo.exe','dororo.pck','libgd_cubism.windows.release.x86_64.dll','DoroInputBridge.exe','DoroUpdater.exe','LICENSE','NOTICE')) {
    if (-not (Test-Path (Join-Path $outDir $f))) { Fail "组装后缺少 $f" }
}
$fileCount = (Get-ChildItem $outDir -File).Count
if ($fileCount -ne 7) { Fail "组装结果应为 7 个文件，实得 $fileCount 个" }
Ok ("{0} 个文件，{1} MB" -f $fileCount,
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

# ------------------------------------------------------- 实跑一次，验渲染器

# 这一步是踩了坑才加的，说清楚为什么值得花 20 秒：
#
# 桌宠的整个视觉前提是「窗口逐像素透明」。它在 Vulkan 路径上正常，在 OpenGL
# 路径上则依赖驱动 —— NVIDIA 上能用，别的卡上整个窗口会变成不透明黑底，
# 也就是用户看到的「一块黑方块里画着 doro」。
#
# 而这两者可以静默错配：project.godot 里 rendering_method 写的是 mobile，
# 但导出版实际按 config/features 里的渲染器标签走。1.4.1 就是这么发出去的 ——
# 本机跑源码是 Vulkan，一切正常；用户下载的包是 OpenGL，全黑。
# 我们测的从来不是他们跑的那一套，所以本机怎么测都测不出来。
#
# 「导出成功」这句话对此毫无保证，唯一靠得住的办法是把包真的跑起来，
# 读引擎自己打出来的那行驱动信息。日志在用户目录，导出版默认就会写。
Step "实跑一次，确认渲染器"

# 期望 D3D12。1.4.2 之后拿到了用户机器上的实测数据：Vulkan 在混合显卡笔记本
# （Intel 集显输出 + NVIDIA 独显渲染）上做不出窗口透明，整个窗口是黑底；
# D3D12 在同一台机器上正常。详见 project.godot 里 driver.windows 那段注释。
$expectRenderer = 'D3D12'

# 画法也必须验。这次就是驱动对了、画法没对：给用户验证的是 D3D12+Forward+，
# 而项目配置要发的是 D3D12+Forward Mobile —— 两套不同的东西，只查驱动的守卫
# 完全拦不住。（后来让用户把 Forward Mobile 也验了一遍，是好的。）
#
# 期望值从 project.godot 现读，不写死在这里：写死会冒出第二种错配 ——
# 配置改了而守卫忘了跟着改，于是守卫盖章通过一个它压根没在检查的东西。
$mLine = Select-String -Path "project.godot" -Pattern '^renderer/rendering_method="(.+)"' | Select-Object -First 1
if (-not $mLine) { Fail "无法从 project.godot 读取 renderer/rendering_method" }
$methodSetting = $mLine.Matches[0].Groups[1].Value
$expectMethod = switch ($methodSetting) {
    'mobile'           { 'Forward Mobile' }
    'forward_plus'     { 'Forward+' }
    'gl_compatibility' { 'Compatibility' }
}
if (-not $expectMethod) { Fail "project.godot 里的 rendering_method 认不出来：$methodSetting" }
Info "期望渲染路径：$expectRenderer / $expectMethod（画法读自 project.godot）"
$logDir = Join-Path $env:APPDATA "Godot\app_userdata\Dororo\logs"
$curLog = Join-Path $logDir "godot.log"

# 启动前先把当前日志删掉。
#
# 不删有个漏洞：万一这个包压根跑不起来，Godot 不会重建 godot.log，守卫读到的
# 就是【上一次运行】留下的内容 —— 那可能恰好是正确的渲染器，于是守卫盖章通过
# 一个连启动都启动不了的包。这和它原来「读运行后新出现的那个文件」是同一类
# 错误：验证了一个不是本次产物的东西。删掉之后，「没有日志」就明确等于
# 「这个包没跑起来」，不会再有含糊。
if (Test-Path $curLog) { Remove-Item $curLog -Force }

# 不带任何参数 —— 必须和用户双击 exe 的情形完全一致。
# 加 --rendering-driver 之类的参数会连 rendering_method 一起换掉（实测传 vulkan
# 会把 Forward Mobile 变成 Forward+），那就不是用户跑的那一套了 —— 而「测的和
# 用户跑的不是同一套」正是这道守卫要防的事，不能在守卫自己身上再犯一次。
$proc = Start-Process -FilePath $targetExe -PassThru
Start-Sleep -Seconds 15
if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
Stop-Process -Name dororo -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# 本次运行的日志永远是 godot.log。
#
# 这里原来找的是「运行后新出现的那个 .log」，那是错的：Godot 启动时会把【上一次】
# 的 godot.log 改名成 godot<时间戳>.log 存档，再新建 godot.log 写本次。所以
# 「新出现的文件」装的恰恰是上一轮的内容 —— 守卫读到的是上次运行的渲染器，
# 这一版打的包压根没被检查过。实测确认：本次运行是 Vulkan，而那个「新出现的
# 文件」里连驱动行都没有（那是上一次 --headless 跑剩下的）。
# 它至今没报警纯属侥幸，恰好上一轮也是 Vulkan 而已。
if (-not (Test-Path $curLog)) {
    Fail ("跑完了但日志没有被重建，说明这个包没能启动起来。`n" +
          "     期望文件：$curLog")
}

# 驱动信息也不一定在第 2 行 —— Live2D 插件的初始化警告会插进来把它顶下去。
# 按内容找，不按行号找。
$driverMatch = Get-Content $curLog | Select-String 'Vulkan|OpenGL|D3D12|Direct3D' | Select-Object -First 1
if (-not $driverMatch) {
    Fail ("日志里找不到驱动信息行，无法确认渲染器。`n" +
          "     日志：$curLog`n" +
          "     这个包可能压根没启动起来。")
}
$driverLine = $driverMatch.Line.Trim()
if ($driverLine -notmatch [regex]::Escape($expectRenderer)) {
    Fail ("打好的包实际用的【驱动】不对。`n" +
          "     期望包含：$expectRenderer`n" +
          "     实际是：  $driverLine`n" +
          "     用户机器实测：Vulkan 整块黑底，D3D12 正常（Intel 集显输出 +`n" +
          "     NVIDIA 独显渲染的笔记本）。驱动发错就是一块黑底。`n" +
          "     检查 project.godot 的 rendering_device/driver.windows。")
}
if ($driverLine -notmatch [regex]::Escape($expectMethod)) {
    Fail ("驱动对了，但【画法】不对。`n" +
          "     期望包含：$expectMethod   （读自 project.godot 的 rendering_method）`n" +
          "     实际是：  $driverLine`n" +
          "     驱动和画法是分开设的，能各自错配。而 config/features 里的渲染器`n" +
          "     标签会覆盖 rendering_method —— 1.4.1 的黑底就是这么来的。")
}
Ok ("渲染路径正确：$driverLine")

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
        foreach ($f in @('dororo.exe','dororo.pck','libgd_cubism.windows.release.x86_64.dll','DoroInputBridge.exe','DoroUpdater.exe','LICENSE','NOTICE')) {
            if ($names -notcontains "$pkgName/$f") { Fail "zip 内缺少 $f" }
        }
        Ok ("{0} 个条目，{1} MB" -f $z.Entries.Count, [Math]::Round((Get-Item $zipPath).Length / 1MB, 1))
    } finally { $z.Dispose() }

    # ---------------------------------------------------------- version.json

    Step "生成 version.json"

    # 桌宠内的「检查更新」读的是公开发布仓库里的这个文件，而不是源码仓库的 GitHub API
    # —— 源码仓库是私有的，匿名请求它的 API 只会得到 404。
    $sha = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToLower()
    $size = (Get-Item $zipPath).Length
    $verJson = [ordered]@{
        version  = $version
        released = (Get-Item $zipPath).LastWriteTime.ToString("yyyy-MM-dd")
        notes_url = "https://github.com/$ReleaseRepo/releases/tag/v$version"
        package  = [ordered]@{
            name   = Split-Path $zipPath -Leaf
            url    = "https://github.com/$ReleaseRepo/releases/download/v$version/" + (Split-Path $zipPath -Leaf)
            size   = $size
            sha256 = $sha
        }
    }
    $verPath = Join-Path $exportDir "version.json"
    ($verJson | ConvertTo-Json -Depth 4) | Set-Content -Path $verPath -Encoding utf8NoBOM
    Ok ("已写出 {0}" -f $verPath)
    Info ("sha256 = {0}" -f $sha)

    # ---------------------------------------------------------- 给清单签名
    #
    # 必须在这里签，不能留给人工。客户端对 version.json 是 fail-closed 的：没签名
    # 或签名不对，一键更新整条被拒。而 selfcheck 查的是**仓库根目录**那份旧清单，
    # 它一直是签好的 —— 所以「打包 → 通过 → 把这份没签名的覆盖到根目录 → 推送」
    # 一路无人喊停，等下一次打包 selfcheck 才报错，那时所有用户已经坏了一整个版本。
    #
    # 签不了就让整个打包失败，不产出「看着能用其实发出去会坏」的东西。
    Step "给 version.json 签名"
    if (-not (Test-Path $SigningKey)) {
        Fail ("找不到签名私钥 {0}`n     还没做密钥仪式的话先跑：pwsh -File tools/setup_signing_key.ps1`n     没有签名的清单发出去，所有客户端的一键更新会立刻全部失效。" -f $SigningKey)
    }
    & $Godot --headless --path $root --script res://tools/sign_version.gd -- `
        --manifest $verPath --key $SigningKey --quit 2>&1 | Out-Null
    $signed = Get-Content -Raw -Encoding UTF8 $verPath | ConvertFrom-Json
    if (-not $signed.package.PSObject.Properties['signature']) {
        Fail "签名没写进 $verPath —— 检查 tools/sign_version.gd 的输出"
    }
    # 光有 signature 字段不算数，要真过一遍内嵌公钥校验：私钥与客户端里那把公钥
    # 不配对的话，字段在、内容错，一样是全员更新失效。
    $verify = & $Godot --headless --path $root --script res://tools/selfcheck_verify.gd `
        --manifest $verPath --quit 2>&1 | Out-String
    if ($verify -notmatch 'SIGNATURE_VERIFY=OK') {
        Fail "刚签的 version.json 过不了客户端内嵌公钥的校验 —— 私钥和 version_signer.gd 里的公钥不是一对"
    }
    Ok "已签名并通过内嵌公钥校验"
}

# ------------------------------------------------------------------ 收尾

Took

Write-Host ""
Write-Host ("全部检查通过（总耗时 {0:N0} 分 {1:N0} 秒）" -f `
    [Math]::Floor($script:TotalSw.Elapsed.TotalMinutes), $script:TotalSw.Elapsed.Seconds) -ForegroundColor Green
Write-Host ("  目录：{0}" -f $outDir)
if (-not $SkipZip) { Write-Host ("  安装包：{0}" -f $zipPath) }
Write-Host ""
if (-not $SkipZip) {
    Write-Host "下一步（发版，两件事都要做）：" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  1) 把安装包发到公开仓库" -ForegroundColor DarkGray
    # 附件不要加 #显示名 后缀，让 GitHub 直接显示文件名（同样是为了不出现中文名）
    Write-Host ("     gh release create v{0} --repo {1} --title `"Dororo v{0}`" --notes-file <说明文件> `"{2}`"" -f `
        $version, $ReleaseRepo, $zipPath) -ForegroundColor DarkGray
    Write-Host ""
    # 防呆：根目录已有的清单若版本相同但 sha256 不同，说明线上挂的是另一个 zip。
    # 直接复制会让清单和线上附件的校验和对不上，一键更新下载完会拒绝安装。
    $rootVer = Join-Path $root "version.json"
    if (Test-Path $rootVer) {
        try {
            $oldJson = Get-Content $rootVer -Raw | ConvertFrom-Json
            $newJson = Get-Content (Join-Path $exportDir "version.json") -Raw | ConvertFrom-Json
            if ($oldJson.version -eq $newJson.version -and
                $oldJson.package.sha256 -ne $newJson.package.sha256) {
                Write-Host ""
                Warn ("根目录已有 v{0} 的清单，但 sha256 与刚打的包不同。" -f $oldJson.version)
                Warn "zip 带时间戳，同一份代码每次打包字节都不同 —— 这说明线上挂的是另一个 zip。"
                Warn "别直接复制：要么重新上传刚打的这个包，要么保留根目录那份不动。"
            }
        } catch { }
    }

    Write-Host "  2) 更新仓库根目录的 version.json —— 漏了这步，桌宠检查更新仍会说已是最新" -ForegroundColor DarkGray
    Write-Host ("     把 {0} 覆盖到仓库根目录的 version.json 并提交" -f (Join-Path $exportDir "version.json")) -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  3) 源码仓库打 tag（可选，便于对应版本）" -ForegroundColor DarkGray
    Write-Host ("     git tag v{0} && git push origin v{0}" -f $version) -ForegroundColor DarkGray
}
Write-Host ""
Write-Host "提醒：导出版与编辑器共用同一个配置文件" -ForegroundColor DarkGray
Write-Host "  %APPDATA%\Godot\app_userdata\Dororo\config.ini" -ForegroundColor DarkGray
Write-Host "  要复现「新用户第一次打开」的效果，先删掉它。" -ForegroundColor DarkGray
