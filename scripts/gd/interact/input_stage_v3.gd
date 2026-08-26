extends Node2D

const KEYBOARD_TEXTURE_PATH := "res://images/input_reaction/doro_keyboard.png"
const KEYBOARD_SOURCE_SIZE := Vector2(612, 354)
const KEYBOARD_CENTER := Vector2(107, 66)
const KEYBOARD_SCALE := 0.68
const KEYBOARD_TOP_LEFT := KEYBOARD_CENTER - KEYBOARD_SOURCE_SIZE * KEYBOARD_SCALE * 0.5
const KEYBOARD_IDLE_CENTER := Vector2(172, 45)
const KEY_FLASH_TIME := 0.16

const TABLE_COLOR := Color("#fff6f8")
const TABLE_FRONT_COLOR := Color("#f7d8df")
const TABLE_EDGE_COLOR := Color("#dca7b2")
const OUTLINE_COLOR := Color("#532831")
const TABLE_BACK_LEFT := Vector2(-320, -20)
const TABLE_BACK_RIGHT := Vector2(320, 64)

## 每个键帽的四个角，相对键心，贴图坐标系（612x354）。
##
## 由 tools/gen_keyboard.py 连同键盘贴图一起生成 —— 别手改，改了就跟贴图对不上了。
## 按下时的高光就照这四个角描边，所以高光和画在贴图上的键必然重合。
const KEY_SHAPES := {
	0xA4: [Vector2(4.7, 9.1), Vector2(-25.8, 3.7), Vector2(-4.7, -9.1), Vector2(25.7, -3.7)],  # Alt
	0xC0: [Vector2(1.7, 8.6), Vector2(-22.7, 4.3), Vector2(-1.7, -8.6), Vector2(22.7, -4.3)],  # `
	0x14: [Vector2(10.8, 10.2), Vector2(-31.9, 2.6), Vector2(-10.8, -10.2), Vector2(31.8, -2.6)],  # Caps
	0xA2: [Vector2(7.8, 9.7), Vector2(-28.7, 3.1), Vector2(-7.8, -9.7), Vector2(28.7, -3.1)],  # Ctrl
	0x41: [Vector2(1.7, 8.6), Vector2(-22.7, 4.2), Vector2(-1.7, -8.6), Vector2(22.7, -4.2)],  # A
	0x42: [Vector2(1.7, 8.6), Vector2(-22.8, 4.2), Vector2(-1.7, -8.6), Vector2(22.8, -4.2)],  # B
	0x43: [Vector2(1.7, 8.6), Vector2(-22.8, 4.2), Vector2(-1.7, -8.6), Vector2(22.7, -4.2)],  # C
	0x44: [Vector2(1.7, 8.6), Vector2(-22.8, 4.2), Vector2(-1.7, -8.6), Vector2(22.8, -4.2)],  # D
	0x45: [Vector2(1.7, 8.6), Vector2(-22.8, 4.3), Vector2(-1.7, -8.6), Vector2(22.8, -4.2)],  # E
	0x46: [Vector2(1.7, 8.6), Vector2(-22.8, 4.2), Vector2(-1.7, -8.6), Vector2(22.8, -4.2)],  # F
	0x47: [Vector2(1.7, 8.6), Vector2(-22.8, 4.2), Vector2(-1.7, -8.6), Vector2(22.8, -4.2)],  # G
	0x51: [Vector2(1.7, 8.6), Vector2(-22.7, 4.3), Vector2(-1.7, -8.6), Vector2(22.7, -4.3)],  # Q
	0x52: [Vector2(1.7, 8.6), Vector2(-22.8, 4.3), Vector2(-1.7, -8.6), Vector2(22.8, -4.2)],  # R
	0x53: [Vector2(1.7, 8.6), Vector2(-22.7, 4.2), Vector2(-1.7, -8.6), Vector2(22.7, -4.2)],  # S
	0x54: [Vector2(1.7, 8.6), Vector2(-22.8, 4.3), Vector2(-1.7, -8.6), Vector2(22.8, -4.2)],  # T
	0x56: [Vector2(1.7, 8.6), Vector2(-22.8, 4.2), Vector2(-1.7, -8.6), Vector2(22.8, -4.2)],  # V
	0x57: [Vector2(1.7, 8.6), Vector2(-22.8, 4.3), Vector2(-1.7, -8.6), Vector2(22.7, -4.3)],  # W
	0x58: [Vector2(1.7, 8.6), Vector2(-22.7, 4.2), Vector2(-1.7, -8.6), Vector2(22.7, -4.2)],  # X
	0x5A: [Vector2(1.7, 8.6), Vector2(-22.7, 4.2), Vector2(-1.7, -8.6), Vector2(22.7, -4.2)],  # Z
	0x5B: [Vector2(4.7, 9.1), Vector2(-25.7, 3.7), Vector2(-4.7, -9.1), Vector2(25.7, -3.7)],  # Win
	0x31: [Vector2(1.7, 8.6), Vector2(-22.8, 4.3), Vector2(-1.7, -8.6), Vector2(22.7, -4.3)],  # 1
	0x32: [Vector2(1.7, 8.6), Vector2(-22.8, 4.3), Vector2(-1.7, -8.6), Vector2(22.8, -4.3)],  # 2
	0x33: [Vector2(1.7, 8.6), Vector2(-22.8, 4.3), Vector2(-1.7, -8.6), Vector2(22.8, -4.3)],  # 3
	0x34: [Vector2(1.7, 8.6), Vector2(-22.8, 4.3), Vector2(-1.7, -8.6), Vector2(22.8, -4.3)],  # 4
	0x35: [Vector2(1.7, 8.6), Vector2(-22.8, 4.3), Vector2(-1.7, -8.6), Vector2(22.8, -4.3)],  # 5
	0xA0: [Vector2(16.9, 11.3), Vector2(-37.9, 1.5), Vector2(-16.9, -11.3), Vector2(37.9, -1.5)],  # Shift
	0x20: [Vector2(65.7, 20.0), Vector2(-87.0, -7.2), Vector2(-65.8, -20.0), Vector2(86.8, 7.2)],  # Space
	0x09: [Vector2(7.8, 9.7), Vector2(-28.8, 3.2), Vector2(-7.8, -9.7), Vector2(28.8, -3.2)],  # Tab
	0xDC: [Vector2(7.8, 9.7), Vector2(-29.1, 3.2), Vector2(-7.8, -9.7), Vector2(29.1, -3.1)],  # \\
	0x08: [Vector2(13.9, 10.8), Vector2(-35.3, 2.1), Vector2(-13.9, -10.8), Vector2(35.3, -2.1)],  # Back
	0xBC: [Vector2(1.6, 8.6), Vector2(-22.8, 4.2), Vector2(-1.6, -8.6), Vector2(22.8, -4.2)],  # ,
	0xBE: [Vector2(1.6, 8.6), Vector2(-22.9, 4.2), Vector2(-1.6, -8.6), Vector2(22.8, -4.2)],  # .
	0x28: [Vector2(7.3, 5.2), Vector2(-17.2, 0.8), Vector2(-7.3, -5.2), Vector2(17.2, -0.8)],  # ↓
	0xBB: [Vector2(1.6, 8.6), Vector2(-23.0, 4.3), Vector2(-1.6, -8.6), Vector2(23.0, -4.3)],  # =
	0x48: [Vector2(1.7, 8.6), Vector2(-22.8, 4.2), Vector2(-1.7, -8.6), Vector2(22.8, -4.2)],  # H
	0x49: [Vector2(1.6, 8.6), Vector2(-22.9, 4.2), Vector2(-1.6, -8.6), Vector2(22.9, -4.2)],  # I
	0x4A: [Vector2(1.6, 8.6), Vector2(-22.8, 4.2), Vector2(-1.6, -8.6), Vector2(22.8, -4.2)],  # J
	0x4B: [Vector2(1.6, 8.6), Vector2(-22.9, 4.2), Vector2(-1.6, -8.6), Vector2(22.8, -4.2)],  # K
	0x4C: [Vector2(1.6, 8.6), Vector2(-22.9, 4.2), Vector2(-1.6, -8.6), Vector2(22.9, -4.2)],  # L
	0x4D: [Vector2(1.6, 8.6), Vector2(-22.8, 4.2), Vector2(-1.6, -8.6), Vector2(22.8, -4.2)],  # M
	0x4E: [Vector2(1.7, 8.6), Vector2(-22.8, 4.2), Vector2(-1.7, -8.6), Vector2(22.8, -4.2)],  # N
	0x4F: [Vector2(1.6, 8.6), Vector2(-22.9, 4.2), Vector2(-1.6, -8.6), Vector2(22.9, -4.2)],  # O
	0x50: [Vector2(1.6, 8.6), Vector2(-22.9, 4.2), Vector2(-1.6, -8.6), Vector2(22.9, -4.2)],  # P
	0x55: [Vector2(1.6, 8.6), Vector2(-22.9, 4.3), Vector2(-1.6, -8.6), Vector2(22.8, -4.2)],  # U
	0x59: [Vector2(1.7, 8.6), Vector2(-22.8, 4.3), Vector2(-1.7, -8.6), Vector2(22.8, -4.2)],  # Y
	0x25: [Vector2(1.6, 8.6), Vector2(-22.9, 4.2), Vector2(-1.6, -8.6), Vector2(22.9, -4.2)],  # ←
	0xDB: [Vector2(1.6, 8.6), Vector2(-22.9, 4.2), Vector2(-1.6, -8.6), Vector2(22.9, -4.2)],  # [
	0xBD: [Vector2(1.6, 8.6), Vector2(-23.0, 4.3), Vector2(-1.6, -8.6), Vector2(22.9, -4.3)],  # -
	0x30: [Vector2(1.6, 8.6), Vector2(-22.9, 4.3), Vector2(-1.6, -8.6), Vector2(22.9, -4.3)],  # 0
	0x36: [Vector2(1.6, 8.6), Vector2(-22.9, 4.3), Vector2(-1.6, -8.6), Vector2(22.8, -4.3)],  # 6
	0x37: [Vector2(1.6, 8.6), Vector2(-22.9, 4.3), Vector2(-1.6, -8.6), Vector2(22.9, -4.3)],  # 7
	0x38: [Vector2(1.6, 8.6), Vector2(-22.9, 4.3), Vector2(-1.6, -8.6), Vector2(22.9, -4.3)],  # 8
	0x39: [Vector2(1.6, 8.6), Vector2(-22.9, 4.3), Vector2(-1.6, -8.6), Vector2(22.9, -4.3)],  # 9
	0xDE: [Vector2(1.6, 8.6), Vector2(-22.9, 4.2), Vector2(-1.6, -8.6), Vector2(22.9, -4.2)],  # '
	0x0D: [Vector2(17.0, 11.3), Vector2(-38.3, 1.5), Vector2(-17.0, -11.3), Vector2(38.3, -1.5)],  # Enter
	0x27: [Vector2(1.6, 8.6), Vector2(-22.9, 4.2), Vector2(-1.6, -8.6), Vector2(22.9, -4.2)],  # →
	0xDD: [Vector2(1.6, 8.6), Vector2(-23.0, 4.2), Vector2(-1.6, -8.6), Vector2(22.9, -4.2)],  # ]
	0xBA: [Vector2(1.6, 8.6), Vector2(-22.9, 4.2), Vector2(-1.6, -8.6), Vector2(22.9, -4.2)],  # ;
	0xBF: [Vector2(1.6, 8.6), Vector2(-22.9, 4.2), Vector2(-1.6, -8.6), Vector2(22.9, -4.2)],  # /
	0x26: [Vector2(7.3, 5.2), Vector2(-17.2, 0.8), Vector2(-7.3, -5.2), Vector2(17.2, -0.8)],  # ↑
}

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
			var shape: PackedVector2Array = key["shape"]
			if shape.size() < 3:
				continue
			var outline := _rounded_key_outline(shape)
			draw_set_transform(center, 0.0, Vector2.ONE)
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

	## 给键帽四边形切圆角。
	##
	## 原来是拿一个写死的 Vector2 尺寸拼轴对齐矩形，再统一转 0.175 rad。键帽其实是
	## 透视投影出来的平行四边形，带切变，用矩形拼不出来 —— 按下时高光和键就错位。
	## 现在四个角由生成脚本连同贴图一起算出来（KEY_SHAPES），两边同一个来源。
	func _rounded_key_outline(quad: PackedVector2Array) -> PackedVector2Array:
		var points := PackedVector2Array()
		var n := quad.size()
		for i in range(n):
			var p0 := quad[(i - 1 + n) % n]
			var p1 := quad[i]
			var p2 := quad[(i + 1) % n]
			var r := 0.28
			var a := p1 + (p0 - p1) * r
			var b := p1 + (p2 - p1) * r
			for step in range(4):
				var t := float(step) / 3.0
				var mt := 1.0 - t
				points.append(a * (mt * mt) + p1 * (2.0 * mt * t) + b * (t * t))
		points.append(points[0])
		return points


