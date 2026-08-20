extends Node
class_name ContextManager

## 对话历史。
##
## 曾经有一套「按条数主动裁剪」的机制（_max_context_enable / _trim_history），
## 但那个设计被推翻了：现在的模型上下文都很大，正常聊天很难撞到上限，为此在界面上
## 加个让用户猜数字的设置项不值得。改成真撞上了才处理 —— 见 drop_oldest_half，
## 由 chatbar 在接口回报「上下文超长」时调用。
##
## 那套裁剪代码已经删掉，不留着：一个永远不会执行的 _trim_history 只会让下一个人
## 以为裁剪在生效。

const ROLE_USER:StringName = &'user'
const ROLE_ASSISTANT:StringName = &'assistant'
const ROLE_SYSTEM:StringName = &'system'

var _history: Array[Dictionary] = []

func add_context(role: StringName, content: String) -> void:
	if role not in ["user", "assistant", "system"]:
		push_warning("Invalid role '%s'. Must be 'user', 'assistant', or 'system'." % role)
		return

	var entry: Dictionary = {
		"role": role,
		"content": content
	}

	_history.append(entry)

func get_context() -> Array:
	return _history.duplicate(true)

func clear_context() -> void:
	_history.clear()

func get_length() -> int:
	return _history.size()


## 撞上模型上下文上限时，丢掉最旧的一半历史。返回丢掉的条数。
##
## 这里刻意不做「主动按条数裁剪」—— 现在的模型上下文都很大，聊天很难聊到上限，
## 为一个基本不会发生的情况在界面上加个设置项不值得。只在真的撞上了（接口返回
## 上下文超长）时处理一次，代价是偶尔一次重试，换来的是用户什么都不用配。
##
## 系统 prompt 不在这份历史里（客户端每次单独拼在最前面），所以怎么裁都不会
## 把人设裁掉。
func drop_oldest_half() -> int:
	if _history.is_empty():
		return 0
	var drop := maxi(1, _history.size() / 2)
	_history = _history.slice(drop, _history.size())
	return drop
