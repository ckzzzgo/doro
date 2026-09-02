extends RefCounted

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
##
## 故意不用 class_name（消费方一律 const + preload）：理由见 debug_log.gd —— 全局类名
## 靠编辑器扫描才写进 global_script_class_cache.cfg，而本项目是纯命令行打包。

## 内嵌公钥。**空着是故意的** —— 还没做密钥仪式。
##
## 私钥必须由作者本人生成和保管，不能由别人代劳，所以仓库里不预置任何一把。
## 空着时 verify() 会一路 fail-closed：一键更新整条不可用，只留手动下载。
##
## 刻章（一条命令搞定生成、写公钥、重签清单、验配套）：
##   pwsh -File tools/setup_signing_key.ps1
const PUBLIC_KEY_PEM := ""


## 对 manifest 做校验。manifest 是已经 JSON.parse 出来的 Dictionary。
## 返回空串 = 通过；返回非空 = 人话错误信息。
static func verify(manifest: Dictionary) -> String:
	if not manifest.has("version"):
		return "版本清单里没有 version 字段"
	if not manifest.has("package"):
		return "版本清单里没有 package 字段"

	# 必须先用 typeof 判类型，不能写 `manifest["package"] as Dictionary`：
	# 对非字典值 as 不会返回 null，而是抛 Invalid cast 让函数当场中断 ——
	# 中断的返回值是空串，而空串在这里等于「校验通过」。安全闸门 fail-open
	# 比没有闸门更糟，因为上层会据此认为来源已可信。实测过：package 传
	# "lol" / 42 / [] 三种畸形值，改之前三次全部放行。
	if typeof(manifest.get("package")) != TYPE_DICTIONARY:
		return "package 字段不是对象"
	var pkg: Dictionary = manifest["package"]
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
## 每个字段名恒定出现、顺序固定，所以就算镜像往某个字段里塞换行也拼不出碰撞 ——
## 想让两条不同的清单产出同一条串，就得把某个字段名整个吃掉，而它们总是被写出来。
##
## notes_url 也在签名范围内，别拿掉。它不像 sha256 那样直接决定装什么，但
## _on_jump_button_pressed 会把它交给 OS.shell_open —— 不签的话，一个镜像可以转发
## 官方那份合法签名的清单、只把这一行换成自己的网址，客户端验签照过，然后在
## 「请手动下载」的提示下把用户送到钓鱼站。size / released 不签：它们不导向任何动作。
static func canonical_string(manifest: Dictionary) -> String:
	if not manifest.has("version"):
		return ""
	if typeof(manifest.get("package")) != TYPE_DICTIONARY:
		return ""
	var pkg: Dictionary = manifest["package"]
	if not pkg.has("name") and not pkg.has("url") and not pkg.has("sha256"):
		return ""

	var name := str(pkg.get("name", ""))
	var url := str(pkg.get("url", ""))
	var sha := str(pkg.get("sha256", "")).to_lower()
	var version := str(manifest["version"])
	var notes := str(manifest.get("notes_url", ""))

	var lines := PackedStringArray()
	lines.append("doro-manifest-v2")
	lines.append("version=" + version)
	lines.append("notes_url=" + notes)
	lines.append("package.name=" + name)
	lines.append("package.url=" + url)
	lines.append("package.sha256=" + sha)
	return "\n".join(lines)
