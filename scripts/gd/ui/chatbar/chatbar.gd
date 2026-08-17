extends Node

@export var chat_client: OpenAIChatClient
@export var context_manager: ContextManager
@export var line_edit: LineEdit
@export var send_btn: Button
@export var stop_btn: Button
@export var chat_dialog: Window

@onready var _config: ConfigManager = get_node("/root/Config")

func _ready() -> void:
	chat_client.on_response.connect(_on_response)
	chat_client.on_finish.connect(_on_finish)

func _on_send_button_pressed():
	var text = line_edit.get_text()
	if text.strip_edges().is_empty():
		return

	# 配置不全时不要去连接：否则只会得到一句笼统的"无法连接API"，新用户根本
	# 不知道是自己没填 API Key。这里让 Doro 自己说缺什么、去哪填。
	# 刻意不清空输入框，用户填好设置后可以直接再点发送。
	var hint := _chat_config_hint()
	if not hint.is_empty():
		chat_dialog.clear_text()
		_on_response(hint)
		return

	if chat_client.chat(text, context_manager.get_context()):
		context_manager.add_context(ContextManager.ROLE_USER, line_edit.text)
		line_edit.clear()
		chat_dialog.clear_text()
		send_btn.visible = false
		stop_btn.visible = true
	else:
		chat_dialog.clear_text()
		_on_response("错误：无法连接API")
	
func _on_stop_button_pressed():
	chat_client.cancel()
	
func _on_clear_button_pressed():
	context_manager.clear_context()
	
func _on_response(data: String):
	chat_dialog.show()
	chat_dialog.append_text(data)
	
func _on_finish():
	var response_text = chat_dialog.get_text()
	# 连接失败等异常路径下对话内容可能是错误提示，不应作为助手回复写入历史。
	if not response_text.is_empty():
		context_manager.add_context(ContextManager.ROLE_ASSISTANT, response_text)
	send_btn.visible = true
	stop_btn.visible = false

func _on_line_edit_text_submitted(new_text: String):
	_on_send_button_pressed()

## 聊天配置缺项检查。返回一句以 Doro 口吻写的提示；配置齐全时返回空串。
## API Key 属于每个用户自己的凭据，不随安装包分发，所以新装的用户必定先撞到这一条。
func _chat_config_hint() -> String:
	if String(chat_client.get_api_key()).strip_edges().is_empty():
		return "人，你还没给我钥匙呢……\n\n用聊天框左边的返回按钮回到工具栏，点「设置」→「聊天」，把 API Key 填进去，我就能说话了。"
	if String(chat_client.get_url()).strip_edges().is_empty():
		return "人，我不知道该去哪儿找我的脑子……\n\n「设置」→「聊天」里的接口地址还是空的。"
	if String(chat_client.get_model()).strip_edges().is_empty():
		return "人，「设置」→「聊天」里的模型名还没填，我不知道该用哪个脑子。"
	return ""
