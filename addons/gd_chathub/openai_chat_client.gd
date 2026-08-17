extends BaseChatClient
class_name OpenAIChatClient

var _chat_http: HTTPClient = HTTPClient.new()
var _response_parser: ResponseParser = ResponseParser.new()
var _last_http_status: int = 0

var _temperature_enable: bool = false
var _max_token_enable: bool = false

# 非阻塞连接状态：_connecting 为 true 时，连接在 _process 中推进；
# 连接成功后立即发送缓存的待发消息/上下文，全程不阻塞主线程。
var _connecting: bool = false
var _connect_start_time: float = 0.0
var _pending_message: String = ""
var _pending_context: Array = []

func _ready() -> void:
	_response_parser.on_thinking.connect(_emit_on_thinking)
	_response_parser.on_response.connect(_emit_on_response)
	_response_parser.on_error.connect(_emit_on_response)
	_response_parser.on_finish.connect(_on_process_response_finished)

func _disconnect():
	_chat_http.close()
	_connected = false
	_connecting = false

func chat(message: String, context: Array[Dictionary] = []):
	if _processing or _connecting:
		return false

	var err = _chat_http.connect_to_host(_url, _port, _tls_options_for(_url, _port))
	if err != OK:
		_connected = false
		_processing = false
		return false

	# 非阻塞：记录待发消息，连接成功后由 _process 自动发送。
	_connecting = true
	_connect_start_time = Time.get_ticks_msec() / 1000.0
	_pending_message = message
	_pending_context = context
	return true

## 决定这次连接是否走 TLS。
##
## Godot 的 HTTPClient 只有显式传入 tls_options 才会加密，光把地址写成 https://
## 是不会走 TLS 的 —— 而 _send() 的请求头里带着 Authorization: Bearer <api_key>，
## 不加密就等于把 key 明文发上网。
##
## 判定保持保守：只有 https:// 或 443 端口才启用 TLS。默认配置指向本机 Ollama
## （http://127.0.0.1），对它强制 TLS 会直接连不上，所以 http:// 一律保持明文。
func _tls_options_for(url: String, port: int) -> TLSOptions:
	var lower := url.to_lower()
	if lower.begins_with("http://"):
		_warn_if_key_exposed(url)
		return null
	if lower.begins_with("https://") or port == 443:
		return TLSOptions.client()
	_warn_if_key_exposed(url)
	return null

## 明文连接 + 非本机地址 + 配了 key，才提示：这种组合下 key 会明文出网。
## 只提示一次：chat() 每发一条消息都会走到这里，否则会刷满日志。
var _warned_plaintext_for: String = ""

func _warn_if_key_exposed(url: String) -> void:
	if _api_key.is_empty():
		return
	if _warned_plaintext_for == url:
		return
	var host := url.to_lower().trim_prefix("http://").trim_prefix("https://")
	if host.begins_with("127.0.0.1") or host.begins_with("localhost") or host.begins_with("[::1]"):
		return
	_warned_plaintext_for = url
	push_warning(
		"聊天接口使用明文连接（%s），API key 会以明文发送。若目标支持 HTTPS，请把地址改为 https:// 或把端口设为 443。" % url
	)

func cancel():
	_processing = false
	_connecting = false
	_response_parser.clear_cache()
	_disconnect()
	_on_process_response_finished()

func _send(api: String, message, context: Array[Dictionary] = []):
	if _processing:
		return false
		
	if !_connected:
		return false
		
	_processing = true
	_last_http_status = -1
	_response_parser.clear_cache()
		
	var data = {
		"model": _model_name,
		"messages": [
			{
			  "role": "system",
			  "content": _prompt,
			}
		],
		"stream": _stream,
	}

	# thinking 不是 OpenAI 兼容接口的标准字段，多数官方接口（DeepSeek 等）遇到未知
	# 顶层参数会直接返回 400。这里与下面的 temperature / max_tokens 保持一致：
	# 只在真正开启时才带上，关闭时干脆不发这个字段。
	if _thinking:
		data["thinking"] = {"type": "enabled"}

	if _temperature_enable:
		data["temperature"] = _temperature
	
	if _max_token_enable:
		data["max_tokens"] = _max_token
	
	data["messages"].append_array(context)
	data["messages"].append({"role": "user", "content": message})
	
	_chat_http.request(
		HTTPClient.METHOD_POST, 
		api, 
		[
			"Content-Type: application/json",
			"Authorization: Bearer {0}".format([_api_key]),
		], 
		JSON.stringify(data)
	)
	
	return true
	
func _process(delta: float) -> void:
	# 连接推进阶段：不阻塞主线程，按帧轮询连接状态，超时或失败时通知 UI。
	if _connecting:
		_chat_http.poll()
		var status = _chat_http.get_status()
		var elapsed = (Time.get_ticks_msec() / 1000.0) - _connect_start_time
		
		if status == HTTPClient.STATUS_CONNECTED:
			_connecting = false
			_connected = true
			_send(_route, _pending_message, _pending_context)
		elif elapsed >= _connect_timeout or status == HTTPClient.STATUS_CONNECTION_ERROR or status == HTTPClient.STATUS_CANT_CONNECT:
			print("[DORO] chat connect failed (timeout=%s status=%s)" % [str(elapsed >= _connect_timeout), str(status)])
			_connecting = false
			_connected = false
			_processing = false
			_response_parser.clear_cache()
			_disconnect()
			on_response.emit("错误：无法连接API")
			on_finish.emit()
		return

	if _connected and _processing:
		_chat_http.poll()
		var http_status = _chat_http.get_status()
		if _chat_http.has_response() and http_status == HTTPClient.STATUS_BODY:
			var chunk = _chat_http.read_response_body_chunk()
			if chunk.size() > 0:
				var response = chunk.get_string_from_utf8()
				if _stream:
					_response_parser.process_stream(response)
				else:
					_response_parser.process(response)
		
		if http_status != HTTPClient.STATUS_BODY and _last_http_status == HTTPClient.STATUS_BODY:
			_on_process_response_finished()
			
		_last_http_status = http_status

func _on_process_response_finished():
	_processing = false
	_last_http_status = -1
	_response_parser.clear_cache()
	_disconnect()
	on_finish.emit()

func _emit_on_response(content: String):
	on_response.emit(content)
	
func _emit_on_thinking(content: String):
	on_thinking.emit(content)

func set_temperature_enable(enable: bool):
	_temperature_enable = enable
	
func get_temperature_enable():
	return _temperature_enable
	
func set_max_token_enable(enable: bool):
	_max_token_enable = enable
	
func get_max_token_enable(enable: bool):
	return _max_token_enable
