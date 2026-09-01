extends SceneTree
## 给仓库根目录的 version.json 加上数字签名（写进 package.signature）。
##
## 这是发版流程的一步：作者每次改版本号 / 安装包 sha256 后，都要重新跑一遍，
## 否则新的 version.json 过不了客户端的签名校验，一键更新会整条被拒、退回手动下载。
##
## 用法（在项目根目录，headless）：
##   godot --headless --script res://tools/sign_version.gd -- --key tools/keys/signing_priv.pem
##
## 默认读取仓库根 version.json 原地改写；--version 或 --sha256 可显式指定再签。
## 私钥只留在作者手里，绝不能入库（见 .gitignore 加 tools/keys/）。
##
## 签名与校验共用 VersionSigner.canonical_string()，保证签发端和消费端拼的是同一条串。
const VersionSignerScript = preload("res://scripts/gd/utils/version_signer.gd")

func _init():
	var args := OS.get_cmdline_user_args()
	var key_path := "tools/keys/signing_priv.pem"
	var manifest_path := "version.json"
	var force_version := ""
	var force_sha := ""

	var i := 0
	while i < args.size():
		match args[i]:
			"--key":
				if i + 1 < args.size(): key_path = args[i + 1]; i += 1
			"--manifest":
				if i + 1 < args.size(): manifest_path = args[i + 1]; i += 1
			"--version":
				if i + 1 < args.size(): force_version = args[i + 1]; i += 1
			"--sha256":
				if i + 1 < args.size(): force_sha = args[i + 1]; i += 1
		i += 1

	var text := FileAccess.get_file_as_string(manifest_path)
	if text.is_empty():
		push_error("无法读取清单: " + manifest_path)
		quit(1)
		return
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("清单不是合法 JSON: " + manifest_path)
		quit(1)
		return

	if not force_version.is_empty():
		parsed["version"] = force_version

	if not parsed.has("package") or typeof(parsed["package"]) != TYPE_DICTIONARY:
		push_error("清单里没有 package 对象")
		quit(1)
		return
	# parsed 是 JSON.parse_string 的返回值，类型是 Variant，不能直接推断出 Dictionary。
	var pkg := parsed["package"] as Dictionary
	if pkg == null:
		push_error("package 不是对象")
		quit(1)
		return
	# JSON.parse 会把整数 size 读成 float，重新 stringify 会掉成 "99779143.0"。
	# size 不参与签名、也不安全相关，但这串 .0 落进 manifest 很丑，顺手归位。
	if pkg.has("size"):
		var s = pkg["size"]
		if s is float and s == floorf(s):
			pkg["size"] = int(s)
	if not force_sha.is_empty():
		pkg["sha256"] = force_sha

	# 关键：用与客户端相同的 canonical_string 拼签名串，字段不一致必然签出一个
	# 客户端验不过的签名。这里跑一遍只是 confirm 这条串能拼出来。
	var canon: String = VersionSignerScript.canonical_string(parsed)
	if canon.is_empty():
		push_error("canonical_string 拼不出这条清单（缺字段）")
		quit(1)
		return

	var priv := FileAccess.get_file_as_string(key_path)
	if priv.is_empty():
		push_error("读不到私钥 " + key_path + "（先跑 tools/gen_signing_key.gd 生成）")
		quit(1)
		return
	var key := CryptoKey.new()
	if key.load_from_string(priv, false) != OK:
		push_error("私钥无法解析: " + key_path)
		quit(1)
		return
	if key.is_public_only():
		push_error("拿到的是公钥，不是私钥: " + key_path)
		quit(1)
		return

	var crypto := Crypto.new()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(canon.to_utf8_buffer())
	var digest := ctx.finish()
	var sig := crypto.sign(HashingContext.HASH_SHA256, digest, key)
	var sig_b64 := Marshalls.raw_to_base64(sig)

	pkg["signature"] = sig_b64
	parsed["package"] = pkg

	var out_file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if out_file == null:
		push_error("无法写入 " + manifest_path)
		quit(1)
		return
	# JSON.stringify 不补尾部换行。原文件一般带一个，保住它免得每次重签都留下一个
	# 没有末尾换行的文件、git diff 也随之多一行噪音。
	out_file.store_string(JSON.stringify(parsed, "\t") + "\n")
	out_file.close()

	print("已签名 version=" + str(parsed.get("version", "")) + " sha256=" + str(pkg.get("sha256", "")))
	print("signature 长度=" + str(sig_b64.length()))
	print("写回 " + manifest_path)
	quit(0)


## 供 headless 之外的调用：把一条已生成好的 manifest（含 package）签好返回。
## 不落盘。发版脚本若想拿签名字符串自己拼输出，可用这个。
static func sign_manifest(parsed: Dictionary, key: CryptoKey) -> String:
	var canon := VersionSignerScript.canonical_string(parsed)
	if canon == "":
		return ""
	var crypto := Crypto.new()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(canon.to_utf8_buffer())
	var sig := crypto.sign(HashingContext.HASH_SHA256, ctx.finish(), key)
	return Marshalls.raw_to_base64(sig)
