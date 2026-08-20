extends Window

## 聊天记录窗口的外壳：只管开关和「打开时刷新一次」。
##
## 入口是聊天栏最左边那个按钮 —— 它本来就带着图标和「打开聊天窗口」的提示，
## 但一直没接任何东西，是个死按钮。这里把它接上。

@onready var _panel = $Root

func _ready() -> void:
	$"Root/VBoxContainer/TitleBar/MarginContainer/HBoxContainer/CloseButton".pressed.connect(_on_close_pressed)

func toggle() -> void:
	if visible:
		visible = false
		return
	_panel.refresh()
	visible = true

## 每轮对话前后由 chatbar 调用。窗口没开就不用白刷。
##
## 走增量而不是全量：全量重建的代价随消息数线性增长（300 条要 546ms），
## 而每轮新增的只有一两条。
func refresh_if_open() -> void:
	if visible:
		_panel.sync()

func _on_close_pressed() -> void:
	visible = false
