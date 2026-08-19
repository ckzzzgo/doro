extends NinePatchRect

## 聊天记录面板。
##
## 头顶那个气泡只显示最新一句，聊上几轮就看不到前面说过什么了。但气泡本身不适合
## 承担「翻记录」这件事：它跟着桌宠飘、尺寸小，塞十几句进去会挡住半个屏幕，还分不清
## 谁说的。所以分工：气泡负责「此刻她在说什么」，这个窗口负责「我们都聊了什么」。
##
## 数据不另存一份，直接读 ContextManager —— 那本来就是发给模型的那份对话历史，
## 界面上看到的和模型看到的因此永远一致。也就是说这里显示的就是她「记得」的内容：
## 点了「重新开始」之后记录清空，正是因为她真的不记得了。
##
## 只在打开时和每轮对话结束后重建，不做流式增量追加 —— 逐字冒出来的效果由气泡负责，
## 记录窗口要的是稳定可读。

## 正文字色。比说话人那行的灰（LabelItem，0.64）更深，好让正文成为视觉重点。
const BODY_COLOR := Color(0.28, 0.28, 0.3)

const ROLE_LABEL := {
	&"user": "人",
	&"assistant": "Doro",
	&"system": "设定",
}

@onready var _entries: VBoxContainer = $VBoxContainer/ScrollContainer/Entries
@onready var _scroll: ScrollContainer = $VBoxContainer/ScrollContainer
@onready var _empty_hint: Label = $VBoxContainer/ScrollContainer/Entries/EmptyHint
@onready var _restart_btn: Button = $VBoxContainer/Footer/RestartButton
@onready var _context: ContextManager = get_node("/root/Node2D/OpenAIChatClient/ContextManager")

func _ready() -> void:
	_restart_btn.pressed.connect(_on_restart_pressed)
	refresh()

func refresh() -> void:
	for child in _entries.get_children():
		if child != _empty_hint:
			child.queue_free()

	var history: Array = _context.get_context()
	_empty_hint.visible = history.is_empty()
	_empty_hint.add_theme_color_override("font_color", BODY_COLOR)

	for entry in history:
		if not entry is Dictionary:
			continue
		# system 是内置人设，不是聊天内容，不该出现在记录里
		var role := StringName(entry.get("role", ""))
		if role == &"system":
			continue
		_entries.add_child(_make_entry(role, String(entry.get("content", ""))))

	# 等一帧让容器算完布局，否则滚动条的最大值还是旧的，滚不到底
	await get_tree().process_frame
	if is_inside_tree():
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)

func _make_entry(role: StringName, content: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	# 字色必须显式指定。settings 主题里 Label 的默认字色是纯白（那是给粉色标题栏用的），
	# 而面板底色很浅 —— 不设的话正文就是白字压浅底，等于隐形。主题里可用的
	# LabelItem 是 0.64 的灰，适合当次要文字，正文得更深一点才立得住。
	var who := Label.new()
	who.text = ROLE_LABEL.get(role, String(role))
	who.theme_type_variation = &"LabelItem"
	who.add_theme_font_size_override("font_size", 12)
	box.add_child(who)

	var body := Label.new()
	body.text = content
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_color_override("font_color", BODY_COLOR)
	box.add_child(body)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	box.add_child(gap)
	return box

## 「重新开始」放在这里而不是只放在聊天栏：清空之前能先看一眼聊了什么再决定。
func _on_restart_pressed() -> void:
	_context.clear_context()
	refresh()
