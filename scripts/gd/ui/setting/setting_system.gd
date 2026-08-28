extends Node

## 系统相关开关。
##
## 「低功耗模式」原本在这里，已去掉，现在恒为开启 —— 由 project.godot 的
## application/run/low_processor_mode=true 在启动时施加，不再有开关。
##
## 去掉的理由是实测它没有代价：同一台机器上开与关的帧率完全一致
## （30 档 30.00 对 30.00，60 档 60.02 对 60.03，144 档 143.97 对 144.00），
## 帧间隔的抖动也在噪声范围内（30 档标准差 0.65ms 对 0.18ms，即 33.33ms 一帧上
## 波动 2%，肉眼与 60Hz 屏都分辨不出；60 档两者交错，分不出高下），
## 而 CPU 占用开着比关着低 9%（30 档）到 24%（60 档）。
##
## 也就是说这是个白送的优化，留一个叫「低功耗模式」的勾选框只会让人误以为
## 它会牺牲流畅度而主动关掉，白多烧一份 CPU 换不到任何东西。
##
## 代价是失去了逃生口：若某台机器上它真的引发问题，用户无法自行关闭，只能等新版本。
## 上述实测只覆盖一台插电的 24 核台式机 + 60Hz 显示器，不含笔记本电池模式、
## 虚拟机与远程桌面。

const DoroLog = preload("res://scripts/gd/utils/debug_log.gd")

@onready var _config: ConfigManager = get_node("/root/Config")
@onready var _auto_starter = get_node("/root/AutoStarter")
var _section: ConfigSection 
var _app_name = ProjectSettings.get_setting("application/config/name")

func _ready() -> void:
	_section = _config.add_section(&"system")
	
	_bind_components()
	_config.save_config()
	_section.load_props()
	# 夹在这两步中间：load_props 之后才知道用户存档里是什么，_load_config 之前改完
	# 才能让勾选框和检测定时器一次到位。
	_migrate_auto_hide()
	_load_config()

func _bind_components():
	_section.set_prop(&"auto_start", false)
	_section.bind(&"auto_start").with(_update_auto_start).to_check_box($AutoStartCheckbox)

	_section.set_prop(&"auto_hide", true)
	_section.bind(&"auto_hide").with(_update_auto_hide).to_check_box($AutoHideCheckbox)
	# 迁移标记，见 _migrate_auto_hide。
	#
	# 必须也声明成正式配置项：ConfigManager._purge_orphan_keys 会把「没人认领」的键
	# 从配置文件里删掉。标记一被删，迁移每次启动都会重跑 —— 用户手动关掉的开关会被
	# 反复翻开，比不做迁移还糟。
	_section.set_prop(&"auto_hide_default_applied", false)

func _load_config():
	$AutoStartCheckbox.set_pressed_no_signal(_auto_starter.IsAutoStartEnabled(_app_name))
	$AutoHideCheckbox.set_pressed_no_signal(_section.get_prop(&"auto_hide"))
	get_node("/root/Node2D").set_fullscreen_status(_section.get_prop(&"auto_hide"))
	
## 「全屏自动隐藏」的默认值从关改成开，并给已经装过的人翻一次。
##
## README 一直把「全屏让路 —— 你全屏看视频或打游戏，我自己藏起来」写在功能列表里，
## 可这个开关出厂是关的。关着的时候 window.set_fullscreen_status 会直接把检测定时器
## 暂停，一次都不查 —— 于是用户全屏打游戏，她照样在上面自己溜达。而这个窗口是置顶的
## （WindowManager 用 SetWindowPos + HWND_TOPMOST），移动一个置顶窗口会把独占全屏的
## 游戏挤出全屏，人就被弹回桌面了。等于宣传了一个默认不生效的功能。
##
## 光改默认值救不到已经装过的人：他们的 config.ini 里已经写着 auto_hide=false，
## load_props 里存档值优先于代码默认值。所以给他们翻一次。
##
## 翻过就记下，只翻这一次 —— 之后用户想关随时能关，不会被下次启动再翻开。
func _migrate_auto_hide() -> void:
	if _section.get_prop(&"auto_hide_default_applied"):
		return
	_section.set_prop(&"auto_hide", true)
	_section.set_prop(&"auto_hide_default_applied", true)
	# set_prop 只改内存里的字典，得自己落盘，否则下次启动又从存档读回旧值。
	_config.set_value(&"system", &"auto_hide", true)
	_config.set_value(&"system", &"auto_hide_default_applied", true)
	_config.save_config()
	DoroLog.d("[DORO] 全屏自动隐藏：默认值改为开，已为老配置翻开一次")

func _update_auto_start(name, value):
	if value:
		_auto_starter.EnableAutoStart(_app_name)
	else:
		_auto_starter.DisableAutoStart(_app_name)
		
func _update_auto_hide(name, value):
	get_node("/root/Node2D").set_fullscreen_status(value)
