extends PopupMenu

const ID_HIDE = 0
const ID_EXIT = 1

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
		# 勾上 = 已隐藏。先翻状态再动手：动画要跑一段时间，期间菜单还能再点，
		# 状态没先翻的话会把同一个方向重复触发一遍。
		var hidden := is_item_checked(ID_HIDE)
		set_item_checked(ID_HIDE, not hidden)
		if hidden:
			_show_with_run_in()
		else:
			_hide_with_run_out()
	elif id == ID_EXIT:
		# 先跑出屏幕，跑完才真的退。这段时间进程还活着。
		var ee = _enter_exit()
		if ee:
			ee.run_out(func(): get_tree().quit())
		else:
			get_tree().quit()

## 入场 / 退场效果挂在根节点上（window.gd 里建的）。拿不到就退回原来的瞬间切换 ——
## 动画是锦上添花，不该因为它没建起来就退不了程序、藏不了窗口。
func _enter_exit():
	return $"../..".enter_exit

## 藏起来：跑出屏幕之后才隐藏 + 暂停。
##
## 顺序不能反。get_tree().paused = true 会把 Tween 一起停掉 —— 先暂停的话她会卡死在
## 半路上，下次显示出来就是站在屏幕边缘不动。
##
## 手动隐藏和别的程序全屏走的是同一套，抽出来共用：这个顺序错一次就是个不好查的
## bug，不该在两个地方各写一遍等着漏。
func _hide_with_run_out() -> void:
	var ee = _enter_exit()
	if ee:
		ee.run_out(_apply_hidden)
	else:
		_apply_hidden()

## 叫回来：先解除暂停、先显示，她才跑得动、也才看得见。
func _show_with_run_in() -> void:
	get_tree().paused = false
	$"../..".visible = true
	var ee = _enter_exit()
	if ee:
		ee.run_in()

func _apply_hidden() -> void:
	$"../..".visible = false
	get_tree().paused = true

func _on_other_app_fullscreen(is_fullscreen):
	if is_fullscreen:
		if is_item_checked(ID_HIDE):
			return
		# 状态先标记上：全屏检测每 0.5 秒轮询一次，而退场要跑一秒上下，
		# 期间会再触发好几次，不先标记就会反复重启动画。
		set_item_checked(ID_HIDE, true)
		_is_fullscreen_hide = true
		_hide_with_run_out()
	else:
		if _is_fullscreen_hide:
			set_item_checked(ID_HIDE, false)
			_is_fullscreen_hide = false
			_show_with_run_in()

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
