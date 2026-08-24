extends Panel


func _ready() -> void:
	$"../Chatbar/MarginContainer/HBoxContainer/BackButton".pressed.connect(on_chat_bar_back_button_pressed)
	$"Buttons/ChatButton".pressed.connect(on_chat_button_pressed)
	
func on_chat_button_pressed():
	$"../Chatbar".visible = true
	visible = false
	# 点开聊天栏就是要打字了。主窗口设了 no_focus，不会自己拿到键盘焦点，
	# 得主动要一次 —— 原因见 chatbar.focus_input() 的注释。
	$"../Chatbar".focus_input()
	
func on_chat_bar_back_button_pressed():
	$"../Chatbar".visible = false
	visible = true

func _on_exit_button_pressed() -> void:
	get_tree().quit()

