extends Node2D

const KEYBOARD_TEXTURE_PATH := "res://images/input_reaction/nairin_keyboard.png"
const KEYBOARD_LABEL_FONT_PATH := "res://fonts/MSYHBD.TTC"
const KEYBOARD_SOURCE_SIZE := Vector2(612, 354)
const KEYBOARD_CENTER := Vector2(107, 66)
const KEYBOARD_SCALE := 0.68
const KEYBOARD_TOP_LEFT := KEYBOARD_CENTER - KEYBOARD_SOURCE_SIZE * KEYBOARD_SCALE * 0.5
const KEYBOARD_IDLE_CENTER := Vector2(172, 45)
const KEYBOARD_FALLBACK_CENTER := Vector2(251, 80)
const KEY_FLASH_TIME := 0.16

const TABLE_COLOR := Color("#fff6f8")
const TABLE_FRONT_COLOR := Color("#f7d8df")
const TABLE_EDGE_COLOR := Color("#dca7b2")
const OUTLINE_COLOR := Color("#532831")
const TABLE_BACK_LEFT := Vector2(-320, -20)
const TABLE_BACK_RIGHT := Vector2(320, 64)
const KEY_ACTIVE_COLOR := Color("#ff6f91")
const KEY_ACTIVE_EDGE := Color("#d92f59")
const KEY_TEXT_COLOR := Color("#44242b")
const KEY_LABEL_COLOR := Color("#245b8f")
const KEY_LABEL_OUTLINE_COLOR := Color(1.0, 1.0, 1.0, 0.96)
# 按键按舞台 x 坐标分区：大于此值归键盘爪（屏幕右侧），否则归鼠标爪。
# 101 位于 Y/M 键区与 H/5 键区之间的天然空隙，两侧按键数量大致相等。
const KEY_SPLIT_X := 101.0

const MOUSE_TEXTURE_PATH := "res://images/input_reaction/pink_mouse_rounded_perspective_v2.png"
const MOUSE_SOURCE_SIZE := Vector2(1536, 1024)
const MOUSE_CENTER := Vector2(-200, 90)
const MOUSE_SCALE := 0.14
const MOUSE_ROTATION := 0.0
const MOUSE_LEFT_SOURCE_CENTER := Vector2(690, 590)
const MOUSE_RIGHT_SOURCE_CENTER := Vector2(530, 480)
const MOUSE_IDLE_CENTER := Vector2(-165, -2)

var _keys_by_vk: Dictionary = {}
var _held_keys: Dictionary = {}
var _key_flash_until: Dictionary = {}
var _held_mouse: Dictionary = {}
var _mouse_flash_until: Dictionary = {}
var _last_fallback_key := -1
var _font: Font
var _keyboard_texture: Texture2D
var _mouse_texture: Texture2D
var _key_highlight_layer: Node2D


class _KeyHighlightLayer:
	extends Node2D
	var active_keys: Array[Dictionary] = []

	func set_active_keys(next_keys: Array[Dictionary]) -> void:
		active_keys = next_keys
		queue_redraw()

	func _draw() -> void:
		for key in active_keys:
			var center: Vector2 = key["center"]
			var size: Vector2 = key["size"]
			var outline := _rounded_key_outline(size)
			draw_set_transform(center, 0.175, Vector2.ONE)
			# Edge-only highlight: a soft outer halo plus one crisp key-cap stroke.
			# There is deliberately no filled polygon, so the printed label stays
			# readable and the paw can visibly press the key surface.
			draw_polyline(
				outline,
				Color(1.0, 0.22, 0.46, 0.30),
				3.2,
				true
			)
			draw_polyline(
				outline,
				Color(0.96, 0.08, 0.32, 0.98),
				1.25,
				true
			)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _rounded_key_outline(size: Vector2) -> PackedVector2Array:
		var radius := minf(3.0, minf(size.x, size.y) * 0.28)
		var half := size * 0.5
		var centers := PackedVector2Array([
			Vector2(half.x - radius, -half.y + radius),
			Vector2(half.x - radius, half.y - radius),
			Vector2(-half.x + radius, half.y - radius),
			Vector2(-half.x + radius, -half.y + radius)
		])
		var starts := PackedFloat32Array([-PI * 0.5, 0.0, PI * 0.5, PI])
		var points := PackedVector2Array()
		for corner in range(4):
			for step in range(4):
				var angle := starts[corner] + PI * 0.5 * float(step) / 3.0
				points.append(
					centers[corner]
					+ Vector2(cos(angle), sin(angle)) * radius
				)
		points.append(points[0])
		return points


