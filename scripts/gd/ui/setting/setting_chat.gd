extends Node

## 聊天设置。
##
## 这一页原先有 12 个字段：地址、路由、端口、Key、模型名、Prompt，加上深度思考、
## 流式输出、温度系数、最大 Token、最大上下文五个带勾选框的进阶项。现在只剩四个：
## 地址、Key、模型、Prompt。删掉的东西分三类：
##
## 一、本来就是内部实现漏给了用户
##   路由固定是 /chat/completions（OpenAI 兼容标准），端口能从协议推出来。
##   现在只填一个基础地址，由 BaseChatClient.parse_base_url 拆出主机/端口/路由。
##
## 二、该由模型自己决定的
##   深度思考：要不要推理是模型的属性 —— 选 deepseek-reasoner 就是推理模型。
##   而且 Doro 的人设是「呆，反应总慢半拍」，让她深度思考本身就自相矛盾。
##
## 三、不填反而更好的
##   温度、最大 Token、最大上下文：一律不发这几个参数，用服务商的默认值。
##   现在的模型上下文都很大，聊天很难聊到上限；真撞上了由 chatbar 丢掉一半历史
##   重试一次，比让用户去猜该填多少更靠得住。
##
## 流式输出则是固定开启（见 BaseChatClient._stream 的说明）。

@onready var _config: ConfigManager = get_node("/root/Config")
var _section: ConfigSection

@onready var _chat_client: OpenAIChatClient = get_node("/root/Node2D/OpenAIChatClient")

@onready var _url_edit: LineEdit = $API/LineEdit
@onready var _key_edit: LineEdit = $Key/LineEdit
@onready var _model_edit: LineEdit = $Name/LineEdit
@onready var _pick_btn: Button = $Name/PickButton
@onready var _fetch_btn: Button = $FetchButton
@onready var _status: Label = $FetchStatus
@onready var _prompt_edit: TextEdit = $Prompt/TextEdit

var _http: HTTPRequest
var _menu: PopupMenu
var _models: Array[String] = []

func _ready() -> void:
	_section = _config.add_section(&"chat")

	_migrate_old_keys()
	_migrate_default_prompt()
	_bind_components()
	_config.save_config()
	_section.load_props()
	_load_config()
	_set_up_fetch()

## 老版本把地址拆成 url + route + port 三个键，新版只要一个基础地址，这里合回去。
##
## 不需要额外的版本标记：只要配置里还有 route 这个键，就说明没合过。合完之后
## ConfigManager 的废弃键清理会把 route / port 删掉，下次启动自然不会再进来。
##
## 端口必须一起考虑：本地 Ollama 那类配置是 http://127.0.0.1 + 11434，
## 光把 url 和 route 接起来会丢掉端口，聊天直接连不上。
func _migrate_old_keys() -> void:
	var old_route = _config.get_value("chat", "route", "")
	if not (old_route is String) or String(old_route).is_empty():
		return

	var host := String(_config.get_value("chat", "url", ""))
	if host.is_empty():
		return

	var port := int(_config.get_value("chat", "port", -1))
	var is_https := host.to_lower().begins_with("https://")
	var default_port := 443 if is_https else 80
	if port > 0 and port != default_port:
		host += ":" + str(port)

	# route 里除 /chat/completions 之外的部分是路径前缀（比如 /v1），要保留
	var prefix := String(old_route)
	if prefix.to_lower().ends_with("/chat/completions"):
		prefix = prefix.substr(0, prefix.length() - "/chat/completions".length())

	_config.set_value("chat", "url", host + prefix)

## 把还停留在旧版内置人设上的用户换到新版人设。
##
## prompt 存在用户自己的 config.ini 里，而 load_props() 只在「配置里没有这个键」时才写
## 默认值。所以光改场景里的默认 prompt，老用户是一辈子都看不到的 —— 他们配置里那份
## 旧的会一直生效。
##
## 但也绝不能无条件覆盖：有人可能自己重写了人设，那是他的心血。判据是看里面有没有
## 旧版内置人设特有的【】小节标题 —— 历代内置 prompt 都用这套结构（【你是谁】
## 【长相】【性格】【最爱】【怎么说话】），而自己写的人设几乎不会恰好也用它。
## 两个都命中才动手，尽量减少误伤。
##
## 代价说清楚：如果有人是在旧版内置人设上改了几句、又保留了那套小节标题，
## 他的改动会被这次覆盖掉。这是我在「让所有人拿到新人设」和「绝不碰任何人的修改」
## 之间选的折中。
const OLD_PROMPT_MARKERS := ["【你是谁】", "【怎么说话】"]

func _migrate_default_prompt() -> void:
	var stored := String(_config.get_value("chat", "prompt", ""))
	if stored.is_empty():
		return
	for marker in OLD_PROMPT_MARKERS:
		if not stored.contains(marker):
			return
	_config.set_value("chat", "prompt", _chat_client.get_prompt())

