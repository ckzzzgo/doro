extends Node
class_name BaseChatClient

@export var _url: StringName
@export var _route: StringName
@export var _port: int = -1

@export var _api_key:StringName = ""
@export var _model_name: StringName
@export var _prompt: String

@export var _thinking: bool = false
@export var _stream: bool = false
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
	
func _connect():
	pass
	
func _disconnect():
	pass
	
func generate(message: String, stream=true):
	pass
	
func chat(message: String):
	pass
	
func cancel():
	pass
	
func _process_response():
	pass
	
func set_api_key(key: String):
	_api_key = key
	
func get_api_key():
	return _api_key
	
func set_prompt(prompt: String):
	_prompt = prompt
	
func get_prompt():
	return _prompt
	
## 接口地址只保留「协议 + 主机」。
##
## HTTPClient.connect_to_host 只接受主机名，用户若把 https://api.deepseek.com/v1 这类
## 带路径的完整地址整个填进来，路径会被当成主机名的一部分去解析 —— 结果是连不上，
## 而且从界面上完全看不出原因。路径部分属于「路由」，那有单独的设置项。
##
## 协议前缀必须保留：TLS 判定要靠它区分 https 与 http。
func set_url(url: String):
	_url = _host_only(url)

func get_url():
	return _url

var _warned_dropped_path: String = ""

func _host_only(url: String) -> String:
	var rest := url.strip_edges()
	var scheme := ""
	var lower := rest.to_lower()
	if lower.begins_with("https://"):
		scheme = rest.substr(0, 8)
		rest = rest.substr(8)
	elif lower.begins_with("http://"):
		scheme = rest.substr(0, 7)
		rest = rest.substr(7)

	var slash := rest.find("/")
	if slash >= 0:
		var dropped := rest.substr(slash)
		rest = rest.substr(0, slash)
		# 单个结尾斜杠是常见手误，不值得提示；真带了路径才说一声，且同一路径只说一次
		if dropped != "/" and _warned_dropped_path != dropped:
			_warned_dropped_path = dropped
			push_warning(
				"接口地址里的路径「%s」已被忽略：地址栏只填协议和域名，路径请填到「路由」里。" % dropped
			)

	return scheme + rest
	
func set_port(port: int):
	_port = port
	
func set_route(route: String):
	_route = route
	
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
