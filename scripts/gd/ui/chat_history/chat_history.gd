extends Panel

## DORO 窗口的面板：完整的聊天界面。
##
## 头顶那个气泡只显示最新一句，聊几轮就看不到前面说过什么。这个窗口负责「我们都聊了
## 什么」，并且自带输入栏 —— 打开它之后，跟她说话就在这里说，桌宠旁边那条聊天栏会
## 自动让位（见 chatbar.gd）。她的回话仍然会同时出现在这里和她头顶。
##
## 数据不另存一份，直接读 ContextManager —— 那本来就是发给模型的那份对话历史，
## 所以界面上看到的和模型记得的永远一致。左上角那个扫把清空之后记录会空，
## 正是因为她真的不记得了。
##
## 版式仿微信：她的话靠左并配圆头像，人的话靠右不配头像。两边气泡用同一份样式 ——
## 区分靠位置和头像，不靠颜色，这样配色上不会花。

const BUBBLE_STYLE := preload("res://assets/themes/pink_bubble.tres")
const AVATAR := preload("res://assets/images/ui/avatar_doro.png")

## 气泡最多占内容区宽度的这个比例。短句会自己收窄，只有长句才铺到上限再换行。
const BUBBLE_MAX_RATIO := 0.66
const AVATAR_SIZE := 40.0
## 人的气泡右侧留白：和滚动条之间的间隙。
const RIGHT_GAP := 10.0

## 正文字色。settings 主题里 Label 的默认字色是纯白（那是给粉色标题栏用的），
## 气泡底是浅色，不显式指定就是白字压浅底、等于隐形。
const BODY_COLOR := Color(0.28, 0.28, 0.3)
const HINT_COLOR := Color(0.62, 0.55, 0.58)

@onready var _entries: VBoxContainer = $VBoxContainer/ChatArea/ScrollContainer/Entries
@onready var _scroll: ScrollContainer = $VBoxContainer/ChatArea/ScrollContainer
@onready var _empty_hint: Label = $VBoxContainer/ChatArea/ScrollContainer/Entries/EmptyHint
@onready var _broom: Button = $VBoxContainer/TitleBar/MarginContainer/HBoxContainer/BroomButton
@onready var _input: LineEdit = $VBoxContainer/InputArea/InputRow/LineEdit
@onready var _send_btn: Button = $VBoxContainer/InputArea/InputRow/SendButton
@onready var _context: ContextManager = get_node("/root/Node2D/OpenAIChatClient/ContextManager")
@onready var _chatbar = get_node("/root/Node2D/GUI/Chatbar")

func _ready() -> void:
	_empty_hint.add_theme_color_override("font_color", HINT_COLOR)
	_broom.pressed.connect(_on_broom_pressed)
	_send_btn.pressed.connect(_on_send_pressed)
	_input.text_submitted.connect(_on_text_submitted)
	refresh()

func _on_text_submitted(_t: String) -> void:
	_on_send_pressed()

## 已经渲染过的历史条数（含被跳过的 system）。
##
## 记的是「消费到历史数组的第几项」而不是「画了几行」—— 因为 system 那条不出现在界面上，
## 两个数字对不上，用行数会错位。
var _rendered: int = 0

## 全量重建。开销随消息数线性增长，所以只在真的需要时用：打开窗口、点扫把、
## 以及历史被裁剪过之后。平时每轮对话走 sync()。
func refresh() -> void:
	for child in _entries.get_children():
		if child != _empty_hint:
			_entries.remove_child(child)
			child.queue_free()
	_rendered = 0
	await _append_new()

