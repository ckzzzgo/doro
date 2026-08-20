extends Node
class_name BaseChatClient

@export var _url: StringName
@export var _route: StringName
@export var _port: int = -1

@export var _api_key:StringName = ""
@export var _model_name: StringName
@export var _prompt: String

@export var _thinking: bool = false

## 流式输出默认开启，界面上不再提供开关。
##
## 关掉的话是「盯着空白等三五秒、然后整段话啪地蹦出来」，开着是一个字一个字往外冒，
## 像真的在说话 —— 对桌宠来说后者明显更好，这不该是个让用户纠结的选项。
##
## 它原先默认关闭，是因为 response_parser 里残片拼接的方向写反了，开了就丢字乱序
## （详见那边的注释）。那个 bug 已修，实测 TCP 在行中间切包也能完整还原。
@export var _stream: bool = true
@export var _max_token: int = -1
@export var _temperature: float = -1

# 连接超时（秒）。原值 1 秒只够连本机端点；连远程 HTTPS 接口时，TLS 握手加跨境
# 往返经常超过 1 秒，会被判定为连接失败。
@export var _connect_timeout: int = 10

var _connected: bool = false
var _processing: bool = false

signal on_response
signal on_thinking
signal on_finish
	
## 子类要实现的：连接管理、发送、取消。
##
## 原先这里还有 _connect() / generate() / _process_response() 三个空桩，
## 但没有任何子类覆盖、也没有任何地方调用 —— 是这个基类当初照着某个模板写下来
## 却从没用上的部分，删掉。
func _disconnect():
	pass

func chat(message: String):
	pass

func cancel():
	pass
	
func set_api_key(key: String):
	_api_key = key
	
func get_api_key():
	return _api_key
	
func set_prompt(prompt: String):
	_prompt = prompt
	
func get_prompt():
	return _prompt
	
## 路径前缀，例如 https://api.openai.com/v1 里的 "/v1"。聊天和模型列表两个
## 接口都挂在它下面。
var _api_prefix: String = ""

## 用一个「基础地址」一次性设定主机、端口和路由。
##
## 原先界面上有三个字段：地址、路由、端口。后两个纯粹是把内部实现细节漏给了用户 ——
## 路由固定是 /chat/completions（OpenAI 兼容标准），端口能从协议推出来。用户只需要
## 照服务商文档粘一个基础地址，剩下的这里算。
func set_base_url(base: String) -> void:
	var p := parse_base_url(base)
	_url = p["host"]
	_port = p["port"]
	_api_prefix = p["prefix"]
	_route = p["route"]

## 模型列表接口，用于「连接并获取模型」。
func get_models_route() -> String:
	return _api_prefix + "/models"

## 拆解基础地址。写成静态纯函数，方便直接测各种写法。
##
## 认得出这些形式：
##   https://api.deepseek.com            -> 443, /chat/completions
##   https://api.openai.com/v1           -> 443, /v1/chat/completions
##   http://127.0.0.1:11434/v1           -> 11434, /v1/chat/completions
##   api.deepseek.com                    -> 没写协议时按 https
##   https://api.deepseek.com/v1/chat/completions
##                                       -> 用户把完整端点粘进来了，去掉尾巴避免拼两次
static func parse_base_url(base: String) -> Dictionary:
	var rest := base.strip_edges()
	var scheme := "https://"
	var lower := rest.to_lower()
	if lower.begins_with("https://"):
		rest = rest.substr(8)
	elif lower.begins_with("http://"):
		scheme = "http://"
		rest = rest.substr(7)

	var path := ""
	var slash := rest.find("/")
	if slash >= 0:
		path = rest.substr(slash)
		rest = rest.substr(0, slash)

	# 显式端口优先，没写就按协议默认
	var port := 443 if scheme == "https://" else 80
	var colon := rest.rfind(":")
	if colon > 0:
		var maybe := rest.substr(colon + 1)
		if maybe.is_valid_int():
			port = maybe.to_int()
			rest = rest.substr(0, colon)

	# 归一化路径前缀：去掉结尾斜杠；用户若把完整端点粘进来，去掉那段尾巴
	while path.ends_with("/"):
		path = path.substr(0, path.length() - 1)
	if path.to_lower().ends_with("/chat/completions"):
		path = path.substr(0, path.length() - "/chat/completions".length())

	return {
		"host": scheme + rest,
		"port": port,
		"prefix": path,
		"route": path + "/chat/completions",
	}

func get_url():
	return _url

func get_route():
	return _route

func get_port():
	return _port
	
func set_model(name: String):
	_model_name = name
	
func get_model():
	return _model_name

func set_max_token(max_token: int):
	_max_token = max_token
	
func get_max_token():
	return _max_token
	
func set_thinking(thinking: bool):
	_thinking = thinking
	
func get_thinking():
	return _thinking
	
func set_stream(stream: bool):
	_stream = stream
	
func get_stream():
	return _stream
	
func set_temperature(temperature: float):
	_temperature = temperature
	
func get_temperature():
	return _temperature
