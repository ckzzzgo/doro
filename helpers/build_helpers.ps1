<#
.SYNOPSIS
    编译 helpers 目录下的辅助程序（DoroInputBridge / DoroUpdater）。

.DESCRIPTION
    这两个 exe 刻意用 .NET Framework 编译，而不是 .NET 8：
    Windows 10/11 自带 .NET Framework 4.8，所以它们在目标机器上零依赖即可运行。
    而主程序那份 .NET 8 是 Godot 自己打进 pck、运行时解压到 AppData 的，
    辅助程序拿不到，因此不能依赖它。

    产出的 exe 直接提交入库（helpers/*.exe），因为发布包需要它们，而目标机器上
    没有编译环境。改了 .cs 之后记得重新跑本脚本并把 exe 一起提交。

.EXAMPLE
    pwsh -File helpers/build_helpers.ps1
#>
[CmdletBinding()]
param(
    # .NET Framework 的 C# 编译器。Windows 自带，无需安装。
    [string]$Csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
)

$ErrorActionPreference = 'Stop'

function Fail([string]$m) { Write-Host ("失败：" + $m) -ForegroundColor Red; exit 1 }
function Ok([string]$m)   { Write-Host ("  OK   " + $m) -ForegroundColor Green }

if (-not (Test-Path $Csc)) {
    Fail "找不到 csc.exe：$Csc`n     用 -Csc 指定 .NET Framework 编译器路径。"
}

$here = $PSScriptRoot
Set-Location $here

# 每个目标：源文件 + 需要引用的程序集
$targets = @(
    @{ Src = "DoroInputBridge.cs"; Refs = @() }
    # ZipFile 在 System.IO.Compression.FileSystem 里，必须显式引用
    @{ Src = "DoroUpdater.cs";     Refs = @("System.IO.Compression.dll", "System.IO.Compression.FileSystem.dll") }
)

foreach ($t in $targets) {
    $src = $t.Src
    if (-not (Test-Path $src)) { Fail "缺少源文件 $src" }
    $exe = [System.IO.Path]::ChangeExtension($src, ".exe")

    $before = if (Test-Path $exe) { (Get-FileHash $exe -Algorithm MD5).Hash } else { "" }

    $args = @("/nologo", "/target:exe", "/optimize+", "/platform:x64", "/out:$exe")
    foreach ($r in $t.Refs) { $args += "/reference:$r" }
    $args += $src

    Write-Host ""
    Write-Host ("编译 {0} -> {1}" -f $src, $exe) -ForegroundColor Cyan
    $out = & $Csc @args 2>&1
    if ($LASTEXITCODE -ne 0) {
        $out | ForEach-Object { Write-Host ("     " + $_) -ForegroundColor Red }
        Fail "$src 编译失败"
    }
    $out | Where-Object { $_ -match 'warning' } | ForEach-Object { Write-Host ("     " + $_) -ForegroundColor Yellow }

    if (-not (Test-Path $exe)) { Fail "$exe 未生成" }
    $after = (Get-FileHash $exe -Algorithm MD5).Hash
    $size = (Get-Item $exe).Length
    if ($before -eq $after -and $before -ne "") {
        Ok ("$exe 未变化（$size 字节）")
    } else {
        Ok ("$exe 已更新（$size 字节，$($after.Substring(0,8))）")
    }
}

Write-Host ""
Write-Host "全部编译完成。记得把改动的 exe 一并提交入库。" -ForegroundColor Green
