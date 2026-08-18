extends PopupMenu

const ID_HIDE = 0
const ID_EXIT = 1
const ID_RESET = 2

@onready var config: ConfigManager = get_node("/root/Config")
var _is_fullscreen_hide = false

func _on_status_indicator_pressed(mouse_button: int, mouse_position: Vector2i) -> void:
	# 左键点击托盘图标召回窗口
	if mouse_button == MOUSE_BUTTON_LEFT:
		var center_pos = _get_screen_center()
		var window_pos = get_tree().root.position
		if center_pos.distance_to(window_pos) > 10:
			get_node("/root/Node2D/GDCubismUserModel/Animation/EffectMove").move(center_pos, true, _on_recall_start, _on_recall_finish)

func _on_item_pressed(id: int) -> void:
	if id == ID_HIDE:
		var checked = is_item_checked(ID_HIDE)
		$"../..".visible = checked
		get_tree().paused = !checked
		set_item_checked(ID_HIDE, !checked)
	elif id == ID_RESET:
		_reset_size_and_position()
	elif id == ID_EXIT:
		get_tree().quit()

func _on_other_app_fullscreen(is_fullscreen):
	if is_fullscreen:
		if is_item_checked(ID_HIDE):
			return
		else:
			$"../..".visible = !is_fullscreen
			get_tree().paused = is_fullscreen
			set_item_checked(ID_HIDE, is_fullscreen)
			_is_fullscreen_hide = true
	else:
		if _is_fullscreen_hide:
			$"../..".visible = !is_fullscreen
			get_tree().paused = is_fullscreen
			set_item_checked(ID_HIDE, is_fullscreen)
			_is_fullscreen_hide = false

func _get_screen_center():
	var screen_pos = DisplayServer.screen_get_position()
	var screen_size = DisplayServer.screen_get_size()
	var window_size = get_tree().root.get_window().size
	return screen_pos + screen_size / 2 - window_size / 2

func _on_recall_start():
	get_node("/root/Node2D/GDCubismUserModel/Animation").run()
	get_node("/root/Node2D/GDCubismUserModel/Animation").set_expression("Amaze")
	
func _on_recall_finish():
	get_node("/root/Node2D/GDCubismUserModel/Animation").idle()
	get_node("/root/Node2D/GDCubismUserModel/Animation").set_expression("Idle")


## 把桌宠恢复成默认大小、解除停靠、移到主屏中央。
##
## 这是「鼠标够不着她」时的逃生口。缩得过小、被拖到屏幕外、停靠后藏起来、或者显示器
## 布局变化之后，窗口可能完全无法用鼠标命中 —— 而一旦命中不了，点击穿透就常开，
## 连滚轮和拖动事件都进不到窗口里，用户没有任何办法把她弄回来，只能去改配置文件。
## 托盘是这种情况下唯一还能操作的入口。
func _reset_size_and_position() -> void:
	var w = get_node_or_null("/root/Node2D")
	if w == null:
		return

	w.window_scale = 1.0

	# 必须先把窗口摆回屏幕中央，再调 update_window()：后者内部会按当前位置重新判定
	# 停靠，而这时窗口很可能还在屏幕外（正是需要救援的情形），它会认为窗口贴着边缘
	# 而立刻又把她停靠藏起来 —— 等于白救。
	var scr := DisplayServer.get_primary_screen()
	var size := Vector2i(int(w.BASE_WINDOW_WIDTH), int(w.BASE_WINDOW_HEIGHT))
	var pos: Vector2i = DisplayServer.screen_get_position(scr) 		+ (DisplayServer.screen_get_size(scr) - size) / 2
	get_tree().root.position = pos
	w.update_window()
	get_tree().root.position = pos

	# 解除停靠。居中之后 dock_to_edge 通常已经解除了，但 enable_docking 关闭时它
	# 根本不会被调用，且打字模式下它会跳过姿态复位，所以这里无条件收尾一次。
	w.docking = false
	w.docking_dir = 4  # DOCK_NONE
	var model = w.get_node_or_null("GDCubismUserModel")
	if model:
		model.set_rotation_degrees(0)
		model.position = Vector2.ZERO
		model.Body_group = 1
	w.window_docking.emit(false, 4)

	# 立刻落盘，否则下次启动又回到坏掉的值
	w.window_scale_changed.emit("window_scale", w.window_scale)
	w.window_pos_changed.emit("window_pos", pos)