func _ready() -> void:
	var label_font := load(KEYBOARD_LABEL_FONT_PATH)
	if label_font is Font:
		_font = label_font as Font
	else:
		_font = ThemeDB.fallback_font
	_keyboard_texture = _load_keyboard_texture()
	_mouse_texture = _load_png_texture(MOUSE_TEXTURE_PATH)
	_build_key_map()
	_key_highlight_layer = _KeyHighlightLayer.new()
	_key_highlight_layer.name = "KeyHighlightLayer"
	# Keyboard < highlight/labels < arms < paws. In particular, the paw must
	# occlude the highlighted key edge at the actual contact point.
	_key_highlight_layer.z_index = 1
	add_child(_key_highlight_layer)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	queue_redraw()


func _process(_delta: float) -> void:
	var now := _now()
	var redraw_needed := false
	for key in _key_flash_until.keys():
		if now >= float(_key_flash_until[key]) and not _held_keys.has(key):
			_key_flash_until.erase(key)
			redraw_needed = true
	for button in _mouse_flash_until.keys():
		if now >= float(_mouse_flash_until[button]) and not _held_mouse.has(button):
			_mouse_flash_until.erase(button)
			redraw_needed = true
	_update_key_highlight_layer()

	if (
		redraw_needed
		or
		not _held_keys.is_empty()
		or not _key_flash_until.is_empty()
		or not _held_mouse.is_empty()
		or not _mouse_flash_until.is_empty()
	):
		queue_redraw()


func normalize_vk(virtual_key: int) -> int:
	match virtual_key:
		0x10, 0xA1:
			return 0xA0
		0x11, 0xA3:
			return 0xA2
		0x12, 0xA5:
			return 0xA4
		0x5C:
			return 0x5B
		_:
			return virtual_key


func has_key(virtual_key: int) -> bool:
	return virtual_key > 0


func is_left_key(virtual_key: int) -> bool:
	var key: Dictionary = _keys_by_vk.get(normalize_vk(virtual_key), {})
	if key.is_empty():
		return false
	return key["center"].x <= KEY_SPLIT_X


func get_key_center(virtual_key: int) -> Vector2:
	var key: Dictionary = _keys_by_vk.get(normalize_vk(virtual_key), {})
	if key.is_empty():
		return KEYBOARD_FALLBACK_CENTER
	return key["center"]


## 全部已映射按键的虚拟键码（预览截图做全键位抽查用）。
func get_mapped_vks() -> Array[int]:
	var vks: Array[int] = []
	for virtual_key in _keys_by_vk:
		vks.append(virtual_key)
	vks.sort()
	return vks


func get_keyboard_idle_center() -> Vector2:
	return KEYBOARD_IDLE_CENTER


func get_mouse_idle_center() -> Vector2:
	return MOUSE_IDLE_CENTER


func press_key(virtual_key: int) -> void:
	var key := normalize_vk(virtual_key)
	_held_keys[key] = true
	_key_flash_until[key] = _now() + KEY_FLASH_TIME
	if not _keys_by_vk.has(key):
		_last_fallback_key = key
	queue_redraw()


func release_key(virtual_key: int) -> void:
	_held_keys.erase(normalize_vk(virtual_key))
	queue_redraw()