func _ready() -> void:
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


## 这个键在虚拟键盘上有没有对应的键帽。
##
## 原来写的是 return virtual_key > 0 —— 压根没查键位表，任何键码都算「有」。
## 于是 _on_key_down 里那道 has_key 守卫从来没拦住过谁，ESC / F1 / F2 这些没画出来的
## 键会走进「兜底键」那条路：在键盘右上角固定位置画一个通用键帽，爪子也跟着去按。
## 用户看到的就是「按了键盘上没有的键，她还是有反应」。
##
## 现在如实查表。键位表只收了 61 个常用键，表外的键一律不产生任何反应。
func has_key(virtual_key: int) -> bool:
	return _keys_by_vk.has(normalize_vk(virtual_key))



func get_key_center(virtual_key: int) -> Vector2:
	var key: Dictionary = _keys_by_vk.get(normalize_vk(virtual_key), {})
	if key.is_empty():
		# 表外的键现在被 has_key 拦在外面，走不到这里；留个无害的默认值
		return KEYBOARD_IDLE_CENTER
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

	# 键帽上的字直接来自贴图，这里不再画第二遍。
	#
	# 以前贴图自带一套小字，代码又用 MSYHBD 画一套粗的盖上去，靠一圈 1 像素的白描边
	# 遮住下面那套。遮不住：两套字大小不同（代码固定 font_size 8，贴图跟着缩放），
	# 旋转也不同（代码固定 0.175 rad，贴图每个键跟着各自的透视角度），错位露边，
	# 看上去就是「键盘有两层」。实测把实机画面和贴图对齐后有 20.22% 的像素对不上，
	# 差出来的全是字。
	#
	# 现在的贴图由生成脚本按每个键各自的透视角度把字画好，一层就够了。


