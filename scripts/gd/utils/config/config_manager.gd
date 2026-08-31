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
		
## 需要加密落盘的键（section/key）。
##
## 只放**凭据**。url、model_name 不是秘密；prompt 是用户自己调的人格，加密只会让
## 配置文件没法人工排查，而调 prompt 的人正想直接看它。
const SECRET_KEYS := {
	"chat": ["api_key"],
}


## 读写在这里做透明加解密，上层（ConfigSection、设置界面、绑定框架）一行都不用改。
##
## 挡的是「config.ini 这个文件被别人看到」：借走的笔记本、截图、同步到网盘的备份、
## 用户把配置发出来求助。挡不住以同一个 Windows 账号运行的程序 —— 它自己也能解开。
## 细节见 SecretStore.cs。
func _is_secret(section: String, key: String) -> bool:
	return key in SECRET_KEYS.get(section, [])


func _secret_store():
	return get_node_or_null(^"/root/SecretStore")


## 本次运行中解不开的机密键（"section/key"）。见 set_value 里那道守卫。
var _undecryptable: Dictionary = {}


func set_value(section: String, key: String, value):
	if _is_secret(section, key):
		var id := "%s/%s" % [section, key]
		# 解不开的密文，不许被空串覆盖。
		#
		# ConfigSection.load_props() 会把 get_value 返回的东西原样写回配置文件。
		# 解密失败时 get_value 返回空串，于是那串「暂时读不出来、但换回原机器就能用」
		# 的密文会被当场抹成 ""。实测过：确实会毁掉用户唯一能恢复的凭据。
		#
		# 用户自己填了新 key（非空）才放行，同时解除标记 —— 那是真的要替换。
		if _undecryptable.has(id):
			if value is String and value == "":
				return
			_undecryptable.erase(id)
		if value is String and value != "":
			var store = _secret_store()
			if store:
				var sealed: String = store.Protect(value)
				# 加密失败（非 Windows、crypt32 缺失）就退回明文。功能可用优先于加密
				# —— 存不进去 key 等于聊天功能直接废掉，那比明文更糟。
				if sealed != "":
					_config.set_value(section, key, sealed)
					return
	_config.set_value(section, key, value)


func get_value(section: String, key: String, default=null):
	var raw = _config.get_value(section, key, default)
	if not (_is_secret(section, key) and raw is String and raw != ""):
		return raw
	var store = _secret_store()
	if store == null:
		return raw
	if not store.IsProtected(raw):
		# 老版本留下的明文。就地补加密再写回，只补这一次。
		DoroLog.d("[Config] %s/%s 是明文，改为加密存放" % [section, key])
		set_value(section, key, raw)
		save_config()
		return raw
	var plain: String = store.Unprotect(raw)
	if plain == "":
		# 解不开：配置多半是从别的机器或别的 Windows 账号拷来的。DPAPI 的密钥绑账号，
		# 这属于预期内。返回空让用户重填，同时记上标记 —— set_value 那边靠它挡住
		# 「空串把密文冲掉」，用户拷回原机器时还能用。
		_undecryptable["%s/%s" % [section, key]] = true
		push_warning("配置里的 %s/%s 解密失败：换过机器或 Windows 账号的话需要重新填写" % [section, key])
	return plain

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
