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
	# 跟托盘的退出走同一套：先跑出屏幕，跑完才真的退。
	# 拿不到效果节点就照旧直接退 —— 动画不该成为退不掉程序的理由。
	var root := get_tree().root.get_node_or_null("Node2D")
	if root and root.enter_exit:
		root.enter_exit.run_out(func(): get_tree().quit())
	else:
		get_tree().quit()