func _bind_components():
	# 默认值取自场景里 OpenAIChatClient 节点上配好的值，不要写死成 ""。
	# load_props() 的逻辑是「配置文件里没有就写入默认值」，填空串会导致新机器
	# 第一次打开时接口地址和人设被清空。
	_section.set_prop(&"url", String(_chat_client.get_url()))
	_section.bind(&"url").with(_update_url).to_line_edit(_url_edit)

	# api_key 不设内置默认值：它是每个用户自己的凭据，不该随安装包分发
	_section.set_prop(&"api_key", "")
	_section.bind(&"api_key").with(_update_api_key).to_line_edit(_key_edit)

	_section.set_prop(&"model_name", String(_chat_client.get_model()))
	_section.bind(&"model_name").with(_update_model_name).to_line_edit(_model_edit)

	_section.set_prop(&"prompt", _chat_client.get_prompt())
	_section.bind(&"prompt").with(_update_prompt).to_text_edit(_prompt_edit)

func _load_config():
	_url_edit.set_text(_section.get_prop(&"url"))
	_chat_client.set_base_url(_section.get_prop(&"url"))
	_key_edit.set_text(_section.get_prop(&"api_key"))
	_chat_client.set_api_key(_section.get_prop(&"api_key"))
	_model_edit.set_text(_section.get_prop(&"model_name"))
	_chat_client.set_model(_section.get_prop(&"model_name"))
	_prompt_edit.set_text(_section.get_prop(&"prompt"))
	_chat_client.set_prompt(_section.get_prop(&"prompt"))

func _update_url(_name, value):
	_chat_client.set_base_url(value)

func _update_api_key(_name, value):
	_chat_client.set_api_key(value)

func _update_model_name(_name, value):
	_chat_client.set_model(value)

func _update_prompt(_name, value):
	_chat_client.set_prompt(value)

# ---------------------------------------------------------------- 获取模型列表

func _set_up_fetch() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_models_received)

	_menu = PopupMenu.new()
	add_child(_menu)
	_menu.id_pressed.connect(_on_model_picked)

	_fetch_btn.pressed.connect(_on_fetch_pressed)
	_pick_btn.pressed.connect(_on_pick_pressed)

func _on_fetch_pressed() -> void:
	var base := _url_edit.text.strip_edges()
	if base.is_empty():
		_status.text = "先填 API 地址。"
		return
	if _key_edit.text.strip_edges().is_empty():
		_status.text = "先填 API Key。"
		return

	var p: Dictionary = BaseChatClient.parse_base_url(base)
	var url: String = p["host"]
	if p["port"] != 443 and p["port"] != 80:
		url += ":" + str(p["port"])
	url += String(p["prefix"]) + "/models"

	_status.text = "正在连接……"
	_fetch_btn.disabled = true
	var err := _http.request(url, [
		"Authorization: Bearer " + _key_edit.text.strip_edges(),
	], HTTPClient.METHOD_GET)
	if err != OK:
		_fetch_btn.disabled = false
		_status.text = "请求发不出去（地址格式不对？）。"

func _on_models_received(result: int, code: int, _headers, body: PackedByteArray) -> void:
	_fetch_btn.disabled = false

	if result != HTTPRequest.RESULT_SUCCESS:
		_status.text = "连不上，检查网络和 API 地址。"
		return
	if code == 401 or code == 403:
		_status.text = "API Key 不对（接口返回 %d）。" % code
		return
	if code != 200:
		_status.text = "接口返回 %d，这个地址可能不支持列出模型。可以直接手填模型名。" % code
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	_models = _extract_model_ids(parsed)
	if _models.is_empty():
		_status.text = "连上了，但没解析出模型列表。可以直接手填模型名。"
		_pick_btn.disabled = true
		return

	_status.text = "已连接，找到 %d 个模型。" % _models.size()
	_pick_btn.disabled = false
	_pick_btn.tooltip_text = "从获取到的 %d 个模型里选" % _models.size()

	# 当前填的模型名不在列表里时提醒一句，否则用户要等到第一次说话才发现填错了
	if not _model_edit.text.strip_edges() in _models:
		_status.text += "当前填的「%s」不在列表里。" % _model_edit.text.strip_edges()

## 兼容两种常见返回形状：OpenAI 兼容接口是 {"data":[{"id":...}]}，
## 少数自建服务用 {"models":[{"name":...}]}。
static func _extract_model_ids(parsed) -> Array[String]:
	var out: Array[String] = []
	if not parsed is Dictionary:
		return out
	for key in ["data", "models"]:
		if not parsed.has(key) or not parsed[key] is Array:
			continue
		for item in parsed[key]:
			if item is Dictionary:
				for field in ["id", "name", "model"]:
					if item.has(field) and item[field] is String:
						out.append(item[field])
						break
			elif item is String:
				out.append(item)
		if not out.is_empty():
			break
	out.sort()
	return out

func _on_pick_pressed() -> void:
	if _models.is_empty():
		return
	_menu.clear()
	for i in _models.size():
		_menu.add_item(_models[i], i)
	# 贴着按钮左下角弹出
	var r := _pick_btn.get_screen_position()
	_menu.position = Vector2i(int(r.x), int(r.y + _pick_btn.size.y))
	_menu.reset_size()
	_menu.popup()

func _on_model_picked(id: int) -> void:
	if id < 0 or id >= _models.size():
		return
	_model_edit.text = _models[id]
	# LineEdit 的绑定默认在失去焦点时才触发，这里是代码改的值，得自己通知一次
	_section.set_prop(&"model_name", _models[id])
	_config.set_value("chat", "model_name", _models[id])
	_config.save_config()
	_chat_client.set_model(_models[id])
	_status.text = "已选择 %s。" % _models[id]
