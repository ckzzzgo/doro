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

@onready var _config: ConfigManager = get_node("/root/Config")
@onready var _auto_starter = get_node("/root/AutoStarter")
var _section: ConfigSection 
var _app_name = ProjectSettings.get_setting("application/config/name")

func _ready() -> void:
	_section = _config.add_section(&"system")
	
	_bind_components()
	_config.save_config()
	_section.load_props()
	_load_config()

func _bind_components():
	_section.set_prop(&"auto_start", false)
	_section.bind(&"auto_start").with(_update_auto_start).to_check_box($AutoStartCheckbox)
	
	_section.set_prop(&"auto_hide", false)
	_section.bind(&"auto_hide").with(_update_auto_hide).to_check_box($AutoHideCheckbox)
	
func _load_config():
	$AutoStartCheckbox.set_pressed_no_signal(_auto_starter.IsAutoStartEnabled(_app_name))
	$AutoHideCheckbox.set_pressed_no_signal(_section.get_prop(&"auto_hide"))
	get_node("/root/Node2D").set_fullscreen_status(_section.get_prop(&"auto_hide"))
	
func _update_auto_start(name, value):
	if value:
		_auto_starter.EnableAutoStart(_app_name)
	else:
		_auto_starter.DisableAutoStart(_app_name)
		
func _update_auto_hide(name, value):
	get_node("/root/Node2D").set_fullscreen_status(value)