func _scaled_shape(virtual_key: int) -> PackedVector2Array:
	var quad: Array = KEY_SHAPES.get(virtual_key, [])
	var out := PackedVector2Array()
	for p in quad:
		out.append(p * KEYBOARD_SCALE)
	return out


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
			"shape": _scaled_shape(virtual_key),
		})
	_key_highlight_layer.set_active_keys(active_keys)



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
	var source_points := [
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
	]
	if button == 2:
		source_points = [
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
		]

	var stage_points := PackedVector2Array()
	for point in source_points:
		stage_points.append(_mouse_source_to_stage(point))
	return stage_points


func _mouse_source_to_stage(source_point: Vector2) -> Vector2:
	var local_point := (source_point - MOUSE_SOURCE_SIZE * 0.5) * MOUSE_SCALE
	return MOUSE_CENTER + local_point.rotated(MOUSE_ROTATION)


## 键位表：每个键在键盘贴图（612x354）上的中心。
##
## Tab / Ctrl / Win 三个曾经写错，跟贴图上画的键帽差了 7.6~9.3 px（其余 57 个键的
## 中位误差只有 0.24 px）。旧的按键高光是写死的 26x14 矩形，盖得住这点偏移，所以
## 一直没暴露；但这份坐标同时喂给 get_key_center 决定爪子的落点，按这三个键时爪子
## 是偏的。2026-08-26 按贴图上键帽的实际中心改正。
func _build_key_map() -> void:
	_add_key(0xA4, "Alt", Vector2(453.6, 235.9))
	_add_key(0xC0, "`", Vector2(445.7, 312.0))
	_add_key(0x14, "Caps", Vector2(482.1, 280.0))
	_add_key(0xA2, "Ctrl", Vector2(538.6, 251.3))
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
	_add_key(0x5B, "Win", Vector2(482.2, 241.1))
	_add_key(0x31, "1", Vector2(418.0, 307.1))
	_add_key(0x32, "2", Vector2(389.8, 302.0))
	_add_key(0x33, "3", Vector2(361.2, 297.0))
	_add_key(0x34, "4", Vector2(332.6, 291.9))
	_add_key(0x35, "5", Vector2(304.7, 287.0))
	_add_key(0xA0, "Shift", Vector2(499.9, 263.6))
	_add_key(0x20, "Space", Vector2(359.6, 219.1))
	_add_key(0x09, "Tab", Vector2(464.9, 296.1))
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


