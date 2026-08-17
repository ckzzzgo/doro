extends Node

@export var update_message_box: Resource

## 弹窗实例在场景树里的固定名字，用来判断是否已经开着
const UPDATE_BOX_NAME := "UpdateMessageBox"

func _ready() -> void:
	var ver = "当前版本：%s" % ProjectSettings.get_setting("application/config/version")
	ver += "  引擎版本：%s" % Engine.get_version_info()["string"]
	$VersionContainer/VersionIndicator.set_text(ver)

func _on_check_update_button_pressed() -> void:
	# 已经开着就把它显示到前面，不要再实例化一个。
	# 原实现无论如何都先 instantiate，节点已存在时那个新实例既不入树也不释放 —— 每点
	# 一次漏一个场景实例。
	var existing := get_node_or_null(NodePath(UPDATE_BOX_NAME))
	if existing != null:
		if existing is Window:
			existing.show()
			existing.grab_focus()
		return

	var packed := load(update_message_box.resource_path) as PackedScene
	if packed == null:
		push_error("检查更新：无法加载弹窗场景 %s" % str(update_message_box))
		return

	var box := packed.instantiate()
	box.name = UPDATE_BOX_NAME
	add_child(box)