func press_mouse(button: int) -> void:
	if button != 1 and button != 2:
		return
	_held_mouse[button] = true
	_mouse_flash_until[button] = _now() + KEY_FLASH_TIME
	queue_redraw()


func release_mouse(button: int) -> void:
	_held_mouse.erase(button)
	queue_redraw()


func get_mouse_button_center(button: int) -> Vector2:
	var source_center := (
		MOUSE_LEFT_SOURCE_CENTER if button == 1 else MOUSE_RIGHT_SOURCE_CENTER
	)
	return _mouse_source_to_stage(source_center)


func _draw() -> void:
	_draw_table()
	_draw_table_back_edge()
	_draw_keyboard()
	_draw_mouse()


func _draw_table() -> void:
	var front_left := Vector2(-320, 272)
	var front_right := Vector2(320, 320)
	var table := PackedVector2Array([
		TABLE_BACK_LEFT,
		TABLE_BACK_RIGHT,
		front_right,
		front_left
	])
	draw_colored_polygon(table, TABLE_COLOR)

	var front_strip := PackedVector2Array([
		Vector2(-320, 238),
		Vector2(320, 300),
		Vector2(320, 320),
		Vector2(-320, 272)
	])
	draw_colored_polygon(front_strip, TABLE_FRONT_COLOR)
	draw_polyline(
		PackedVector2Array([Vector2(-320, 238), Vector2(320, 300)]),
		TABLE_EDGE_COLOR,
		2.0,
		true
	)


func _draw_table_back_edge() -> void:
	draw_polyline(
		PackedVector2Array([TABLE_BACK_LEFT, TABLE_BACK_RIGHT]),
		OUTLINE_COLOR,
		4.0,
		true
	)


func _draw_keyboard() -> void:
	if _keyboard_texture:
		draw_texture_rect(
			_keyboard_texture,
			Rect2(KEYBOARD_TOP_LEFT, KEYBOARD_SOURCE_SIZE * KEYBOARD_SCALE),
			false
		)

	_draw_key_labels()

	if _last_fallback_key >= 0 and _is_key_active(_last_fallback_key):
		_draw_fallback_key(_last_fallback_key)


func _draw_key_labels() -> void:
	if _font == null:
		return
	for virtual_key in _keys_by_vk:
		var key: Dictionary = _keys_by_vk[virtual_key]
		var label: String = key["label"]
		var font_size := 8 if label.length() <= 2 else 6
		var text_size := _font.get_string_size(
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size
		)
		draw_set_transform(key["center"], 0.175, Vector2.ONE)
		var baseline := Vector2(-text_size.x * 0.5, text_size.y * 0.34)
		# The source bitmap already contains tiny labels. A one-pixel light outline
		# masks those underlying glyphs before the bold label is drawn, preventing
		# the doubled/blurred appearance caused by two slightly different rasters.
		draw_string_outline(
			_font,
			baseline,
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			1,
			KEY_LABEL_OUTLINE_COLOR
		)
		draw_string(
			_font,
			baseline,
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			KEY_LABEL_COLOR
		)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _update_key_highlight_layer() -> void:
	if _key_highlight_layer == null:
		return
	var active_keys: Array[Dictionary] = []
	for virtual_key in _keys_by_vk:
		if not _is_key_active(virtual_key):
			continue
		var key: Dictionary = _keys_by_vk[virtual_key]
		active_keys.append({
			"center": key["center"],
			"size": _highlight_size(virtual_key),
		})
	_key_highlight_layer.set_active_keys(active_keys)


func _draw_fallback_key(virtual_key: int) -> void:
	var rect := Rect2(142, 42, 91, 28)
	var style := _make_style(Color("#fff7fa"), KEY_ACTIVE_EDGE, 11.0, 2)
	draw_style_box(style, rect)
	if _font == null:
		return
	var label := _fallback_label(virtual_key)
	var text_size := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	draw_string(
		_font,
		rect.position + Vector2((rect.size.x - text_size.x) * 0.5, 19),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		11,
		KEY_TEXT_COLOR
	)


