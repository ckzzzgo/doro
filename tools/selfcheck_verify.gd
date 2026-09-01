extends SceneTree
## selfcheck.ps1 在 -WithGodot 分支里调用：真校验一遍 version.json 的签名。
## 只有 Godot 能跑 RSA 加解密，字段存在性之类的静态检查替代不了这一关。
##
## 输出一行 SIGNATURE_VERIFY=OK 表示通过；否则打印具体错误。
func _init():
	var path := "version.json"
	if not FileAccess.file_exists(path):
		print("SIGNATURE_VERIFY=FAIL missing version.json")
		quit(1)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		print("SIGNATURE_VERIFY=FAIL not json")
		quit(1)
		return
	var VS = load("res://scripts/gd/utils/version_signer.gd")
	var err: String = VS.verify(parsed)
	if err.is_empty():
		print("SIGNATURE_VERIFY=OK")
		quit(0)
		return
	print("SIGNATURE_VERIFY=FAIL " + err)
	quit(1)
