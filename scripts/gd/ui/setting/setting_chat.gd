extends Node

@onready var _config: ConfigManager = get_node("/root/Config")
var _section: ConfigSection 

@onready var _chat_client: OpenAIChatClient = get_node("/root/Node2D/OpenAIChatClient")
@onready var _context_manager: ContextManager = get_node("/root/Node2D/OpenAIChatClient/ContextManager")

func _ready() -> void:
	_section = _config.add_section(&"chat")
	
	_bind_components()
	_config.save_config()
	_section.load_props()
	_load_config()

func _bind_components():
	# 这几项的默认值一律取自场景里 OpenAIChatClient 节点上配好的值，不要写死成 ""。
	#
	# 原先全填空串，而 load_props() 的逻辑是"配置文件里没有就写入默认值"，于是首次运行
	# 会把空串写进 config.ini，再由 _load_config() 回灌给客户端 —— 场景里配好的接口地址
	# 和 Doro 人设在新机器上第一次打开就被清空了，聊天必然连不上、桌宠也没有性格设定。
	# 而 config.ini 存在 user:// 里不随安装包分发，所以这个坑对每个新用户都会踩到。
	# 客户端上这几个字段声明成 StringName，必须转成 String 再存：
	# 绑定到 LineEdit 的值断言要求是 String，直接塞 StringName 会触发断言失败，
	# 而且会以 &"..." 的形式写进 config.ini。
	_section.set_prop(&"url", String(_chat_client.get_url()))
	_section.bind(&"url").with(_update_url).to_line_edit($API/LineEdit)

	_section.set_prop(&"route", String(_chat_client.get_route()))
	_section.bind(&"route").with(_update_route).to_line_edit($Route/LineEdit)

	_section.set_prop(&"port", float(_chat_client.get_port()))
	_section.bind(&"port").with(_update_port).to_spin_box($Port/SpinBox)

	# api_key 不设内置默认值：它是每个用户自己的凭据，不应随安装包分发
	_section.set_prop(&"api_key", "")
	_section.bind(&"api_key").with(_update_api_key).to_line_edit($Key/LineEdit)

	_section.set_prop(&"model_name", String(_chat_client.get_model()))
	_section.bind(&"model_name").with(_update_model_name).to_line_edit($Name/LineEdit)

	_section.set_prop(&"prompt", _chat_client.get_prompt())
	_section.bind(&"prompt").with(_update_prompt).to_text_edit($Prompt/TextEdit)
	
	_section.set_prop(&"thinking", false)
	_section.bind(&"thinking").with(_update_thinking).to_check_box($ThinkingCheckbox)
	
	_section.set_prop(&"stream", false)
	_section.bind(&"stream").with(_update_stream).to_check_box($StreamCheckbox)
	
	_section.set_prop(&"temperature_enable", false)
	_section.bind(&"temperature_enable").with(_update_temperature_enable).to_check_box($Temperature/TemperatureCheckbox)
	_section.bind(&"temperature_enable").to($Temperature/SpinBox, "editable")
	_section.set_prop(&"temperature", 0.7)
	_section.bind(&"temperature").with(_update_temperature).to_spin_box($Temperature/SpinBox)
	
	_section.set_prop(&"max_token_enable", false)
	_section.bind(&"max_token_enable").with(_update_max_token_enable).to_check_box($MaxToken/MaxTokenCheckbox)
	_section.bind(&"max_token_enable").to($MaxToken/SpinBox, "editable")
	_section.set_prop(&"max_token", 100.0)
	_section.bind(&"max_token").with(_update_max_token).to_spin_box($MaxToken/SpinBox)
	
	_section.set_prop(&"max_context_enable", false)
	_section.bind(&"max_context_enable").with(_update_max_context_enable).to_check_box($MaxContext/MaxContextCheckbox)
	_section.bind(&"max_context_enable").to($MaxContext/SpinBox, "editable")
	_section.set_prop(&"max_context", 5.0)
	_section.bind(&"max_context").with(_update_max_context).to_spin_box($MaxContext/SpinBox)
	