func _draw_mouse() -> void:
	if _mouse_texture:
		draw_set_transform(MOUSE_CENTER, MOUSE_ROTATION, Vector2.ONE)
		draw_texture_rect(
			_mouse_texture,
			Rect2(-MOUSE_SOURCE_SIZE * MOUSE_SCALE * 0.5, MOUSE_SOURCE_SIZE * MOUSE_SCALE),
			false
		)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	for button in [1, 2]:
		if not _is_mouse_active(button):
			continue
		var polygon := _mouse_button_polygon(button)
		draw_colored_polygon(polygon, Color(1.0, 0.24, 0.52, 0.28))
		var outline := polygon.duplicate()
		outline.append(polygon[0])
		draw_polyline(outline, Color(1.0, 0.30, 0.60, 0.18), 5.0, true)
		draw_polyline(outline, Color(0.96, 0.13, 0.40, 0.88), 1.25, true)


func _mouse_button_polygon(button: int) -> PackedVector2Array:
	# In this perspective the mouse points toward the lower-left. The physical
	# left button is therefore the lower-right pink panel in source coordinates.
	var source_points := PackedVector2Array([
		Vector2(765, 392),
		Vector2(796, 412),
		Vector2(820, 432),
		Vector2(842, 452),
		Vector2(861, 472),
		Vector2(881, 492),
		Vector2(884, 512),
		Vector2(869, 532),
		Vector2(853, 552),
		Vector2(840, 572),
		Vector2(823, 592),
		Vector2(808, 612),
		Vector2(793, 632),
		Vector2(780, 652),
		Vector2(764, 672),
		Vector2(750, 692),
		Vector2(735, 712),
		Vector2(717, 732),
		Vector2(692, 752),
		Vector2(650, 768),
		Vector2(562, 752),
		Vector2(519, 732),
		Vector2(504, 712),
		Vector2(517, 692),
		Vector2(531, 672),
		Vector2(548, 652),
		Vector2(563, 632),
		Vector2(577, 612),
		Vector2(593, 592),
		Vector2(607, 572),
		Vector2(625, 552),
		Vector2(643, 532),
		Vector2(659, 512),
		Vector2(675, 492),
		Vector2(693, 472),
		Vector2(711, 452),
		Vector2(727, 432),
		Vector2(745, 412)
	])
	if button == 2:
		source_points = PackedVector2Array([
			Vector2(565, 286),
			Vector2(635, 306),
			Vector2(673, 326),
			Vector2(692, 346),
			Vector2(675, 366),
			Vector2(656, 386),
			Vector2(637, 406),
			Vector2(621, 426),
			Vector2(602, 446),
			Vector2(584, 466),
			Vector2(570, 486),
			Vector2(551, 506),
			Vector2(537, 526),
			Vector2(523, 546),
			Vector2(506, 566),
			Vector2(493, 586),
			Vector2(479, 606),
			Vector2(465, 626),
			Vector2(451, 646),
			Vector2(431, 666),
			Vector2(412, 646),
			Vector2(396, 626),
			Vector2(382, 606),
			Vector2(372, 586),
			Vector2(364, 566),
			Vector2(361, 546),
			Vector2(361, 526),
			Vector2(370, 506),
			Vector2(381, 486),
			Vector2(395, 466),
			Vector2(410, 446),
			Vector2(426, 426),
			Vector2(443, 406),
			Vector2(460, 386),
			Vector2(478, 366),
			Vector2(497, 346),
			Vector2(517, 326),
			Vector2(539, 306)
		])

	var stage_points := PackedVector2Array()
	for point in source_points:
		stage_points.append(_mouse_source_to_stage(point))
	return stage_points


func _mouse_source_to_stage(source_point: Vector2) -> Vector2:
	var local_point := (source_point - MOUSE_SOURCE_SIZE * 0.5) * MOUSE_SCALE
	return MOUSE_CENTER + local_point.rotated(MOUSE_ROTATION)


