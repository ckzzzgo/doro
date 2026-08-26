extends SceneTree

## 全项目资源可达性分析：哪些文件已经没人用了。
##
## 用法：godot --headless --path . --script res://tools/depcheck.gd
##
## 为什么需要它：二进制 .res 是压缩的，在外面 grep 根本看不到里面引用了谁；
## Godot 又常按 uid:// 而不是路径来引用。只靠文本搜索必然误判 —— 第一次清理时
## 文本扫描报了 13 个「没人用」，让引擎自己回答之后只剩 1 个是真的，另外 12 个
## 全是 Doro 的表情，删了脸就没了。
##
## 判定分两条腿，缺一不可：
##   1. 从主场景 + 自动加载出发，顺着 ResourceLoader.get_dependencies 走一遍
##   2. 源码里出现过的 res:// 字面量（运行时 load() 的东西，第 1 条走不到）
## 两条都没命中的，才算嫌疑。
##
## 注意它仍有误报，别拿结果直接删：
##   addons/ 里的文件按 class_name / extends 互相引用，这里看不出来
##   LICENSE、README、csproj 这类本来就不是被引用的资源
##   assets/icons/app_icon.ico 之类由构建脚本（而非 Godot）使用的文件
## 真要删，先把文件移走跑一遍，确认没有缺资源报错再动手。

const SKIP_DIRS := ["res://.godot", "res://export", "res://docs", "res://tools"]

func _initialize() -> void:
	var roots := _roots()
	print("=== 起点 %d 个 ===" % roots.size())

	var reachable := {}
	var queue := roots.duplicate()
	while not queue.is_empty():
		var p: String = queue.pop_front()
		if reachable.has(p) or not ResourceLoader.exists(p):
			continue
		reachable[p] = true
		for d in ResourceLoader.get_dependencies(p):
			var path := d
			var idx := d.rfind("::")
			if idx >= 0:
				path = d.substr(idx + 2)
			if path.begins_with("res://"):
				queue.push_back(path)
	print("    顺着依赖走到 %d 个资源" % reachable.size())

	var literals := _res_literals()
	print("    源码里出现过的 res:// 字面量 %d 个" % literals.size())

	var all := []
	_collect("res://", all)
	print("    项目里共 %d 个文件" % all.size())

	print()
	print("=== 两条腿都没命中的（疑似没人用）===")
	var dead := []
	for p in all:
		if reachable.has(p) or literals.has(p):
			continue
		dead.append(p)
	dead.sort()
	var total := 0
	for p in dead:
		var sz := _size(p)
		total += sz
		print("  %9.1f KB  %s" % [sz / 1024.0, p])
	print()
	print("  共 %d 个，合计 %.1f KB" % [dead.size(), total / 1024.0])
	quit()


func _roots() -> Array:
	var out := ["res://scenes/main.tscn"]
	var cfg := ConfigFile.new()
	if cfg.load("res://project.godot") == OK:
		out.append(cfg.get_value("application", "run/main_scene", ""))
		for k in cfg.get_section_keys("autoload"):
			var v: String = cfg.get_value("autoload", k, "")
			out.append(v.trim_prefix("*"))
	var clean := []
	for p in out:
		if p != "" and not clean.has(p):
			clean.append(p)
	return clean


func _res_literals() -> Dictionary:
	var out := {}
	var files := []
	_collect("res://", files)
	var re := RegEx.new()
	re.compile('res://[A-Za-z0-9_./-]+')
	for f in files:
		if not (f.ends_with(".gd") or f.ends_with(".cs") or f.ends_with(".tscn")
				or f.ends_with(".tres") or f.ends_with(".cfg") or f.ends_with(".godot")):
			continue
		var txt := FileAccess.get_file_as_string(f)
		for m in re.search_all(txt):
			out[m.get_string()] = true
	return out


func _collect(base: String, out: Array) -> void:
	for s in SKIP_DIRS:
		if base.begins_with(s):
			return
	var d := DirAccess.open(base)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if not name.begins_with("."):
			var p := base.path_join(name)
			if d.current_is_dir():
				_collect(p, out)
			elif not name.ends_with(".import") and not name.ends_with(".uid"):
				out.append(p)
		name = d.get_next()
	d.list_dir_end()


func _size(p: String) -> int:
	var f := FileAccess.open(p, FileAccess.READ)
	return 0 if f == null else f.get_length()
