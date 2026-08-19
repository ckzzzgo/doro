extends Node

@export var chat_client: OpenAIChatClient
@export var context_manager: ContextManager
@export var line_edit: LineEdit
@export var send_btn: Button
@export var stop_btn: Button
@export var chat_dialog: Window

@onready var _config: ConfigManager = get_node("/root/Config")

## 上一句发出去的话。撞上上下文上限时要用它重发一次。
var _last_sent: String = ""
## 一轮对话里只允许因为上下文超长重试一次，避免来回死循环。
var _retried_overflow: bool = false
## 溢出重试要等客户端这一轮收完再发，见 _on_finish。
var _pending_overflow_retry: bool = false
## 当前显示在对话框里的是报错而不是回复，不能写进聊天历史。
var _showing_error: bool = false
## 正在显示「她在想」的占位提示。
var _thinking_shown: bool = false

func _ready() -> void:
	chat_client.on_response.connect(_on_response)
	chat_client.on_finish.connect(_on_finish)
	chat_client.on_context_overflow.connect(_on_context_overflow)
	chat_client.on_api_error.connect(_on_api_error)
	chat_client.on_thinking.connect(_on_thinking)

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
		_last_sent = text
		_retried_overflow = false
		_showing_error = false
		_thinking_shown = false
		context_manager.add_context(ContextManager.ROLE_USER, line_edit.text)
		# 立刻刷一次记录窗口：不刷的话自己发的那句要等她回完才出现，
		# 开着记录窗口时看起来就像「没同步进去」。
		_history_window().refresh_if_open()
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
	_retried_overflow = false
	_pending_overflow_retry = false
	_history_window().refresh_if_open()
	
func _on_response(data: String):
	# 推理模型会先想一会儿再开口。真内容一来就把「在想」的占位换掉。
	if _thinking_shown:
		_thinking_shown = false
		chat_dialog.clear_text()
	chat_dialog.show()
	chat_dialog.append_text(data)
	
func _on_finish():
	# 溢出重试放在这里发：溢出信号是在解析途中发出来的，那时客户端还处于
	# _processing 状态，立刻再调 chat() 会被直接拒掉。必须等这一轮收完。
	if _pending_overflow_retry:
		_pending_overflow_retry = false
		if chat_client.chat(_last_sent, context_manager.get_context()):
			return
		_showing_error = true
		chat_dialog.clear_text()
		_on_response("诶……我有点想不起来前面聊了啥。")

	var response_text = chat_dialog.get_text()
	# 连接失败等异常路径下对话内容可能是错误提示，不应作为助手回复写入历史。
	if not response_text.is_empty() and not _showing_error:
		context_manager.add_context(ContextManager.ROLE_ASSISTANT, response_text)
	send_btn.visible = true
	stop_btn.visible = false
	_history_window().refresh_if_open()

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


## 聊得太久、超出模型上下文上限时的处理。
##
## 刻意不做「主动按条数裁剪」：现在的模型上下文都很大，正常聊天很难撞到上限，
## 为此在界面上加个「最大上下文数量」让用户去猜该填多少，代价大于收益。这里改成
## 真撞上了才处理 —— 丢掉最旧的一半历史，静默重发刚才那句话。顺利的话用户完全
## 察觉不到，只是这一句回得慢一点。
##
## 系统 prompt 不在这份历史里（客户端每次单独拼在最前面），所以裁剪不会让她失忆到
## 忘记自己是谁。
func _on_context_overflow(_message: String) -> void:
	if _retried_overflow or _last_sent.is_empty():
		# 裁掉一半还是超，说明单轮内容本身就太长了，这时候得让用户自己动手
		_showing_error = true
		chat_dialog.clear_text()
		_on_response("诶……我们聊得太多了，我脑袋装不下啦。点一下聊天栏那个「重新开始」，咱们从头聊？")
		return

	_retried_overflow = true
	context_manager.drop_oldest_half()
	_pending_overflow_retry = true

## 其它接口错误：显示出来，但标记成「这不是 Doro 说的话」，别写进聊天历史 ——
## 否则「API Key 无效」这类句子会被当成她的上一句发回给模型。
func _on_api_error(message: String) -> void:
	_showing_error = true
	_on_response(message)


## 推理模型（deepseek-v4-flash 这类）会先输出一段思考再给答案，那段思考往往是英文的
## 自言自语，不该当成 Doro 说的话显示出来。但也不能什么都不显示 —— 思考可能持续好几秒，
## 屏幕上一片空白看起来就像卡死了（这正是「发完消息没反应」的一部分原因：
## on_thinking 以前压根没有任何人接收）。所以放一句占位，等真内容到了再换掉。
func _on_thinking(_content: String) -> void:
	if _thinking_shown or _showing_error:
		return
	_thinking_shown = true
	chat_dialog.show()
	chat_dialog.append_text("（她好像在想什么……）")


## 聊天记录窗口。气泡只显示最新一句，要回看得开这个。
func _history_window():
	return get_node("/root/Node2D/GUI/ChatHistory")

func _on_chat_window_button_pressed():
	_history_window().toggle()
