extends Node

## 互动相关开关的绑定。
##
## 这些开关现在只出现在工具栏的「互动」菜单里（中键点桌宠 → 互动），设置窗口不再重复
## 显示同一批选项。本节点因此没有自己的界面，只作为绑定与持久化的宿主 —— 它仍然挂在
## 设置窗口的「互动」容器上，那个容器已经空了、不占版面。
##
## 边缘吸附不再区分「吸附至边缘」和「吸附至任务栏」：上下左右四边本来就都能吸，那个
## 下拉框只影响贴的是屏幕物理边缘还是任务栏边缘，对用户没有解释价值。现统一按任务栏
## 边缘（screen_get_usable_rect），也就是原来的默认行为，手感不变。

@onready var _config: ConfigManager = get_node("/root/Config")
var _section: ConfigSection

@onready var _root: Node2D = get_node("/root/Node2D")
@onready var _chat_dialog: Window = get_node("/root/Node2D/GUI/ChatDialog")
@onready var _window_manager = get_node("/root/WindowManager")

const MENU := "/root/Node2D/GUI/Toolbar/Buttons/InteractButton/InteractMenu/VBoxContainer"

func _ready() -> void:
	_section = _config.add_section(&"interact")

	_bind_components()
	_config.save_config()
	_section.load_props()
	_load_config()

func _menu(name: String) -> CheckBox:
	return get_node(MENU + "/" + name)

func _bind_components():
	_section.set_prop(&"pin", true)
	_section.bind(&"pin").with(_update_pin).to_check_box(_menu("PinCheckbox"))

	_section.set_prop(&"stroll", true)
	_section.bind(&"stroll").with(_update_stroll).to_check_box(_menu("StrollCheckbox"))

	_section.set_prop(&"mouse_follow", true)
	_section.bind(&"mouse_follow").with(_update_mouse_follow).to_check_box(_menu("MouseFollowCheckbox"))

	_section.set_prop(&"dock", true)
	_section.bind(&"dock").with(_update_dock).to_check_box(_menu("DockCheckbox"))

	# 默认开：这是原有行为，不能因为加了开关就把功能从所有人手里悄悄拿走。
	# 不喜欢的人自己关掉。
	_section.set_prop(&"keyboard_mode", true)
	_section.bind(&"keyboard_mode").with(_update_keyboard_mode).to_check_box(_menu("KeyboardModeCheckbox"))

func _load_config():
	_menu("PinCheckbox").set_pressed_no_signal(_section.get_prop(&"pin"))
	_apply_pin(_section.get_prop(&"pin"))

	_menu("StrollCheckbox").set_pressed_no_signal(_section.get_prop(&"stroll"))
	_apply_stroll(_section.get_prop(&"stroll"))

	_menu("MouseFollowCheckbox").set_pressed_no_signal(_section.get_prop(&"mouse_follow"))
	_apply_mouse_follow(_section.get_prop(&"mouse_follow"))

	_menu("DockCheckbox").set_pressed_no_signal(_section.get_prop(&"dock"))
	_apply_dock(_section.get_prop(&"dock"))

	_menu("KeyboardModeCheckbox").set_pressed_no_signal(_section.get_prop(&"keyboard_mode"))
	_apply_keyboard_mode(_section.get_prop(&"keyboard_mode"))

func _update_pin(_name, value):
	_apply_pin(value)

func _update_stroll(_name, value):
	_apply_stroll(value)

func _update_mouse_follow(_name, value):
	_apply_mouse_follow(value)

func _update_dock(_name, value):
	_apply_dock(value)

func _update_keyboard_mode(_name, value):
	_apply_keyboard_mode(value)

## 主窗口的置顶交给 WindowManager 用 SetWindowPos 施加。
##
## 光设 Godot 的 always_on_top 是不够的：WindowManager.SetClickThrough() 在鼠标每次
## 移进/移出桌宠时都会重写整个窗口扩展样式，这个动作会把窗口挤出置顶层。实测无论开关
## 如何，系统层面的 TOPMOST 位始终为 0 —— 也就是置顶从来没真正生效过。
##
## 仍然同步 Godot 自己的标志，避免引擎内部状态与实际不符。聊天框是独立子窗口，
## 不受上述样式重写影响，照旧用 Godot 的属性即可。
func _apply_pin(value: bool) -> void:
	get_tree().root.get_window().always_on_top = value
	if _window_manager:
		_window_manager.SetTopmost(value)
	_chat_dialog.always_on_top = value

func _apply_stroll(value: bool) -> void:
	get_node("/root/Node2D/GDCubismUserModel/Animation/EffectMove/EffectRandMove").enable = value

func _apply_mouse_follow(value: bool) -> void:
	get_node("/root/Node2D/GDCubismUserModel/Animation/EffectMouseFollow").enable = value

func _apply_dock(value: bool) -> void:
	_root.enable_docking = value


## 键盘模式的总开关。
##
## 关掉之后她不会再因为你敲键盘而摆出桌子和键盘。如果关的当下她正处在打字模式里，
## 立刻退出 —— 否则得等 7 秒空闲超时，用户会以为开关没生效。
func _apply_keyboard_mode(value: bool) -> void:
	var ir = get_node_or_null("/root/Node2D/InputReaction")
	if ir:
		ir.set_keyboard_mode_enabled(value)
