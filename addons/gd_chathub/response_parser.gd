extends Node
class_name ResponseParser

var _cache: String = ""
var _json: JSON = JSON.new()

signal on_response(content: String)
signal on_thinking(content: String)
signal on_finish
signal on_error(message: String)

func process(response: String):
	if response.is_empty():
		on_finish.emit()
		return
			
	if response.begins_with("data: "):
		response = response.substr("data: ".length())
		
	if _json.parse(response) == OK:
		var data = _json.get_data()
		if data.has("error"):
			on_error.emit(data.error.message)
			
		if data.has("choices") and data.choices.size() > 0:
			var choice = data.choices[0]
			
			if choice.has("message"):
				_emit_delta(choice.message)
				
	on_finish.emit()

func process_stream(response: String):
	# 缓存必须拼在【前面】。_cache 存的是上一块数据末尾那半行没读完的 JSON，
	# 它在字节流里位于新数据之前。原来写的是 response += _cache，等于把残片接到了
	# 后面 —— 一行 JSON 被 TCP 切成两半时不但拼不回来，残片还会在错误的位置被当成
	# 独立一行去解析，结果是内容既丢字又乱序。实测（假接口故意在行中间切包）：
	#   期望「人你好呀，今天有哦润吉吃吗？」
	#   实得「人呀今天，哦润吉有吗吃」
	# 这多半就是流式输出一直默认关闭的原因。
	response = _cache + response
	_cache = ""
	
	var lines = response.split("\n")
	
	for line in lines:
		#prints("LINE: ", line)
		line = line.strip_edges()
		
		if line.is_empty():
			continue
			
		if line.begins_with("data: "):
			line = line.substr("data: ".length())
		
		if line == "[DONE]":
			#print("STOP")
			on_finish.emit()
			break
		
		if _json.parse(line) == OK:
			var data = _json.get_data()
			if data.has("error"):
				on_error.emit(data.error.message)
				
			if data.has("choices") and data.choices.size() > 0:
				var choice = data.choices[0]
				if choice.has("finish_reason") and choice.finish_reason == "stop":
					#print("STOP")
					on_finish.emit()
					break
				elif choice.has("delta"):
					_emit_delta(choice.delta)
		else:
			#print('Parse Error')
			_cache = line
			break
			

func clear_cache():
	_cache = ""


## 把一个 delta / message 里的内容分发到对应的信号。
##
## 这里必须按【值】判空，不能按键是否存在判 —— 推理模型（deepseek-v4-flash 这类）
## 每一片都同时带着 content 和 reasoning_content 两个键，只不过其中一个是 null：
##
##   "delta": {"content": null, "reasoning_content": "Okay"}
##   "delta": {"content": "汪汪", "reasoning_content": null}
##
## 原来的写法是 elif choice.delta.has("reasoning_content")，而 has() 只看键在不在。
## 于是这个分支永远命中，所有内容都被当成「思考过程」发到 on_thinking，
## 真正的回复一个字都到不了 on_response —— 表现就是发完消息毫无反应。
##
## 另外用 if 而不是 elif：一片里两样都有值时，两样都该发出去。
func _emit_delta(d: Dictionary) -> void:
	var reasoning = d.get("reasoning_content")
	if reasoning is String and not reasoning.is_empty():
		on_thinking.emit(reasoning)

	var content = d.get("content")
	if content is String and not content.is_empty():
		on_response.emit(content)
