extends NinePatchRect


func _ready() -> void:
	$"../Chatbar/MarginContainer/HBoxContainer/BackButton".pressed.connect(on_chat_bar_back_button_pressed)
	$"Buttons/ChatButton".pressed.connect(on_chat_button_pressed)
	
func on_chat_button_pressed():
	$"../Chatbar".visible = true
	visible = false
	
func on_chat_bar_back_button_pressed():
	$"../Chatbar".visible = false
	visible = true

func _on_exit_button_pressed() -> void:
	get_tree().quit()

