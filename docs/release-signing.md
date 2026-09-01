# 版本清单签名 — 发版流程

## 为什么要有这一步

一键更新的信任链原本依赖第三方镜像。直连 GitHub 不通时，`version.json` 要从
ghfast.top 这类公共加速源取，而安装包的 `sha256` 就写在同一份 `version.json` 里。

一个能把 `version.json` 掉包的镜像，可以同时伪造「更新版本号 + 配套 sha256 + 更高的
版本号」，让客户端看到更高版本、下载被掉包的包、`sha256` 也对得上、于是照样装上恶意
内容 —— 一条自圆其说的供应链攻击。

挡它的办法是对「版本号 + 下载清单」这一小段做 RSA 数字签名：

- **公钥**内嵌在客户端里（`scripts/gd/utils/version_signer.gd` 的 `PUBLIC_KEY_PEM`），
  客户端用它校验清单。
- **私钥**只留在作者手里，**绝不能入库**（`.gitignore` 已排除 `tools/keys/`）。

镜像拿不到私钥，只能原样转发官方那份合法清单；改任何一个字段（版本号 / 下载地址 /
sha256 / 签名）都会让校验失败，一键更新被整条拦下，退回手动下载。

## 每次发版都要跑的两步

### 1. 签名 version.json

改完版本号 / 安装包 sha256 之后：

```powershell
# 在项目根目录
D:\...\Godot_v4.4.1-stable_mono_win64_console.exe --headless --path . --script res://tools/sign_version.gd -- --key tools/keys/signing_priv.pem --quit
```

它读仓库根 `version.json`，把签名字段写进 `package.signature`（base64），原地写回。
签名串与客户端校验用的是同一条 `VersionSigner.canonical_string()`，两边不会分叉。

### 2. 确认签名能过

```powershell
# 不带 -WithGodot 只查「有没有签名字段 + 私钥没入库」；
# 带 -WithGodot 会真跑 RSA 加解密，确认签的是当前这份清单。
pwsh -File tools/selfcheck.ps1 -WithGodot
```

自检第 5 节保证 `version.json` 带签名、`tools/keys/` 没被 git 跟踪；第 6 节跑真校验。
最后一节显示 `version.json 签名通过内嵌公钥校验` 才算通过。

## 首次拿到这份代码：生成自己的密钥对

仓库里那份 `tools/keys/` 是**示例密钥**，别用到生产。真要用，先自己生成一把：

```powershell
D:\...\Godot_v4.4.1-stable_mono_win64_console.exe --headless --path . --script res://tools/gen_signing_key.gd -- --out tools/keys/signing_priv.pem --quit
```

把输出的**公钥**整段粘到 `version_signer.gd` 的 `PUBLIC_KEY_PEM`（替换掉示例公钥），
**私钥**文件自己备份好。私钥一旦丢失，旧版客户端将无法通过校验、无法一键更新 ——
只能靠手动下载，所以务必备份。

## 各文件职责

| 文件 | 干什么 |
| --- | --- |
| `scripts/gd/utils/version_signer.gd` | 客户端侧校验。内嵌公钥 + `verify()`/`canonical_string()`，唯一的安全闸门。 |
| `tools/gen_signing_key.gd` | 一次性生成密钥对。私钥写 `--out` 路径，公钥打到 stdout 供嵌入。 |
| `tools/sign_version.gd` | 发版时给 `version.json` 的 `package` 写入签名。 |
| `tools/selfcheck_verify.gd` | 自检调用的独立校验，供 `selfcheck.ps1 -WithGodot` 真跑一次。 |
| `tools/keys/` | 私钥目录，`.gitignore` 排除，绝不入库。 |

## 签名覆盖的字段

签名只覆盖「安全相关」字段，拼成一条规范串（`doro-manifest-v1` 开头）：

```
version
package.name
package.url
package.sha256
```

`size`、`notes_url`、`released` 等不参与签名。这样客户端校验的正是它接下来要用的
那一小段，且与 JSON 键序无关（`JSON.parse_string` 在不同 Godot 版本对同键可能重排，
签原始字节必然失败）。