## 增量追加：只画还没画过的那几条。
##
## 每轮对话都全量重建是我最初的写法，实测代价很难看：20 条消息 127ms、100 条 175ms、
## 300 条 546ms —— 聊到一百多轮之后，每发一句话窗口就卡半秒，而且正好卡在
## 「刚按下发送、她刚回完」这个最不该卡的时刻。
##
## 现在只 add_child 新的那一两行。历史缩短过（清空、或撞上上下文上限被裁掉一半）时
## 增量就不成立了，退回全量重建 —— 判据是历史条数比已渲染的还少。
func sync() -> void:
	var history: Array = _context.get_context()
	if history.size() < _rendered:
		await refresh()
		return
	if history.size() == _rendered:
		return
	await _append_new()

func _append_new() -> void:
	var history: Array = _context.get_context()
	_empty_hint.visible = history.is_empty()

	for i in range(_rendered, history.size()):
		var entry = history[i]
		if entry is Dictionary:
			# system 是内置人设，不是聊天内容，不该出现在记录里
			var role := StringName(entry.get("role", ""))
			if role != &"system":
				_entries.add_child(_make_row(role == &"assistant", String(entry.get("content", ""))))
	_rendered = history.size()

	# 等一帧让容器算完布局，否则滚动条的最大值还是旧的，滚不到底
	await get_tree().process_frame
	if is_inside_tree():
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)

## 一行消息：她的靠左带头像，人的靠右。
func _make_row(from_doro: bool, content: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var bubble := _make_bubble(content)
	if from_doro:
		row.add_child(_make_avatar())
		row.add_child(bubble)
		row.add_child(_make_spacer())
	else:
		row.add_child(_make_spacer())
		row.add_child(bubble)
		# 留一小条间隙，别让气泡贴着滚动条。
		#
		# 这里的取舍：消息区的右边距已经收到 4px（让滚动条尽量靠窗口边缘），如果气泡也
		# 一路顶到内容区右缘，它和滚动条之间就只剩 0 —— 视觉上像是被滚动条压着。
		# 所以间隙放在气泡这一侧，而不是靠加大消息区边距来腾（那样滚动条会跟着往里跑）。
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(RIGHT_GAP, 0)
		row.add_child(gap)
	return row

func _make_avatar() -> Control:
	var tex := TextureRect.new()
	tex.texture = AVATAR
	tex.custom_minimum_size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# 顶部对齐：气泡长的时候头像该贴在第一行旁边，而不是浮到中间
	tex.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return tex

func _make_spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

func _make_bubble(content: String) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", BUBBLE_STYLE)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)

	var label := Label.new()
	label.text = content
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", BODY_COLOR)
	margin.add_child(label)

	_clamp_label_width(label, content)
	return panel

## 气泡宽度：短句自然收窄，长句到上限就换行。
##
## Godot 的容器没有 max_width，所以自己量：用字体算出整段文字排成一行要多宽，和上限
## 取小。不这么做只有两条路 —— 要么气泡永远铺满一整行（短句也占满，很丑），
## 要么长句一路撑到窗口外面去。
func _clamp_label_width(label: Label, content: String) -> void:
	var font := label.get_theme_font("font")
	if font == null:
		return
	var font_size := label.get_theme_font_size("font_size")
	var one_line := font.get_string_size(
			content, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	# 内容区宽度：窗口宽减去头像、占位和两侧留白
	var avail := maxf(120.0, size.x - AVATAR_SIZE * 2.0 - 40.0)
	label.custom_minimum_size.x = minf(one_line, avail * BUBBLE_MAX_RATIO)

## 左上角那个扫把。放在这里而不是聊天栏：清空之前能先看一眼聊了什么再决定，
## 而且聊天栏省下的位置正好留给输入框。
func _on_broom_pressed() -> void:
	_context.clear_context()
	refresh()

## 发送。复用 chatbar 那一整套流程（配置检查、上下文、溢出重试、头顶气泡），
## 不在这里重写一遍 —— 两个入口共用同一条路，行为才不会分叉。
func _on_send_pressed() -> void:
	var text := _input.text
	if text.strip_edges().is_empty():
		return
	if _chatbar.send_text(text):
		_input.clear()
