extends Node2D

const KEYBOARD_ORIGIN := Vector2(-292, 34)
const KEY_UNIT_X := 24.0
const KEY_UNIT_Y := 22.0
const KEY_ROW_SKEW := 4.2
const KEY_COLUMN_SLOPE := 1.35
const KEY_GAP := 0.10
const KEYBOARD_WIDTH := 16.2
const KEYBOARD_ROWS := 6.0
const KEY_FLASH_TIME := 0.16

const TABLE_COLOR := Color("#fff4f6")
const TABLE_FRONT_COLOR := Color("#f7d8df")
const OUTLINE_COLOR := Color("#532831")
const BOARD_COLOR := Color("#ef9eae")
const KEY_COLOR := Color("#fffafb")
const KEY_ACTIVE_COLOR := Color("#ff7893")
const KEY_TEXT_COLOR := Color("#44242b")
const MOUSE_RECT := Rect2(184, 72, 100, 136)
const MOUSE_LEFT_CENTER := Vector2(211, 100)
const MOUSE_RIGHT_CENTER := Vector2(257, 103)

var _keys: Array[Dictionary] = []
var _keys_by_vk: Dictionary = {}
var _held_keys: Dictionary = {}
var _key_flash_until: Dictionary = {}
var _held_mouse: Dictionary = {}
var _mouse_flash_until: Dictionary = {}
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_build_keyboard()
	queue_redraw()


func _process(_delta: float) -> void:
	if not _key_flash_until.is_empty() or not _mouse_flash_until.is_empty():
		queue_redraw()


func normalize_vk(virtual_key: int) -> int:
	match virtual_key:
		0x10:
			return 0xA0
		0x11:
			return 0xA2
		0x12:
			return 0xA4
		_:
			return virtual_key


func has_key(virtual_key: int) -> bool:
	return _keys_by_vk.has(normalize_vk(virtual_key))


func is_left_key(virtual_key: int) -> bool:
	var key: Dictionary = _keys_by_vk.get(normalize_vk(virtual_key), {})
	return key.get("left", true)


func get_key_center(virtual_key: int) -> Vector2:
	var key: Dictionary = _keys_by_vk.get(normalize_vk(virtual_key), {})
	return key.get("center", Vector2(-80, 120))


func press_key(virtual_key: int) -> void:
	var key := normalize_vk(virtual_key)
	if not _keys_by_vk.has(key):
		return
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
	return MOUSE_LEFT_CENTER if button == 1 else MOUSE_RIGHT_CENTER


func _draw() -> void:
	_draw_table()
	_draw_keyboard()
	_draw_mouse()


func _draw_table() -> void:
	var table := PackedVector2Array([
		Vector2(-320, -7),
		Vector2(320, 13),
		Vector2(320, 320),
		Vector2(-320, 320)
	])
	draw_colored_polygon(table, TABLE_COLOR)
	draw_polyline(PackedVector2Array([
		Vector2(-320, -7),
		Vector2(320, 13)
	]), OUTLINE_COLOR, 4.0, true)

	var front_strip := PackedVector2Array([
		Vector2(-320, 286),
		Vector2(320, 286),
		Vector2(320, 320),
		Vector2(-320, 320)
	])
	draw_colored_polygon(front_strip, TABLE_FRONT_COLOR)
	draw_polyline(PackedVector2Array([
		Vector2(-320, 286),
		Vector2(320, 286)
	]), Color("#dca7b2"), 2.0, true)


func _draw_keyboard() -> void:
	var board := PackedVector2Array([
		_project(-0.20, -0.25),
		_project(KEYBOARD_WIDTH + 0.20, -0.25),
		_project(KEYBOARD_WIDTH + 0.20, KEYBOARD_ROWS + 0.25),
		_project(-0.20, KEYBOARD_ROWS + 0.25)
	])
	draw_colored_polygon(board, BOARD_COLOR)
	_draw_polygon_outline(board, OUTLINE_COLOR, 3.0)

	for key in _keys:
		var virtual_key: int = key["vk"]
		var active := _is_key_active(virtual_key)
		var fill := KEY_ACTIVE_COLOR if active else KEY_COLOR
		var polygon: PackedVector2Array = key["polygon"]
		draw_colored_polygon(polygon, fill)
		_draw_polygon_outline(
			polygon,
			Color("#d92f59") if active else OUTLINE_COLOR,
			2.4 if active else 1.25
		)
		_draw_key_label(key)


