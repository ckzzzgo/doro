extends SceneTree
## 一次性生成「版本清单签名」用的 RSA 密钥对。
##
## 用法（在项目根目录，headless）：
##   godot --headless --script res://tools/gen_signing_key.gd -- --out tools/keys/signing_priv.pem
##
## 私钥写到 --out 指定路径（务必加进 .gitignore，绝不能入库）；公钥打到 stdout，
## 供你嵌进 version_signer.gd 的 PUBLIC_KEY_PEM。
##
## 公钥可以公开，私钥必须只留在你自己手里并备份。私钥一旦丢失，旧版客户端将无法
## 通过校验、无法一键更新 —— 只能靠手动下载。
func _init():
	var args := OS.get_cmdline_user_args()
	var out := "tools/keys/signing_priv.pem"
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]

	var c := Crypto.new()
	var key: CryptoKey = c.generate_rsa(2048)

	var pub: String = key.save_to_string(true)
	var priv: String = key.save_to_string(false)

	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		push_error("无法写入私钥文件: " + out)
		quit(1)
		return
	f.store_string(priv)
	f.close()
	# 收紧权限，防止别的高权进程读取（Windows 上主要靠放对位置）
	print("PRIVATE_KEY_WRITTEN=" + out)
	print("-----BEGIN PUBLIC KEY-----")
	var body := pub
	if body.begins_with("-----BEGIN PUBLIC KEY-----\n"):
		body = body.trim_prefix("-----BEGIN PUBLIC KEY-----\n")
		body = body.trim_suffix("-----END PUBLIC KEY-----\n")
	elif body.begins_with("-----BEGIN PUBLIC KEY-----"):
		body = body.trim_prefix("-----BEGIN PUBLIC KEY-----")
		body = body.trim_suffix("-----END PUBLIC KEY-----")
	print(body)
	print("-----END PUBLIC KEY-----")
	quit(0)