func _build_key_map() -> void:
	_add_key(0xA4, "Alt", Vector2(453.6, 235.9))
	_add_key(0xC0, "`", Vector2(445.7, 312.0))
	_add_key(0x14, "Caps", Vector2(482.1, 280.0))
	_add_key(0xA2, "Ctrl", Vector2(545.6, 247.4))
	_add_key(0x41, "A", Vector2(445.1, 273.4))
	_add_key(0x42, "B", Vector2(345.9, 236.2))
	_add_key(0x43, "C", Vector2(402.0, 246.2))
	_add_key(0x44, "D", Vector2(388.3, 263.1))
	_add_key(0x45, "E", Vector2(375.9, 280.3))
	_add_key(0x46, "F", Vector2(359.9, 257.9))
	_add_key(0x47, "G", Vector2(331.4, 253.0))
	_add_key(0x51, "Q", Vector2(432.7, 290.5))
	_add_key(0x52, "R", Vector2(347.9, 275.3))
	_add_key(0x53, "S", Vector2(417.0, 268.3))
	_add_key(0x54, "T", Vector2(319.8, 270.2))
	_add_key(0x56, "V", Vector2(374.1, 241.1))
	_add_key(0x57, "W", Vector2(404.4, 285.2))
	_add_key(0x58, "X", Vector2(430.5, 251.4))
	_add_key(0x5A, "Z", Vector2(458.5, 256.4))
	_add_key(0x5B, "Win", Vector2(488.8, 237.3))
	_add_key(0x31, "1", Vector2(418.0, 307.1))
	_add_key(0x32, "2", Vector2(389.8, 302.0))
	_add_key(0x33, "3", Vector2(361.2, 297.0))
	_add_key(0x34, "4", Vector2(332.6, 291.9))
	_add_key(0x35, "5", Vector2(304.7, 287.0))
	_add_key(0xA0, "Shift", Vector2(499.9, 263.6))
	_add_key(0x20, "Space", Vector2(359.6, 219.1))
	_add_key(0x09, "Tab", Vector2(456.5, 300.2))
	_add_key(0xDC, "\\", Vector2(86.9, 228.8))
	_add_key(0x08, "Back", Vector2(67.6, 244.6))
	_add_key(0xBC, ",", Vector2(260.5, 221.2))
	_add_key(0xBE, ".", Vector2(232.4, 216.1))
	_add_key(0x28, "↓", Vector2(185.3, 183.5))
	_add_key(0xBB, "=", Vector2(106.0, 251.6))
	_add_key(0x48, "H", Vector2(304.0, 248.0))
	_add_key(0x49, "I", Vector2(234.7, 255.2))
	_add_key(0x4A, "J", Vector2(275.4, 243.1))
	_add_key(0x4B, "K", Vector2(246.8, 237.9))
	_add_key(0x4C, "L", Vector2(218.1, 233.0))
	_add_key(0x4D, "M", Vector2(289.1, 226.2))
	_add_key(0x4E, "N", Vector2(317.7, 231.2))
	_add_key(0x4F, "O", Vector2(206.6, 250.2))
	_add_key(0x50, "P", Vector2(178.1, 244.9))
	_add_key(0x55, "U", Vector2(263.2, 260.2))
	_add_key(0x59, "Y", Vector2(291.1, 265.1))
	_add_key(0x25, "←", Vector2(208.8, 192.3))
	_add_key(0xDB, "[", Vector2(149.6, 239.9))
	_add_key(0xBD, "-", Vector2(134.4, 256.6))
	_add_key(0x30, "0", Vector2(163.5, 261.8))
	_add_key(0x36, "6", Vector2(276.7, 281.9))
	_add_key(0x37, "7", Vector2(248.3, 276.9))
	_add_key(0x38, "8", Vector2(220.2, 271.8))
	_add_key(0x39, "9", Vector2(191.9, 266.8))
	_add_key(0xDE, "'", Vector2(161.7, 222.8))
	_add_key(0x0D, "Enter", Vector2(120.1, 215.5))
	_add_key(0x27, "→", Vector2(151.6, 182.1))
	_add_key(0xDD, "]", Vector2(121.7, 235.0))
	_add_key(0xBA, ";", Vector2(189.9, 228.0))
	_add_key(0xBF, "/", Vector2(203.8, 211.0))
	_add_key(0x26, "↑", Vector2(174.7, 190.8))


