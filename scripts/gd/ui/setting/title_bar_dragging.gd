extends Control

## 标题栏：显示标题 + 按住拖动窗口。
##
## 刻意 extends Control 而不是某个具体控件：设置窗口的标题栏是 NinePatchRect（贴图），
## DORO 窗口的是 Panel（StyleBox，为了做上圆角），两者都是 Control，共用这一份逻辑。
## 脚本的 extends 必须是节点类型的祖先，否则 Godot 会直接不挂脚本 —— 这个坑刚踩过。

@export var title: StringName
@export var show_close_button: bool = true

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