func _load_config():
	$API/LineEdit.set_text(_section.get_prop(&"url"))
	_chat_client.set_url(_section.get_prop(&"url"))
	$Route/LineEdit.set_text(_section.get_prop(&"route"))
	_chat_client.set_route(_section.get_prop(&"route"))
	$Port/SpinBox.set_value_no_signal(_section.get_prop(&"port"))
	_chat_client.set_port(_section.get_prop(&"port"))
	$Key/LineEdit.set_text(_section.get_prop(&"api_key"))
	_chat_client.set_api_key(_section.get_prop(&"api_key"))
	$Name/LineEdit.set_text(_section.get_prop(&"model_name"))
	_chat_client.set_model(_section.get_prop(&"model_name"))
	$Prompt/TextEdit.set_text(_section.get_prop(&"prompt"))
	_chat_client.set_prompt(_section.get_prop(&"prompt"))
	
	$ThinkingCheckbox.set_pressed_no_signal(_section.get_prop(&"thinking"))
	_chat_client.set_thinking(_section.get_prop(&"thinking"))
	
	$StreamCheckbox.set_pressed_no_signal(_section.get_prop(&"stream"))
	_chat_client.set_stream(_section.get_prop(&"stream"))
	
	$Temperature/TemperatureCheckbox.set_pressed_no_signal(_section.get_prop(&"temperature_enable"))
	$Temperature/SpinBox.editable = _section.get_prop(&"temperature_enable")
	_chat_client.set_temperature_enable(_section.get_prop(&"temperature_enable"))
	$Temperature/SpinBox.set_value_no_signal(_section.get_prop(&"temperature"))
	_chat_client.set_temperature(_section.get_prop(&"temperature"))
	
	$MaxToken/MaxTokenCheckbox.set_pressed_no_signal(_section.get_prop(&"max_token_enable"))
	$MaxToken/SpinBox.editable = _section.get_prop(&"max_token_enable")
	_chat_client.set_max_token_enable(_section.get_prop(&"max_token_enable"))
	$MaxToken/SpinBox.set_value_no_signal(_section.get_prop(&"max_token"))
	_chat_client.set_max_token(_section.get_prop(&"max_token"))
	
	$MaxContext/MaxContextCheckbox.set_pressed_no_signal(_section.get_prop(&"max_context_enable"))
	$MaxContext/SpinBox.editable = _section.get_prop(&"max_context_enable")
	_context_manager.set_max_context_enable(_section.get_prop(&"max_context_enable"))
	$MaxContext/SpinBox.set_value_no_signal(_section.get_prop(&"max_context"))
	_context_manager.set_max_context(_section.get_prop(&"max_context"))

func _update_url(name, value):
	_chat_client.set_url(value)
	
func _update_route(name, value):
	_chat_client.set_route(value)
	
func _update_port(name, value):
	_chat_client.set_port(value)

func _update_api_key(name, value):
	_chat_client.set_api_key(value)
	
func _update_model_name(name, value):
	_chat_client.set_model(value)
	
func _update_prompt(name, value):
	_chat_client.set_prompt(value)
	
func _update_thinking(name, value):
	_chat_client.set_thinking(value)
	
func _update_stream(name, value):
	_chat_client.set_stream(value)
	
func _update_temperature_enable(name, value):
	_chat_client.set_temperature_enable(value)
	
func _update_temperature(name, value):
	_chat_client.set_temperature(value)
	
func _update_max_token_enable(name, value):
	_chat_client.set_max_token_enable(value)
	
func _update_max_token(name, value):
	_chat_client.set_max_token(value)
	
func _update_max_context_enable(name, value):
	_context_manager.set_max_context_enable(value)
	
func _update_max_context(name, value):
	_context_manager.set_max_context(value)
