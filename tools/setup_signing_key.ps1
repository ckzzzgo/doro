<#
.SYNOPSIS
    刻一枚新的「版本清单签名」私章，一条命令做完全套。

.DESCRIPTION
    做四件事，中间不需要你复制粘贴任何东西：

      1. 生成一对新密钥，私钥写进 tools/keys/signing_priv.pem（已被 .gitignore 排除）
      2. 把配套的公钥写进 scripts/gd/utils/version_signer.gd
      3. 用新私钥重新签 version.json
      4. 真跑一遍校验，确认这三样确实是配套的

    私钥全程只出现在那个文件里 —— 不打屏幕、不进剪贴板、不进 git。屏幕上只会
    显示公钥的指纹，那个是可以公开的。

    **这枚章必须由你自己生成、自己保管。** 谁拿到私钥，谁就能伪造出一份让所有
    Doro 客户端都信任的「新版本」清单。

    **生成完立刻离线备份。** 私钥丢了的话，已经装了签名版的用户会永久失去一键
    更新 —— 你没法再签出他们认的清单，他们只能手动下载。备份到 U 盘或密码管理器，
    不要放网盘、不要发微信。

.EXAMPLE
    pwsh -File tools/setup_signing_key.ps1

.EXAMPLE
    # 换章（旧的泄露了）。注意：已发出去的客户端认的是旧公钥，换章后它们
    # 会全部失去一键更新，得让他们手动装一次新版。
    pwsh -File tools/setup_signing_key.ps1 -Force
#>
[CmdletBinding()]
param(
    [string]$Godot = "$env:USERPROFILE\Desktop\Godot_v4.4.1_mono\Godot_v4.4.1-stable_mono_win64\Godot_v4.4.1-stable_mono_win64_console.exe",

    [string]$KeyPath = "tools/keys/signing_priv.pem",

    # 已经有私钥时也强行重新生成。会作废所有已发出去的客户端的一键更新。
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$signer = 'scripts/gd/utils/version_signer.gd'

function Ok([string]$m)   { Write-Host "     OK   $m" -ForegroundColor Green }
function Info([string]$m) { Write-Host "          $m" -ForegroundColor DarkGray }
function Die([string]$m)  { Write-Host ""; Write-Host "  $m" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "刻一枚版本清单签名私章" -ForegroundColor White

if (-not (Test-Path $Godot)) { Die "找不到 Godot：$Godot（用 -Godot 指定）" }

# ---------------------------------------------------------------- 防手滑
if ((Test-Path $KeyPath) -and (-not $Force)) {
    Write-Host ""
    Write-Host "  $KeyPath 已经存在。" -ForegroundColor Yellow
    Write-Host "  重新生成会作废它 —— 所有已经装了签名版的用户会立刻失去一键更新，" -ForegroundColor Yellow
    Write-Host "  因为他们客户端里认的是旧公钥。确定要换的话加 -Force。" -ForegroundColor Yellow
    exit 2
}

# ---------------------------------------------------------------- 1. 生成
Write-Host ""
Write-Host "[1/4] 生成密钥对" -ForegroundColor Cyan
New-Item -ItemType Directory -Force (Split-Path $KeyPath) | Out-Null

$genOut = & $Godot --headless --path $root --script res://tools/gen_signing_key.gd -- `
    --out $KeyPath --quit 2>&1 | Out-String

if (-not (Test-Path $KeyPath)) { Die "私钥没生成出来。Godot 输出：`n$genOut" }

# 从输出里抠出公钥块。私钥不在输出里（gen_signing_key.gd 只把它写文件），
# 所以这段文本可以放心处理。
$m = [regex]::Match($genOut, '-----BEGIN PUBLIC KEY-----[\s\S]*?-----END PUBLIC KEY-----')
if (-not $m.Success) { Die "没能从输出里取到公钥。Godot 输出：`n$genOut" }
$pub = ($m.Value -replace "`r", "").Trim()

Ok "私钥已写入 $KeyPath"
Info "这个文件被 .gitignore 排除，不会进 git。现在就去备份它。"

# ---------------------------------------------------------------- 2. 换公钥
Write-Host ""
Write-Host "[2/4] 把公钥写进客户端" -ForegroundColor Cyan

$src = Get-Content -Raw -Encoding UTF8 $signer
$pattern = 'const PUBLIC_KEY_PEM := "[\s\S]*?-----END PUBLIC KEY-----"'
if ($src -notmatch $pattern) { Die "在 $signer 里找不到 PUBLIC_KEY_PEM 常量" }
# $pub 里可能有 $ 之类会被 .NET 替换语法吃掉的字符，用 MatchEvaluator 原样塞回去
$new = [regex]::Replace($src, $pattern, { param($x) 'const PUBLIC_KEY_PEM := "' + $pub + '"' })
Set-Content -Path $signer -Value $new -Encoding utf8NoBOM -NoNewline

$fp = (Get-FileHash -InputStream ([IO.MemoryStream]::new(
    [Text.Encoding]::UTF8.GetBytes($pub))) -Algorithm SHA256).Hash.Substring(0, 16).ToLower()
Ok "已换进 $signer"
Info "公钥指纹 $fp （这个可以公开，方便日后核对客户端里装的是哪一把）"

# ---------------------------------------------------------------- 3. 重新签
Write-Host ""
Write-Host "[3/4] 用新私钥重签 version.json" -ForegroundColor Cyan
& $Godot --headless --path $root --script res://tools/sign_version.gd -- `
    --key $KeyPath --quit 2>&1 | Out-Null
$vj = Get-Content -Raw -Encoding UTF8 'version.json' | ConvertFrom-Json
if (-not $vj.package.PSObject.Properties['signature']) { Die "签名没写进 version.json" }
Ok "version.json 已重新签名"

# ---------------------------------------------------------------- 4. 真校验
Write-Host ""
Write-Host "[4/4] 校验这三样是配套的" -ForegroundColor Cyan
$v = & $Godot --headless --path $root --script res://tools/selfcheck_verify.gd --quit 2>&1 | Out-String
if ($v -notmatch 'SIGNATURE_VERIFY=OK') {
    Die "校验没过，别用这把钥匙发版。输出：`n$v"
}
Ok "私钥、客户端公钥、version.json 三者配套"

# ---------------------------------------------------------------- 收尾
Write-Host ""
Write-Host "完成。" -ForegroundColor Green
Write-Host ""
Write-Host "  现在立刻做这两件事：" -ForegroundColor Yellow
Write-Host "    1. 把 $KeyPath 备份到离线的地方（U 盘 / 密码管理器）" -ForegroundColor Yellow
Write-Host "       丢了就再也签不出已发布客户端认的清单，他们只能永远手动下载。" -ForegroundColor Yellow
Write-Host "    2. 确认它没进 git：git status --short 里不该出现 tools/keys/" -ForegroundColor Yellow
Write-Host ""
Write-Host "  以后正常发版不用再跑这个脚本 —— build_release.ps1 会自动用它签名。" -ForegroundColor DarkGray
