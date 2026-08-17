extends RefCounted
## 调试日志。只在 debug 构建（编辑器内运行 / debug 导出）打印，release 导出自动静音。
##
## 这些 [DORO] 日志是排查停靠、拖拽、打字模式时序问题的主要手段，所以保留而不是删掉；
## 但发给别人用的 release 版不该往控制台和日志文件里刷东西。
##
## 故意不用 class_name：全局类名要靠编辑器扫描才会写进 global_script_class_cache.cfg，
## 而本项目用纯命令行 --headless --export-release 打包，漏扫一次就会整批脚本解析失败。
## 调用方一律用 const DoroLog = preload(...)，与项目里其他脚本的做法保持一致。

static func d(msg: String) -> void:
	if OS.is_debug_build():
		print(msg)
