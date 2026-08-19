extends Node
class_name ConfigManager

const DoroLog = preload("res://scripts/gd/utils/debug_log.gd")

const WINDOW_SEC_NAME: StringName = &"window"

@export var config_path:String = "user://config.ini"

var _config = ConfigFile.new()
var _sections: Dictionary[StringName, ConfigSection] = {}

func _ready() -> void:
	load_config()

	# 清理必须等所有设置脚本的 _ready 跑完，原因有两条：
	#   1. 本节点是自动加载，_ready 早于主场景，此刻 _sections 还是空的 ——
	#      现在扫，「没人认领」的会是全部键；
	#   2. 旧键的折算要先读到旧值。例如 display 用 max_fps 折算出 fps_tier，
	#      清理跑在折算前面就会把用户原来的帧率设置抹掉，让他们静默回到默认值。
	# process_frame 在整棵场景树就位、所有 _ready 都调用完之后才触发，正好合适。
	await get_tree().process_frame
	_purge_orphan_keys()
	
func add_section(name: StringName) -> ConfigSection:
	_sections[name] = ConfigSection.new(name, self)
	return _sections[name]
	
func get_section(name: StringName) -> ConfigSection:
	return _sections.get(name)
	
func load_config():
	var error := _config.load(config_path)
	if error != OK:
		if error != ERR_FILE_NOT_FOUND:
			push_warning("Unable to load config file (%s): %s" % [config_path, error])
		save_config()
		
func save_config():
	return _config.save(config_path)
		
func set_value(section: String, key: String, value):
	_config.set_value(section, key, value)
	
func get_value(section: String, key: String, default=null):
	return _config.get_value(section, key, default)

func get_window_config(key: String, default=null):
	return get_value(WINDOW_SEC_NAME, key, default)

func on_window_config_change(key:String, value):
	_config.set_value(WINDOW_SEC_NAME, key, value)
	save_config()

## 清掉配置文件里已经没人认领的键。
##
## 每砍掉一个设置项，用户的配置文件里就会留下一个再也不会被读取的键。单个无害，
## 攒多了配置文件就成了考古现场，也让人分不清哪些还在用。到 1.1.5 为止已经攒下
## 八个：system/power_save、interact/dock_type、interact/drop_remove、
## display 的 fps_limit、max_fps、vsync、msaa、msaa_level。
##
## 这里刻意不维护一张「废弃键清单」—— 那种清单迟早会有人忘了更新。改成反过来判定：
## 凡是走属性绑定的 section，文件里有、而代码里没注册的键，一律算废弃。这样以后
## 再删设置项不用回来改这里。
##
## 两条安全线：
##   1. 只处理 _sections 里登记过的 section。[window] 走的是 get_window_config /
##      on_window_config_change，不注册属性，因此不会被扫到，原样保留。
##   2. 某个 section 一个属性都没注册时跳过 —— 那多半是它的脚本没跑起来，
##      这时候清理会把还在用的键全删光。
func _purge_orphan_keys() -> void:
	var removed: Array[String] = []

	for section_name in _sections:
		var props: Dictionary = _sections[section_name]._prop_dict
		if props.is_empty():
			continue

		var name := String(section_name)
		if not _config.has_section(name):
			continue

		for key in _config.get_section_keys(name):
			if not props.has(StringName(key)):
				_config.erase_section_key(name, key)
				removed.append("%s/%s" % [name, key])

	if not removed.is_empty():
		save_config()
		DoroLog.d("[Config] 已清理废弃配置项: " + ", ".join(removed))
