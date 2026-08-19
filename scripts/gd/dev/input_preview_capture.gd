extends RefCounted

## 开发用的姿态截图流程 —— 正常运行完全不会碰到它。
##
## 当初调爪子和手臂姿态时靠它自动跑一遍所有按键、逐帧存图对比，是纯粹的开发工具。
## 它原先长在 input_reaction.gd 里，占了 90 行，让那个本来就 800 多行的文件更难读，
## 而且跟着每个安装包发货。现在搬出来，只在带了 --capture-input-preview 参数
## （或 DORO_CAPTURE_INPUT_PREVIEW=1）时才被加载。
##
## 截图存到 user:// 下，也就是 %APPDATA%\Godotpp_userdata\Dororo\。

static func run(host: Node) -> void:
	host._activate_work_mode()
	await host.get_tree().create_timer(0.45).timeout
	await _save_preview_frame(host, "wrist2-idle.png")

	# 必验键位：近身键（Space/F/G/H）+ 远距键（P/[/]），各拍稳定按下与
	# 复位过程（松开后第 1 帧、约 25%/50%/75%/100% 与完全静置）。
	var detail_keys: Array = [
		["space", 0x20],
		["f", 0x46],
		["g", 0x47],
		["h", 0x48],
		["p", 0x50],
		["lbracket", 0xDB],
		["rbracket", 0xDD],
	]
	for entry in detail_keys:
		var label: String = entry[0]
		var vk: int = entry[1]
		host._on_key_down(vk)
		await host.get_tree().create_timer(0.03).timeout
		await _save_preview_frame(host, "wrist2-%s-dive.png" % label)
		await host.get_tree().create_timer(0.19).timeout
		await _save_preview_frame(host, "wrist2-%s-press.png" % label)
		host._on_key_up(vk)
		# 复位从松开这一帧开始（长按已过按压保持期）。按真实复位进度取帧：
		# 约 26% / 53% / 67% / 81% / 92% / 完全静置。
		await host.get_tree().create_timer(0.02).timeout
		await _save_preview_frame(host, "wrist2-%s-ret-frame1.png" % label)
		await host.get_tree().create_timer(0.03).timeout
		await _save_preview_frame(host, "wrist2-%s-ret-25.png" % label)
		await host.get_tree().create_timer(0.025).timeout
		await _save_preview_frame(host, "wrist2-%s-ret-50.png" % label)
		await host.get_tree().create_timer(0.035).timeout
		await _save_preview_frame(host, "wrist2-%s-ret-75.png" % label)
		await host.get_tree().create_timer(0.06).timeout
		await _save_preview_frame(host, "wrist2-%s-ret-100.png" % label)
		await host.get_tree().create_timer(0.23).timeout
		await _save_preview_frame(host, "wrist2-%s-ret-settle.png" % label)
		await host.get_tree().create_timer(0.05).timeout

	# 全键位抽查：所有已映射按键逐一按下，确认没有距离阈值导致手臂异常。
	for vk in host._stage.get_mapped_vks():
		host._on_key_down(vk)
		await host.get_tree().create_timer(0.22).timeout
		await _save_preview_frame(host, "wrist2-sweep-%02X.png" % vk)
		host._on_key_up(vk)
		await host.get_tree().create_timer(0.55).timeout

	await host.get_tree().create_timer(0.1).timeout
	host._on_mouse_down(1)
	await host.get_tree().create_timer(0.22).timeout
	await _save_preview_frame(host, "wrist2-mouse-left.png")
	host._on_mouse_up(1)

	await host.get_tree().create_timer(0.5).timeout
	host._on_mouse_down(2)
	await host.get_tree().create_timer(0.22).timeout
	await _save_preview_frame(host, "wrist2-mouse-right.png")
	host._on_mouse_up(2)
	host.get_tree().quit()
static func _save_preview_frame(host: Node, file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := host.get_viewport().get_texture().get_image()
	var save_error := image.save_png("user://%s" % file_name)
	if save_error != OK:
		push_error("Failed to save input preview %s: %s" % [file_name, error_string(save_error)])