func _add_key(virtual_key: int, label: String, resource_position: Vector2) -> void:
	_keys_by_vk[virtual_key] = {
		"label": label,
		"center": KEYBOARD_TOP_LEFT + resource_position * KEYBOARD_SCALE
	}


func _highlight_size(virtual_key: int) -> Vector2:
	match virtual_key:
		0x20:
			return Vector2(116, 14)
		0x08:
			return Vector2(39, 14)
		0x0D, 0xA0:
			return Vector2(45, 14)
		0x14:
			return Vector2(38, 14)
		0x09:
			return Vector2(23, 9)
		0xDC:
			return Vector2(34, 14)
		0x5B:
			return Vector2(20, 10)
		0x26, 0x28:
			return Vector2(20, 8)
		0x25, 0x27:
			return Vector2(25, 14)
		_:
			return Vector2(26, 14)


func _fallback_label(virtual_key: int) -> String:
	if virtual_key >= 0x70 and virtual_key <= 0x7B:
		return "F%d" % [virtual_key - 0x6F]
	match virtual_key:
		0x1B:
			return "Esc"
		0x21:
			return "Page Up"
		0x22:
			return "Page Down"
		0x23:
			return "End"
		0x24:
			return "Home"
		0x2D:
			return "Insert"
		0x2E:
			return "Delete"
		_:
			return "VK %02X" % [virtual_key]


func _is_key_active(virtual_key: int) -> bool:
	if _held_keys.has(virtual_key):
		return true
	return _now() < float(_key_flash_until.get(virtual_key, -1.0))


func _is_mouse_active(button: int) -> bool:
	if _held_mouse.has(button):
		return true
	return _now() < float(_mouse_flash_until.get(button, -1.0))


func _make_style(fill: Color, border: Color, radius: float, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(int(radius))
	return style


func _load_png_texture(path: String) -> Texture2D:
	# 用资源加载系统（而非 FileAccess 直读 PNG），导出版与编辑器版均可用。
	var texture := ResourceLoader.load(path) as Texture2D
	if texture == null:
		push_error("Failed to load image asset: %s" % path)
		return ImageTexture.new()
	return texture


## 键盘贴图。
##
## 这里原本每次启动都逐像素扫一遍 612x354 的图，把桌面那块蓝色（#90c5e6）换成粉色
## （#f6dce3）—— 21.6 万次 GDScript 循环。实测删掉它之后舞台创建从 468.5ms 降到
## 399.5ms，也就是这个循环本身约占 70ms。（我原先以为那 468ms 基本都是它，实测证明不是；
## 剩下那 400ms 在字体加载、1536x1024 的鼠标贴图、键位表构建里，还没细查。）
## 需要换色的只有 9873 个像素（4.6%），而且换法是固定的，完全可以在出图时烘进 PNG。
## 现在贴图已经是换好色的成品，直接加载即可；蓝桌面的原图留在
## docs/source-assets/input-reaction-drafts/nairin_keyboard_original_blue_desk.png。
func _load_keyboard_texture() -> Texture2D:
	var texture := ResourceLoader.load(KEYBOARD_TEXTURE_PATH) as Texture2D
	if texture == null:
		push_error("Failed to load keyboard asset: %s" % KEYBOARD_TEXTURE_PATH)
		return ImageTexture.new()
	return texture


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
