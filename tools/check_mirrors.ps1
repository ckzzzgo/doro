<#
.SYNOPSIS
    在「没有梯子」的网络条件下，实测自动更新的各个下载源到底通不通。

.DESCRIPTION
    自动更新的候选源名单写在 update_message_box.gd 的 MIRRORS 里。那份名单是在
    一台开着 TUN 的机器上验出来的 —— 只能证明镜像内容正确、不重定向，**证明不了
    墙内直连能连上它们**。这个脚本就是补这一课。

    所以第一步一定是「确认直连 GitHub 真的断了」。这一步不过，后面全是白测：
    隧道没关干净的话，所有请求照样从隧道出去，结论仍旧是假的。

    名单直接从 .gd 里读，不在这儿抄一遍 —— 抄一遍迟早两处对不上。

.EXAMPLE
    # 先把 Clash / v2ray 的 TUN 和系统代理都关掉，然后：
    pwsh -File tools/check_mirrors.ps1
#>
[CmdletBinding()]
param(
    # 测速时下载多少字节（默认 3 MB，够看出快慢又不浪费别人带宽）
    [int]$SpeedBytes = 3145728,
    # 每个请求的超时秒数
    [int]$TimeoutSec = 20,

    # 直连仍然通的时候也硬要往下测（结论不作数，只是想看一眼）
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Line($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ""; Write-Host $m -ForegroundColor Cyan }

# ---------------------------------------------------------------- 名单从代码里读
$gd = Get-Content -Raw -Encoding UTF8 'scripts/gd/ui/setting/update_message_box.gd'
$m = [regex]::Match($gd, 'const MIRRORS := \[(.*?)\]', 'Singleline')
if (-not $m.Success) { Write-Host "在 update_message_box.gd 里没找到 MIRRORS" -ForegroundColor Red; exit 1 }
$mirrors = @()
foreach ($q in [regex]::Matches($m.Groups[1].Value, '"([^"]*)"')) { $mirrors += $q.Groups[1].Value }

$versionUrl = [regex]::Match($gd, 'const VERSION_URL := "([^"]+)"').Groups[1].Value
$pkgPrefix = [regex]::Match($gd, 'const PACKAGE_URL_PREFIX := "([^"]+)"').Groups[1].Value

Write-Host ""
Write-Host "下载源实测" -ForegroundColor White
Line "  名单读自 scripts/gd/ui/setting/update_message_box.gd（共 $($mirrors.Count) 个，第一个空串=直连）"

# ---------------------------------------------------------------- 0. 先确认隧道真的关了
Head "第一步：确认直连 GitHub 确实不通"
Line "  这一步不过，后面全部作废 —— 隧道没关干净的话测的还是隧道。" DarkGray

$directOk = $false
try {
    $r = Invoke-WebRequest -Uri $versionUrl -TimeoutSec $TimeoutSec -UseBasicParsing -ErrorAction Stop
    if ($r.StatusCode -eq 200) { $directOk = $true }
} catch { }

if ($directOk) {
    Write-Host "     直连 GitHub 是通的。" -ForegroundColor Yellow
    Write-Host "     说明梯子还开着（Clash 的 TUN 模式关掉了吗？系统代理呢？）。" -ForegroundColor Yellow
    Write-Host "     现在测出来的「镜像能用」不能作数 —— 那是隧道帮的忙。" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "     关干净之后重跑。要是你确实想在通的情况下看一眼，加 -Force 跑。" -ForegroundColor DarkGray
    if (-not $Force) { exit 2 }
} else {
    Write-Host "     OK   直连不通 —— 这正是没梯子的用户看到的情况，可以继续测。" -ForegroundColor Green
}

# ---------------------------------------------------------------- 1. 逐个源试 version.json
Head "第二步：各个源能不能取到 version.json"

$works = @()
$payloads = @{}
foreach ($p in $mirrors) {
    $name = if ($p -eq "") { "直连 GitHub" } else { ([uri]$p).Host }
    $url = $p + $versionUrl
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $r = Invoke-WebRequest -Uri $url -TimeoutSec $TimeoutSec -UseBasicParsing -ErrorAction Stop
        $sw.Stop()
        $body = $r.Content
        $j = $body | ConvertFrom-Json
        if (-not $j.version -or -not $j.package.url) { throw "内容不像 version.json" }
        if (-not $j.package.url.StartsWith($pkgPrefix)) { throw "下载地址不指向本仓库 Release：$($j.package.url)" }
        Write-Host ("     OK   {0,-22} {1,5} ms   版本 {2}" -f $name, $sw.ElapsedMilliseconds, $j.version) -ForegroundColor Green
        $works += $p
        $payloads[$p] = $body
    } catch {
        $sw.Stop()
        Write-Host ("     ×    {0,-22} {1}" -f $name, $_.Exception.Message.Split("`n")[0]) -ForegroundColor DarkGray
    }
}

