extends RefCounted
class_name VersionSigner

## 版本清单（version.json）的数字签名校验。
##
## 为什么需要它：一键更新的信任链原本落在第三方镜像上。直连 GitHub 不通时，
## version.json 要从 ghfast.top 这类公共加速源取 —— 而安装包的 sha256 就写在同一份
## version.json 里。一个能把 version.json 掉包的镜像，可以同时伪造「更新版本号 + 配套
## sha256 + 更高级的版本号」，形成一条自圆其说的供应链攻击：客户端看到更高版本、下载
## 一个被掉包的包、sha256 也对得上、于是照样装上恶意内容。
##
## 挡它的办法：对「版本号 + 下载清单」这一小段做数字签名。公钥内嵌在客户端里，拿不到
## 私钥的镜像只能转发官方发布的那条合法清单，改任何一个字段都会让验证失败。私钥只留在
## 作者手里，仓库里只有公钥（见 tools/gen_signing_key.gd + tools/sign_version.gd）。
##
## 签的是什么：不是原始 JSON 字节（JSON.parse_string 在不同 Godot 版本对同键可能重排，
## 客户端消费的是解析后的字典，字节一漂移就必然失败），而是对「安全相关字段」拼的一条
## 规范串。这样客户端校验的正是它接下来要用的那些值，而且与 JSON 键序无关。
##
## 一个都签不上就拒绝一键更新，退回手动下载。宁可不更新，也不能装来路不明的东西。

## 内嵌公钥。由 tools/gen_signing_key.gd 生成，把输出粘到这里。私钥绝不入库。
const PUBLIC_KEY_PEM := "-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA2VSorcEEPlnfPL4xtGmY
dIDh8Klab+edeqrtLI6Yls+s/EFucur17W4AtpXfOE+BCm1U9iUP5jUkk05uvgjL
6DOCRVIVjLZSGQ7x9K8W+T0650Ui3K5WGGYrPhyJ9DSbfMzlvZJjzj+Z43JQWaF7
x+uMIH6LaA4NhmuivK1/Etmz6qUE4Lrvqmf5Y+O/67llPOKWnGy629zejH3hTpk2
60z/HsUPM8epPY0Q5K61ieEr7e3FKScYziTy2KfHMNp9CFvidpDTJxgCSN9kNadm
rKIe3fGAvRwQHavwlvNY+IFB3l8hFmMIMt1cqtymlp2Q4Mf2C0tMAV5F9mx8Kfzv
BwIDAQAB
-----END PUBLIC KEY-----"


## 对 manifest 做校验。manifest 是已经 JSON.parse 出来的 Dictionary。
## 返回空串 = 通过；返回非空 = 人话错误信息。
static func verify(manifest: Dictionary) -> String:
	if not manifest.has("version"):
		return "版本清单里没有 version 字段"
	if not manifest.has("package"):
		return "版本清单里没有 package 字段"

	var pkg := manifest["package"] as Dictionary
	if pkg == null:
		return "package 字段不是对象"
	if not pkg.has("signature"):
		return "版本清单没有签名，无法确认来源"
	if not pkg.has("url"):
		return "package 里没有下载地址"
	if not pkg.has("sha256"):
		return "package 里没有 sha256"

	if PUBLIC_KEY_PEM.strip_edges().is_empty():
		return "客户端未内嵌校验公钥，无法验证版本清单"

	var key := CryptoKey.new()
	if key.load_from_string(PUBLIC_KEY_PEM, true) != OK:
		return "客户端内嵌公钥无法解析"
	if not key.is_public_only():
		return "客户端内嵌公钥竟不是公钥"

	var canon := canonical_string(manifest)
	if canon == "":
		return "版本清单字段缺失，无法校验"

	# 非法 base64 由 Marshalls 返回空数组（不抛异常），直接判空即可。
	var sig := Marshalls.base64_to_raw(str(pkg["signature"]))
	if sig.is_empty():
		return "签名不是合法的 base64"

	var crypto := Crypto.new()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(canon.to_utf8_buffer())
	var digest := ctx.finish()

	if not crypto.verify(HashingContext.HASH_SHA256, digest, sig, key):
		return "版本清单签名校验失败，下载来源不可信"

	return ""


## 拼出被签名的那条规范串。返回空串表示字段缺失、拼不出来。
##
## 拆开了逐项累加，而不是一次 format：这样缺字段时能精确报错，
## 也避免把恶意镜像塞进来的换行之类的带进签名串。
static func canonical_string(manifest: Dictionary) -> String:
	if not manifest.has("version"):
		return ""
	if not manifest.has("package"):
		return ""
	var pkg := manifest["package"] as Dictionary
	if pkg == null:
		return ""
	if not pkg.has("name") and not pkg.has("url") and not pkg.has("sha256"):
		return ""

	var name := str(pkg.get("name", ""))
	var url := str(pkg.get("url", ""))
	var sha := str(pkg.get("sha256", "")).to_lower()
	var version := str(manifest["version"])

	var lines := PackedStringArray()
	lines.append("doro-manifest-v1")
	lines.append("version=" + version)
	lines.append("package.name=" + name)
	lines.append("package.url=" + url)
	lines.append("package.sha256=" + sha)
	return "\n".join(lines)
