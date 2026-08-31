extends Control

## 标题栏：显示标题 + 按住拖动窗口。
##
## extends Control 而不是 Panel：这份逻辑要给好几个标题栏共用，只依赖 Control 就够。
## 脚本的 extends 必须是节点类型的祖先，否则 Godot 会直接不挂脚本 —— 这个坑踩过。
##
## 设置窗口和更新提示框的标题栏原先是 NinePatchRect（贴一张纯色方块图 bg_sharp.png），
## 所以四个角是直的，跟别的窗口不一致。现在都改成 Panel + pink_titlebar.tres，
## 跟聊天记录窗口用同一份样式，圆角和颜色自然一致。

@export var title: StringName

var drag_start_mouse_pos: Vector2i
var drag_start_window_pos: Vector2i
var dragging: bool = false

func _ready() -> void:
	$MarginContainer/HBoxContainer/Label.set_text(title)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if get_global_rect().has_point(event.global_position):
					dragging = true
					drag_start_mouse_pos = DisplayServer.mouse_get_position()
					drag_start_window_pos = $"../../../".position
			else:
				dragging = false
				
	if event is InputEventMouseMotion and dragging:
		var cur_mouse_pos = DisplayServer.mouse_get_position()
		var delta_pos = cur_mouse_pos - drag_start_mouse_pos
		$"../../../".position = drag_start_window_pos + delta_pos
		
func set_close_button_visibility(visible: bool):
	$MarginContainer/HBoxContainer/CloseButton.visible = visible