func _draw_key_label(key: Dictionary) -> void:
	var label: String = key["label"]
	if label.is_empty() or _font == null:
		return

	var center: Vector2 = key["center"]
	var font_size := 7
	if label.length() >= 5:
		font_size = 5
	elif label.length() >= 3:
		font_size = 6

	var text_size := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var label_angle := PI + atan2(KEY_COLUMN_SLOPE, KEY_UNIT_X)
	draw_set_transform(center, label_angle, Vector2.ONE)
	draw_string(
		_font,
		Vector2(-text_size.x * 0.5, font_size * 0.35),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		KEY_TEXT_COLOR
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_mouse() -> void:
	var body_style := _make_style(Color("#fffafb"), OUTLINE_COLOR, 38.0, 3)
	draw_style_box(body_style, MOUSE_RECT)

	var left_active := _is_mouse_active(1)
	var right_active := _is_mouse_active(2)
	var left_style := _make_style(
		KEY_ACTIVE_COLOR if left_active else Color("#ffe7ec"),
		OUTLINE_COLOR,
		10.0,
		1
	)
	var right_style := _make_style(
		KEY_ACTIVE_COLOR if right_active else Color("#ffe7ec"),
		OUTLINE_COLOR,
		10.0,
		1
	)
	draw_style_box(left_style, Rect2(194, 83, 34, 38))
	draw_style_box(right_style, Rect2(239, 86, 34, 38))
	draw_line(Vector2(234, 82), Vector2(234, 129), OUTLINE_COLOR, 2.0, true)

	if _font:
		draw_string(_font, Vector2(207, 108), "L", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, KEY_TEXT_COLOR)
		draw_string(_font, Vector2(252, 111), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, KEY_TEXT_COLOR)


func _build_keyboard() -> void:
	var rows: Array = [
		[
			_key(0xA2, "Ctrl", 1.3), _key(0x5B, "Win", 1.1), _key(0xA4, "Alt", 1.1),
			_key(0x20, "Space", 4.2), _key(0xA5, "Alt", 1.1), _key(0xA3, "Ctrl", 1.3),
			_gap(0.3), _key(0x25, "←"), _key(0x28, "↓"), _key(0x26, "↑"), _key(0x27, "→")
		],
		[
			_key(0xA0, "Shift", 2.2), _key(0x5A, "Z"), _key(0x58, "X"), _key(0x43, "C"),
			_key(0x56, "V"), _key(0x42, "B"), _key(0x4E, "N"), _key(0x4D, "M"),
			_key(0xBC, ","), _key(0xBE, "."), _key(0xBF, "/"), _key(0xA1, "Shift", 2.8)
		],
		[
			_key(0x14, "Caps", 1.8), _key(0x41, "A"), _key(0x53, "S"), _key(0x44, "D"),
			_key(0x46, "F"), _key(0x47, "G"), _key(0x48, "H"), _key(0x4A, "J"),
			_key(0x4B, "K"), _key(0x4C, "L"), _key(0xBA, ";"), _key(0xDE, "'"),
			_key(0x0D, "Enter", 2.2)
		],
		[
			_key(0x09, "Tab", 1.5), _key(0x51, "Q"), _key(0x57, "W"), _key(0x45, "E"),
			_key(0x52, "R"), _key(0x54, "T"), _key(0x59, "Y"), _key(0x55, "U"),
			_key(0x49, "I"), _key(0x4F, "O"), _key(0x50, "P"), _key(0xDB, "["),
			_key(0xDD, "]"), _key(0xDC, "\\", 1.5)
		],
		[
			_key(0xC0, "`"), _key(0x31, "1"), _key(0x32, "2"), _key(0x33, "3"),
			_key(0x34, "4"), _key(0x35, "5"), _key(0x36, "6"), _key(0x37, "7"),
			_key(0x38, "8"), _key(0x39, "9"), _key(0x30, "0"), _key(0xBD, "-"),
			_key(0xBB, "="), _key(0x08, "Back", 2.0)
		],
		[
			_key(0x1B, "Esc", 1.2), _gap(0.3), _key(0x70, "F1"), _key(0x71, "F2"),
			_key(0x72, "F3"), _key(0x73, "F4"), _key(0x74, "F5"), _key(0x75, "F6"),
			_key(0x76, "F7"), _key(0x77, "F8"), _key(0x78, "F9"), _key(0x79, "F10"),
			_key(0x7A, "F11"), _key(0x7B, "F12"), _gap(0.3), _key(0x2E, "Del", 1.2)
		]
	]

	for row_index in range(rows.size()):
		var cursor := 0.0
		for definition: Dictionary in rows[row_index]:
			var width: float = definition["width"]
			if definition["vk"] < 0:
				cursor += width
				continue

			var left := cursor + KEY_GAP
			var right := cursor + width - KEY_GAP
			var top := row_index + KEY_GAP
			var bottom := row_index + 1.0 - KEY_GAP
			var polygon := PackedVector2Array([
				_project(left, top),
				_project(right, top),
				_project(right, bottom),
				_project(left, bottom)
			])
			var key := {
				"vk": definition["vk"],
				"label": definition["label"],
				"polygon": polygon,
				"center": _project(cursor + width * 0.5, row_index + 0.5),
				"left": cursor + width * 0.5 < KEYBOARD_WIDTH * 0.5
			}
			_keys.append(key)
			_keys_by_vk[definition["vk"]] = key
			cursor += width


func _key(virtual_key: int, label: String, width: float = 1.0) -> Dictionary:
	return {"vk": virtual_key, "label": label, "width": width}


func _gap(width: float) -> Dictionary:
	return {"vk": -1, "label": "", "width": width}


func _project(column: float, row: float) -> Vector2:
	return KEYBOARD_ORIGIN + Vector2(
		column * KEY_UNIT_X + row * KEY_ROW_SKEW,
		column * KEY_COLUMN_SLOPE + row * KEY_UNIT_Y
	)


func _is_key_active(virtual_key: int) -> bool:
	if _held_keys.has(virtual_key):
		return true
	return _now() < float(_key_flash_until.get(virtual_key, -1.0))


func _is_mouse_active(button: int) -> bool:
	if _held_mouse.has(button):
		return true
	return _now() < float(_mouse_flash_until.get(button, -1.0))


func _draw_polygon_outline(polygon: PackedVector2Array, color: Color, width: float) -> void:
	var outline := PackedVector2Array(polygon)
	outline.append(polygon[0])
	draw_polyline(outline, color, width, true)


func _make_style(fill: Color, border: Color, radius: float, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(int(radius))
	return style


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
