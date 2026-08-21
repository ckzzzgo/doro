extends Node

@export var update_message_box: Resource

## 弹窗实例在场景树里的固定名字，用来判断是否已经开着
const UPDATE_BOX_NAME := "UpdateMessageBox"

const COPY_BUTTON_PATH := "VersionContainer/CopyDiagButton"
const COPY_BUTTON_LABEL := "复制诊断信息"

## 一 GB 的字节数，用来把内存数字换成人看得懂的单位
const BYTES_PER_GB := 1073741824.0

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


# ------------------------------------------------------------------ 诊断信息

## 把这台机器的实际情况拼成一段纯文本，塞进剪贴板，让用户粘贴发回来。
##
## 为什么需要这个：窗口透明依赖显卡驱动，开发机上复现不了别人的黑底 —— 我们的卡
## 撑得住，别人的撑不住。上一轮就是因为拿不到用户的环境信息，只能靠猜，结果发了
## 一版没验证的修复，白折腾一轮。有这个按钮，第一句话就能拿到事实而不是描述。
##
## 只收客观的机器信息。不碰聊天记录、不碰 API key、不碰任何账号相关的东西 ——
## 这段文本是要用户自己发给别人的，里面不能有他不愿意示人的内容。
## 也不做自动上报：偷偷往外发数据，用户哪天发现了就再也不会信这个程序。
func _on_copy_diag_button_pressed() -> void:
	DisplayServer.clipboard_set(_build_diagnostics())

	# 必须给看得见的反馈。剪贴板是没有声音的，不改文案的话用户不知道到底成没成，
	# 只会反复点，然后来问「那个按钮是不是坏的」。
	var btn := get_node_or_null(NodePath(COPY_BUTTON_PATH))
	if btn == null:
		return
	btn.text = "已复制！"
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(btn):
		btn.text = COPY_BUTTON_LABEL

func _build_diagnostics() -> String:
	var L: Array[String] = []

	L.append("Doro 诊断信息")
	L.append("版本 %s    引擎 %s    %s" % [
		str(ProjectSettings.get_setting("application/config/version")),
		str(Engine.get_version_info()["string"]),
		Engine.get_architecture_name(),
	])

	# 画面这一块是重点 —— 黑底的原因几乎肯定在这几行里
	L.append("")
	L.append("[画面]")
	L.append("  渲染驱动   %s" % RenderingServer.get_current_rendering_driver_name())
	L.append("  渲染方法   %s" % RenderingServer.get_current_rendering_method())
	L.append("  显卡       %s（%s）" % [
		RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_vendor(),
	])
	L.append("  显卡 API   %s" % RenderingServer.get_video_adapter_api_version())

	# 这里不能直接 join：驱动信息取不到时返回的不是空数组，而是几个空字符串的数组
	# （这台开发机上的 NVIDIA 就是这样），直接拼出来是个孤零零的「 / 」，
	# 看着像程序坏了。挑出真有内容的部分再拼。
	var drv_parts := PackedStringArray()
	for d in OS.get_video_adapter_driver_info():
		if not str(d).strip_edges().is_empty():
			drv_parts.append(str(d))
	L.append("  驱动       %s" % (" / ".join(drv_parts) if drv_parts.size() > 0 else "读不到（显卡驱动没提供）"))

	# 「标志已设上」和「看着是透明的」是两件事：标志设上了而画面仍是黑底，
	# 说明配置没问题，是显卡驱动没做到。这个区分能省掉一整轮排查。
	var tr: bool = DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT)
	L.append("  透明标志   %s" % ("已设上（若仍是黑底，是显卡驱动没做到）" if tr else "没设上（配置问题）"))
	L.append("  显示服务   %s" % DisplayServer.get_name())
	L.append("  屏幕       %s   缩放 %s" % [
		str(DisplayServer.screen_get_size()),
		str(DisplayServer.screen_get_scale()),
	])

	L.append("")
	L.append("[系统]")
	L.append("  %s %s" % [OS.get_name(), OS.get_version()])
	L.append("  CPU        %s" % OS.get_processor_name())
	var mem := OS.get_memory_info()
	L.append("  内存       %.1f GB（空闲 %.1f GB）" % [
		float(mem.get("physical", 0)) / BYTES_PER_GB,
		float(mem.get("free", 0)) / BYTES_PER_GB,
	])

	L.append("")
	L.append("[其他]")
	var args := OS.get_cmdline_args()
	L.append("  启动参数   %s" % (" ".join(args) if args.size() > 0 else "（无）"))
	L.append("  日志目录   %s" % OS.get_user_data_dir().path_join("logs"))

	# 这一条放最后，因为它是唯一用户自己就能解决的原因，而且和显卡无关，
	# 很容易被跳过去查一堆驱动。
	L.append("")
	L.append("——— 如果 Doro 背后是一块黑方块 ———")
	L.append("先看：设置 - 个性化 - 颜色 - 透明效果，是不是关着的。")
	L.append("关掉它会让窗口透明整体失效，跟显卡没关系。")

	return "\n".join(L)