# 交叉比对：直连不通时没有「原件」可比，但多个镜像若给出完全一致的内容，
# 至少说明没有哪一个在单独做手脚。
if ($payloads.Count -ge 2) {
    $vals = @($payloads.Values | ForEach-Object { $_.Trim() } | Select-Object -Unique)
    if ($vals.Count -eq 1) {
        Write-Host "     OK   能通的这几个源，返回内容完全一致" -ForegroundColor Green
    } else {
        Write-Host "     警告 各源返回的内容不一致！有源在改东西，别用。" -ForegroundColor Red
    }
}

if ($works.Count -eq 0) {
    Write-Host ""
    Write-Host "  一个源都不通。这个方案在这条网络下救不了自动更新。" -ForegroundColor Red
    Write-Host "  下一步只能是自己找国内能访问的地方放包（云存储 / 已备案的服务器 / Gitee）。" -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------- 2. 测下载速度
Head "第三步：能通的源，下载有多快（各取 $([math]::Round($SpeedBytes/1MB,1)) MB）"

$vj = $payloads[$works[0]] | ConvertFrom-Json
$pkgUrl = $vj.package.url
Line "  测的文件：$($vj.package.name)（完整 $([math]::Round($vj.package.size/1MB,1)) MB）" DarkGray

foreach ($p in $works) {
    $name = if ($p -eq "") { "直连 GitHub" } else { ([uri]$p).Host }
    $tmp = [System.IO.Path]::GetTempFileName()
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        # 只取前面一段，不整包拉 —— 别人的免费服务，省着点用
        $req = [System.Net.HttpWebRequest]::Create($p + $pkgUrl)
        $req.Timeout = $TimeoutSec * 1000
        $req.ReadWriteTimeout = $TimeoutSec * 1000
        $req.AddRange(0, $SpeedBytes - 1)
        $resp = $req.GetResponse()
        $inS = $resp.GetResponseStream()
        $outS = [System.IO.File]::Create($tmp)
        $buf = New-Object byte[] 65536
        $got = 0
        while (($n = $inS.Read($buf, 0, $buf.Length)) -gt 0) {
            $outS.Write($buf, 0, $n); $got += $n
            if ($got -ge $SpeedBytes) { break }
        }
        $outS.Close(); $inS.Close(); $resp.Close()
        $sw.Stop()
        $mbps = ($got / 1MB) / [math]::Max($sw.Elapsed.TotalSeconds, 0.001)
        $full = $vj.package.size / 1MB / [math]::Max($mbps, 0.001)
        Write-Host ("     OK   {0,-22} {1,6:N2} MB/s   照这个速度整包要 {2:N0} 分 {3:N0} 秒" `
            -f $name, $mbps, [math]::Floor($full / 60), ($full % 60)) -ForegroundColor Green
    } catch {
        $sw.Stop()
        Write-Host ("     ×    {0,-22} 下载失败：{1}" -f $name, $_.Exception.Message.Split("`n")[0]) -ForegroundColor DarkGray
    } finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "结论：$($works.Count) / $($mirrors.Count) 个源在这条网络下可用。" -ForegroundColor White
if ($works -contains "") {
    Write-Host "  （其中直连也通 —— 再确认一下梯子是不是真关了）" -ForegroundColor Yellow
}
Write-Host "  能下载的源要是一个都没有，就得换托管方式，不是改代码能解决的。" -ForegroundColor DarkGray