func _is_key_active(virtual_key: int) -> bool:
	if _held_keys.has(virtual_key):
		return true
	return _now() < float(_key_flash_until.get(virtual_key, -1.0))


func _is_mouse_active(button: int) -> bool:
	if _held_mouse.has(button):
		return true
	return _now() < float(_mouse_flash_until.get(button, -1.0))



func _load_png_texture(path: String) -> Texture2D:
	# 用资源加载系统（而非 FileAccess 直读 PNG），导出版与编辑器版均可用。
	var texture := ResourceLoader.load(path) as Texture2D
	if texture == null:
		push_error("Failed to load image asset: %s" % path)
		return ImageTexture.new()
	return texture


## 键盘贴图。
##
## 贴图是 tools/gen_keyboard.py 生成的：键位读本文件的 _add_key，透视按字母数字四排
## 拟合，键帽、字母、手绘抖动全部几何生成。要改颜色或字号就改那个脚本再重跑，别手动
## P 图 —— 它同时还生成 KEY_SHAPES（按键高光的四角），两者必须同源。
##
## 更早的版本是从 ayangweb/Awesome-BongoCat 拿来的图改色而成，还在运行时逐像素扫
## 21.6 万次把桌面刷成粉色（后来烘进 PNG，省了约 70ms）。那张图没有许可证，
## docs/keyboard-research.md 当初就写了「公开发行建议重画」，现在算是还了那笔账。
func _load_keyboard_texture() -> Texture2D:
	var texture := ResourceLoader.load(KEYBOARD_TEXTURE_PATH) as Texture2D
	if texture == null:
		push_error("Failed to load keyboard asset: %s" % KEYBOARD_TEXTURE_PATH)
		return ImageTexture.new()
	return texture


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ============================================================ 启动开销（已查，结论：不动）
#
# 这个节点创建时约耗 400ms，逐块实测过了：
#
#   爪子 paw_round_v3 1254²   21.6 ms
#   鼠标贴图 1536x1024        18.8 ms
#   爪子 paw_turn 815x720     13.5 ms
#   爪子 paw_press 710x720    11.2 ms
#   键盘贴图 612x354           2.9 ms
#   本节点 _ready（61 键的键位表 + 高亮层）  6.1 ms
#
# 对照：load("res://scenes/main.tscn") 本身 565.9 ms，instantiate() 另加 161.1 ms。
#
# 上表原本还有一项「字体 MSYHBD.TTC 112.3 ms」，是本节点最大的一笔。键帽上的字改成
# 由 tools/gen_keyboard.py 烘进贴图之后，这里不再加载字体，那 112ms 没了 —— 本节点
# 的创建开销从约 400ms 降到约 290ms。
#
# 反直觉的地方：键位表构建和本节点的 _ready 各只要 5~6ms，都很便宜，不值得优化。
#
# 字体本身仍然是整个程序启动的大头，只是不在这个节点了 —— fonts/MSYH.TTC 18.8 MB +
# MSYHBD.TTC 16.1 MB，两个完整的微软雅黑，各带两万多个字形，还有 5 处引用
# （三个主题 + 两个界面场景）。
#
# 字体子集化（只留用到的字符，35MB 可压到几百 KB）**在界面那几处也不成立**：
# Doro 的人设 prompt 是用户可以自由编辑的文本框，字符集没有上界，子集之外的字会
# 显示成方框。别再来优化这个方向。
