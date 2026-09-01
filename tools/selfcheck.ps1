<#
.SYNOPSIS
    发版前的自检：查那些「眼睛看不出来、但发出去会出事」的毛病。

.DESCRIPTION
    这个项目原来只有一道关：打包脚本。它只在发版时跑，平时改完代码不知道有没有改坏，
    要等发版、甚至等用户反馈才知道。这个脚本补上那一步——几秒钟跑完，随时能跑。

    它专挑「代码本身没毛病、所以读代码看不出来」的那类问题。真实案例两个：

      1. README 写着「全屏打游戏我自己躲开」，可那个开关出厂是关的。关着的时候
         检测定时器压根不跑，功能等于不存在。代码逻辑一行错都没有，是默认值不对。
         用户全屏打游戏被弹回桌面，1.4.7 才修。→ 现在由「承诺 vs 默认值」这项拦住。

      2. 版本号散在三个文件里。漏改一个，用户的自动更新会一直提示有新版、或者
         下载到对不上的包。→ 由「版本号一致」这项拦住。

.EXAMPLE
    pwsh -File tools/selfcheck.ps1
    pwsh -File tools/selfcheck.ps1 -WithGodot     # 顺带让 Godot 解析一遍所有脚本（慢十几秒）
#>
[CmdletBinding()]
param(
    # 加上就多跑一步：让 Godot 完整导入一次，确认所有脚本能解析、资源能导入。
    [switch]$WithGodot,

    [string]$Godot = "$env:USERPROFILE\Desktop\Godot_v4.4.1_mono\Godot_v4.4.1-stable_mono_win64\Godot_v4.4.1-stable_mono_win64_console.exe"
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$script:Failed = 0
$script:Warned = 0

function Ok([string]$m)   { Write-Host "     OK   $m" -ForegroundColor Green }
function Warn([string]$m) { Write-Host "     警告 $m" -ForegroundColor Yellow; $script:Warned++ }
function Bad([string]$m)  { Write-Host "     不对 $m" -ForegroundColor Red;   $script:Failed++ }
function Section([string]$m) { Write-Host ""; Write-Host "[$m]" -ForegroundColor Cyan }

function Read-Text([string]$p) { Get-Content -Raw -Encoding UTF8 $p }


# ============================================================ README 的承诺 vs 代码里的默认值
#
# 加新条目就往这个表里加。判据是「README 里写了这句话，那代码里这个默认值就必须是这样」。
$PromiseChecks = @(
    @{
        Promise = '全屏让路'
        File    = 'scripts/gd/ui/setting/setting_system.gd'
        Pattern = 'set_prop\(&"auto_hide",\s*true\)'
        Why     = '功能列表里写了她会在别的程序全屏时躲开。这个开关默认关掉的话，检测定时器根本不跑，功能等于不存在。'
    },
    @{
        Promise = '看你打字'
        File    = 'scripts/gd/ui/setting/setting_interact.gd'
        Pattern = 'set_prop\(&"keyboard_mode",\s*true\)'
        Why     = '功能列表里写了她会跟着你敲键盘。默认关掉就没人看得到这个功能。'
    }
)


Write-Host ""
Write-Host "Doro 自检" -ForegroundColor White
Write-Host "  $root" -ForegroundColor DarkGray

# ------------------------------------------------------------ 1. 版本号一致
Section "1. 版本号"

$presets = Read-Text 'export_presets.cfg'
$godotCfg = Read-Text 'project.godot'

$fileVer = [regex]::Match($presets, 'application/file_version="([^"]+)"').Groups[1].Value
$prodVer = [regex]::Match($presets, 'application/product_version="([^"]+)"').Groups[1].Value
$cfgVer  = [regex]::Match($godotCfg, 'config/version="([^"]+)"').Groups[1].Value

if ($fileVer -and $fileVer -eq $prodVer -and $fileVer -eq $cfgVer) {
    Ok "export_presets.cfg 与 project.godot 都是 $fileVer"
} else {
    Bad "版本号对不上：file=$fileVer product=$prodVer project.godot=$cfgVer"
}

# version.json 是发布清单，正常流程里它落后一个版本（先升号 → 打包 → 发布 → 再更新它）。
# 所以这里只提示，不算失败；但它自己内部必须自洽。
if (Test-Path 'version.json') {
    $vj = Get-Content -Raw -Encoding UTF8 'version.json' | ConvertFrom-Json
    if ($vj.package.name -like "*$($vj.version)*" -and $vj.package.url -like "*$($vj.version)*") {
        Ok "version.json 内部自洽（$($vj.version)）"
    } else {
        Bad "version.json 里 version=$($vj.version)，但包名或下载地址里的版本号跟它不一致"
    }
    if ($vj.version -ne $fileVer) {
        Warn "version.json 是 $($vj.version)，源码已经是 $fileVer —— 发版后记得更新它，否则用户检查更新拿不到新版"
    }
}

# ------------------------------------------------------------ 2. README 承诺 vs 默认值
Section "2. README 说有的功能，默认是不是真开着"

$readme = Read-Text 'README.md'
foreach ($c in $PromiseChecks) {
    if ($readme -notmatch [regex]::Escape($c.Promise)) {
        Warn "README 里没找到「$($c.Promise)」，这条检查可能过期了"
        continue
    }
    if (-not (Test-Path $c.File)) {
        Bad "找不到 $($c.File)，「$($c.Promise)」这条没法检查"
        continue
    }
    if ((Read-Text $c.File) -match $c.Pattern) {
        Ok "「$($c.Promise)」默认开着"
    } else {
        Bad "README 写了「$($c.Promise)」，但 $($c.File) 里的默认值不是开着的`n          $($c.Why)"
    }
}

# ------------------------------------------------------------ 3. 代码里写的资源路径
Section "3. 代码里写的资源路径是不是都存在"

# 必须区分大小写，不能用 Test-Path。
#
# Windows 的文件系统不区分大小写，Test-Path 认为 DORO_keyboard.png 和
# doro_keyboard.png 是同一个文件 —— 编辑器里也照样能跑。但导出成 pck 之后，
# 里面的路径是按真实文件名写死的，大小写不符运行时就找不到。
# 也就是说这类错误「本机一切正常，发出去就炸」，正是最该拦的一种。
#
# 所以拿 git 记录的真实文件名建一张表，做区分大小写的比对。
$realFiles = [System.Collections.Generic.HashSet[string]]::new(
    [string[]](git ls-files), [System.StringComparer]::Ordinal)

$missing = [ordered]@{}
$checked = 0
foreach ($f in (git ls-files | Where-Object { $_ -match '\.(gd|cs|tscn|tres)$' })) {
    if (-not (Test-Path $f)) { continue }
    # tools/ 是开发脚本，里面有正则字符串会被误当成路径
    if ($f -like 'tools/*') { continue }
    foreach ($m in [regex]::Matches((Read-Text $f), 'res://([^"''\s\)]+)')) {
        $p = $m.Groups[1].Value.TrimEnd('.', ',')
        if ($p -match '[%{\[]') { continue }   # 运行时拼出来的路径，静态查不了
        $checked++
        if ($realFiles.Contains($p)) { continue }
        if ($missing.Contains($p)) { continue }
        if (Test-Path $p) {
            # 文件在，但名字对不上 —— 十有八九是大小写写错了。把真名找出来告诉他。
            $real = (git ls-files | Where-Object { $_ -ieq $p } | Select-Object -First 1)
            if ($real) {
                $missing[$p] = "$f`n          大小写不符：真实文件名是 $real。本机跑没事，打进包就找不到。"
            } else {
                $missing[$p] = "$f（文件在磁盘上但没入库，别人 clone 下来就没有）"
            }
        } else {
            $missing[$p] = $f
        }
    }
}
if ($missing.Count -eq 0) {
    Ok "$checked 条路径全部存在（区分大小写）"
} else {
    foreach ($k in $missing.Keys) { Bad "$k  （写在 $($missing[$k])）" }
}

# ------------------------------------------------------------ 4. 打包必需的文件
Section "4. 打包要用到的文件在不在"

foreach ($f in @('LICENSE', 'NOTICE', 'assets/icons/app_icon.ico', 'helpers/DoroInputBridge.exe')) {
    if (Test-Path $f) { Ok $f } else { Bad "缺 $f —— 打包会失败或者发出去的包少东西" }
}

# ------------------------------------------------------------ 5. version.json 签名
Section "5. 版本清单签名"

if (-not (Test-Path 'version.json')) {
    Bad "缺 version.json —— 客户端检查更新靠它，没有就全盘认不出新版"
} else {
    $vj = Get-Content -Raw -Encoding UTF8 'version.json' | ConvertFrom-Json
    if ($vj.package.PSObject.Properties['signature']) {
        Ok "version.json 带签名（$($vj.package.signature.Substring(0,12))…）"
        # 签名内容能否过内嵌公钥校验，这步要 Godot 跑真加解密，放在 -WithGodot 里。
        $script:NeedSigVerify = $true
    } else {
        Bad "version.json 的 package 里没有 signature 字段`n         客户端会自动更新校验签名，没签名的清单会被整条拒绝，用户只能手动下载。`n         发版前先跑 tools/sign_version.gd。"
    }
}

# 私钥绝不能入库。真进了，任何人都能伪造下载清单，内嵌公钥照样验过，防线作废。
if (Test-Path 'tools/keys') {
    $trackedPriv = git ls-files 'tools/keys'
    if ($trackedPriv) {
        Bad "tools/keys/ 下有文件被 git 跟踪：$($trackedPriv -join ', ')`n         私钥进了仓库，伪造签名的门槛就没了。git rm --cached 并从 .gitignore 排除。"
    } else {
        Ok "tools/keys/ 存在但未被 git 跟踪（私钥不在仓库里）"
    }
} else {
    Warn "没有 tools/keys/ —— 确认发布机上有签名私钥（不应入库）"
}

# ------------------------------------------------------------ 6. 可选：让 Godot 过一遍
if ($WithGodot) {
    Section "6. 让 Godot 解析所有脚本（并校验签名）"
    if (-not (Test-Path $Godot)) {
        Warn "找不到 Godot（$Godot），跳过"
    } else {
        $out = & $Godot --headless --path . --import 2>&1 | Out-String
        $errs = $out -split "`n" | Where-Object {
            $_ -match 'SCRIPT ERROR|Parse Error|^ERROR' -and $_ -notmatch 'Cubism|register_types|WASAPI|audio|PSO caching'
        }
        if ($errs) { $errs | Select-Object -First 8 | ForEach-Object { Bad $_.Trim() } }
        else { Ok "所有脚本解析通过，资源导入无错" }

        # 真校验一遍 version.json 的签名。签名是「安全相关字段」的规范串 + 内嵌公钥，
        # 只有 Godot 能跑这道加解密，check_mirrors / 上面的字段存在性都替代不了。
        $sig = & $Godot --headless --path . --script res://tools/selfcheck_verify.gd --quit 2>&1 | Out-String
        if ($sig -match 'SIGNATURE_VERIFY=OK') {
            Ok "version.json 签名通过内嵌公钥校验"
        } else {
            Bad "version.json 签名校验不通过——发出去用户会整条更新被拒"
        }
    }
}

# ------------------------------------------------------------ 收尾
Write-Host ""
if ($script:Failed -gt 0) {
    Write-Host "有 $($script:Failed) 项不对，$($script:Warned) 项提示" -ForegroundColor Red
    exit 1
}
if ($script:Warned -gt 0) {
    Write-Host "全部通过（另有 $($script:Warned) 项提示）" -ForegroundColor Yellow
} else {
    Write-Host "全部通过" -ForegroundColor Green
}
exit 0
