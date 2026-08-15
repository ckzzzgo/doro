extends Node2D

## 工作模式（键盘模式）的双臂渲染器。
##
## 唯一拓扑：每条手臂 = 桌沿根部 → 腕前直线段 → 伸入爪子腕口的填充尖端
## （直臂：根部到腕口全程一条直线，无弯曲段）。腕口骨点（wrist_bone）与
## 腕口朝向（outward）由 input_reaction 按爪子贴图实测腕口反算，本渲染器
## 不再自行猜测：
##   - 手臂中心线终点与末端切线完全由 wrist_bone / outward 决定；
##   - 填充伸入腕口 ARM_TIP_OVERLAP 并向外轮廓中心线锥缩，由前景爪子遮住；
##   - 双侧轮廓在腕口切面处精确停止，与贴图腕管轮廓相接，不进入爪子内部；
##   - 无任何遮缝/短臂补丁，远近按键共用同一个连续求解器。

const PAW_ARM_COLOR := Color("#fcfbfb")
const PAW_ARM_OUTLINE_COLOR := Color("#150f11")
const TABLE_SURFACE_COLOR := Color("#fff6f8")
const EDGE_LINE_CLEARANCE := 2.4

const ARM_RUN_IN_STEPS := 7
# 腕前直线段长度比例/上限：保证可见手臂在腕口前已被拉直到贴图腕管方向。
const ARM_RUN_IN_RATIO := 0.45
const ARM_RUN_IN_MAX := 48.0
# 填充伸入腕口的深度；尖端宽度锥缩到腕管内腔以内，贴图不透明腕管将其遮住。
const ARM_TIP_OVERLAP := 10.0
# 填充锥缩提前量：在腕口切面前 FILL_TAPER_AHEAD 像素处就开始收窄，使填充
# 边缘在轮廓截停处（及更深处）已经明显窄于腕口开口，杜绝白色填充毛边。
const FILL_TAPER_AHEAD := 6.0
const ROOT_IN_FRONT_OF_EDGE := 4.5
# 手臂末端收窄范围：腕骨距桌沿小于此值开始变细，到桌沿（depth=0）缩成零；
# 腕骨没入桌沿后沿后整条隐藏。腕点始终锚定爪子，不做位移插值，回收不脱节。
const RETRACT_TAPER_DEPTH := 12.0
const TABLE_EDGE_OVERLAP := 10.0
const ARM_CONTACT_SHADOW_OFFSET := Vector2(1.4, 2.2)
const ARM_CONTACT_SHADOW_COLOR := Color(0.34, 0.10, 0.15, 0.16)
# 轮廓在腕口切面向贴图内侧的微小过冲（被前景贴图腕管遮住，保证不留缝）。
const WRIST_OUTLINE_OVERSHOOT := -0.6
# 桌沿衬底带的纵深范围（桌沿后 5px 至桌前 12px）。
const EDGE_UNDERLAY_BEHIND := -5.0
const EDGE_UNDERLAY_FRONT := 12.0

const TABLE_BACK_LEFT := Vector2(-320, -20)
const TABLE_BACK_RIGHT := Vector2(320, 64)

const SIDE_KEYBOARD := 0
const SIDE_MOUSE := 1

class _ArmLayer:
	extends Node2D
	var underlay_polys: Array = []
	var shadow_polys: Array = []
	var fill_polys: Array = []
	var outline_lines: Array = []
	var outline_widths: Array = []
	var shadow_color := Color(0.34, 0.10, 0.15, 0.16)
	var underlay_color := Color("#fff6f8")
	var outline_color := Color("#150f11")
	var fill_color := Color("#fcfbfb")

	func _draw() -> void:
		for poly in underlay_polys:
			if poly.size() >= 3:
				draw_colored_polygon(poly, underlay_color)
		for poly in shadow_polys:
			if poly.size() >= 3:
				draw_colored_polygon(poly, shadow_color)
		for poly in fill_polys:
			if poly.size() >= 3:
				draw_colored_polygon(poly, fill_color)
		for index in range(outline_lines.size()):
			var line = outline_lines[index]
			if line.size() >= 2:
				draw_polyline(line, outline_color, outline_widths[index], true)

var _front_layer: Node2D


func _ready() -> void:
	_front_layer = _ArmLayer.new()
	_front_layer.name = "ArmLayerFront"
	_front_layer.z_index = 1
	_front_layer.underlay_color = TABLE_SURFACE_COLOR
	_front_layer.shadow_color = ARM_CONTACT_SHADOW_COLOR
	_front_layer.outline_color = PAW_ARM_OUTLINE_COLOR
	_front_layer.fill_color = PAW_ARM_COLOR
	add_child(_front_layer)


## 每帧由 input_reaction 调用。腕口半宽为贴图实测外轮廓半宽（世界像素），
## 轮廓宽度同样来自贴图实测，保证生成手臂与爪子腕管的轮廓粗细一致。
func update_arms(keyboard_root: Vector2, keyboard_bone: Vector2,
		mouse_root: Vector2, mouse_bone: Vector2,
		keyboard_visible: bool = true, mouse_visible: bool = true,
		keyboard_wrist_half_width: float = 20.0,
		mouse_wrist_half_width: float = 20.0,
		keyboard_wrist_outward: Vector2 = Vector2.UP,
		mouse_wrist_outward: Vector2 = Vector2.UP,
		keyboard_outline_width: float = 1.9,
		mouse_outline_width: float = 1.9) -> void:
	_front_layer.underlay_polys.clear()
	_front_layer.shadow_polys.clear()
	_front_layer.fill_polys.clear()
	_front_layer.outline_lines.clear()
	_front_layer.outline_widths.clear()

	if keyboard_visible:
		_add_arm(
			keyboard_root,
			keyboard_bone,
			keyboard_wrist_half_width,
			keyboard_wrist_outward,
			keyboard_outline_width
		)
	if mouse_visible:
		_add_arm(
			mouse_root,
			mouse_bone,
			mouse_wrist_half_width,
			mouse_wrist_outward,
			mouse_outline_width
		)

	_front_layer.queue_redraw()


## 手臂根部：肩部锚点在桌沿后沿线上的投影，向桌面一侧推出固定距离。
## 侧向偏移连续（不做符号翻转），避免骨点掠过根部垂线时根部位移跳变。
func get_arm_root(shoulder: Vector2, reference: Vector2) -> Vector2:
	var edge_tangent := _table_edge_tangent()
	var edge_point := _project_to_table_edge(shoulder)
	var lateral := clampf(
		(reference - edge_point).dot(edge_tangent) * 0.04,
		-3.0,
		3.0
	)
	return (
		edge_point
		+ edge_tangent * lateral
		+ _table_surface_normal() * ROOT_IN_FRONT_OF_EDGE
	)


## 判断腕骨是否已没入桌沿后沿（此时手臂整条隐藏）。与 _add_arm 的隐藏判定
## 共用同一几何，供 input_reaction 决定爪子是否该在收回瞬间切回无腕口的
## 待机圆爪贴图，避免出现"空腕口"的过渡爪悬在桌沿。
func is_wrist_retracted(root: Vector2, wrist_bone: Vector2) -> bool:
	var desk_normal := _table_surface_normal()
	var edge_point := _project_to_table_edge(root)
	return (wrist_bone - edge_point).dot(desk_normal) <= 0.0


func _add_arm(
	root: Vector2,
	wrist_bone: Vector2,
	wrist_outer_half: float,
	wrist_outward: Vector2,
	outline_width: float
) -> void:
	var outward := wrist_outward.normalized()
	if outward == Vector2.ZERO:
		outward = Vector2.UP
	var desk_normal := _table_surface_normal()

	# 平滑缩回：腕骨没入桌沿后沿（从桌面消失）即整条隐藏。腕骨逼近桌沿时
	# 手臂自然缩短（腕点始终锚定爪子，不做位移插值），并在最后
	# RETRACT_TAPER_DEPTH 内宽度同步收窄，到桌沿缩成零，不瞬断、不脱节。
	var edge_point := _project_to_table_edge(root)
	var wrist_depth := (wrist_bone - edge_point).dot(desk_normal)
	if wrist_depth <= 0.0:
		return
	if wrist_depth < RETRACT_TAPER_DEPTH:
		var taper := clampf(wrist_depth / RETRACT_TAPER_DEPTH, 0.0, 1.0)
		wrist_outer_half *= taper
		outline_width *= taper

	# 中心线：根部 → 腕前直线段 → 腕口内尖端（直臂，无肘部）。
	# 整条手臂是"根部→腕口"的一条直线：前臂方向即根部指向腕口的方向，
	# 腕口前仍保留 run_in 直线段、尖端沿同一直线伸入爪子，不引入折角。
	var reach := root.distance_to(wrist_bone)
	var run_in := minf(
		clampf(reach * ARM_RUN_IN_RATIO, 0.0, ARM_RUN_IN_MAX),
		maxf(reach - 3.0, 0.0)
	)
	var forearm_dir := (wrist_bone - root).normalized()
	if forearm_dir == Vector2.ZERO:
		forearm_dir = desk_normal
	run_in = minf(run_in, maxf(reach - 2.0, 0.0))
	var run_start := wrist_bone - forearm_dir * run_in
	var tip := wrist_bone + forearm_dir * ARM_TIP_OVERLAP
	var path := PackedVector2Array([root, run_start])
	for step in range(1, ARM_RUN_IN_STEPS + 1):
		var amount := float(step) / float(ARM_RUN_IN_STEPS)
		path.append(run_start.lerp(tip, amount))

	# 宽度剖面：轮廓中心线半宽恒定 = 贴图腕管外半宽 - 半条轮廓宽，
	# 与贴图腕管在切面处精确对接；伸入腕口的填充尖端锥缩到内腔以内。
	var centerline_half: float = maxf(wrist_outer_half - outline_width * 0.5, 1.0)
	# 尖端目标宽度比内腔略窄（0.88），与轮廓截停处相比留出更宽的余量，
	# 即使爪子开口边缘有亚像素误差也不会露出白色填充。
	var inner_half: float = maxf(wrist_outer_half - outline_width, 1.0) * 0.88
	var fill_half_widths := PackedFloat32Array()
	var taper_span := ARM_TIP_OVERLAP + FILL_TAPER_AHEAD
	for point in path:
		var depth := (point - wrist_bone).dot(outward)
		if depth >= FILL_TAPER_AHEAD:
			fill_half_widths.append(centerline_half)
		else:
			var amount := clampf((FILL_TAPER_AHEAD - depth) / taper_span, 0.0, 1.0)
			fill_half_widths.append(lerpf(centerline_half, inner_half, amount))

	var sides := _build_side_lines(path, fill_half_widths)
	var fill_left: PackedVector2Array = sides[0]
	var fill_right: PackedVector2Array = sides[1]

	# 轮廓侧线：恒定半宽，并在腕口切面前 0.6px 处精确截停（微小过冲由
	# 前景贴图的不透明腕管遮住，保证既不留缝也不穿进爪子内部）。
	var line_sides := _build_side_lines(path, _constant_widths(path.size(), centerline_half))
	var outline_left := _trim_at_wrist_plane(line_sides[0], wrist_bone, outward)
	var outline_right := _trim_at_wrist_plane(line_sides[1], wrist_bone, outward)
	var start_direction := (path[1] - path[0]).normalized()
	if start_direction == Vector2.ZERO:
		start_direction = desk_normal
	var cap_arc := _build_root_cap_arc(root, start_direction, centerline_half)
	var outline := PackedVector2Array()
	for index in range(outline_left.size() - 1, -1, -1):
		outline.append(outline_left[index])
	for index in range(1, cap_arc.size()):
		outline.append(cap_arc[index])
	for index in range(1, outline_right.size()):
		outline.append(outline_right[index])
	_front_layer.outline_lines.append(outline)
	_front_layer.outline_widths.append(outline_width)

	# 填充：圆头根部 + 整条 ribbon（含腕口内锥缩尖端）。衬底只抹掉手臂
	# 穿越桌沿那一窄条的桌沿描边（贴着手臂的带状区域），不再在桌沿后方
	# 的背景里留下大椭圆色块。
	var band_half_width := (
		(centerline_half + outline_width * 0.5 + EDGE_LINE_CLEARANCE)
		* clampf((reach - RETRACT_TAPER_DEPTH) / 26.0, 0.3, 1.0)
	)
	for segment in _build_edge_underlay(path, root, start_direction, band_half_width):
		_front_layer.underlay_polys.append(segment)
	_front_layer.fill_polys.append(
		_build_root_cap(root, start_direction, centerline_half)
	)
	for segment in _build_fill_strip(path, fill_left, fill_right):
		_front_layer.fill_polys.append(segment)

	# 接触阴影只出现在手臂真正压上桌面的情况下。
	if reach > 16.0:
		_front_layer.shadow_polys.append(
			_build_edge_contact_shadow(root, centerline_half)
		)


## 沿中心线按每点半宽生成两侧偏移线。
func _build_side_lines(
	center_points: PackedVector2Array,
	half_widths: PackedFloat32Array
) -> Array:
	var last_index := center_points.size() - 1
	var left_side := PackedVector2Array()
	var right_side := PackedVector2Array()
	for index in range(center_points.size()):
		var previous := center_points[maxi(index - 1, 0)]
		var next := center_points[mini(index + 1, last_index)]
		var tangent := (next - previous).normalized()
		if tangent == Vector2.ZERO:
			tangent = Vector2.DOWN
		var normal := Vector2(-tangent.y, tangent.x)
		left_side.append(center_points[index] + normal * half_widths[index])
		right_side.append(center_points[index] - normal * half_widths[index])
	return [left_side, right_side]


func _constant_widths(count: int, half_width: float) -> PackedFloat32Array:
	var widths := PackedFloat32Array()
	for index in range(count):
		widths.append(half_width)
	return widths


## 把轮廓侧线在腕口切面（朝向外 0.6px 过冲）处截停。
func _trim_at_wrist_plane(
	points: PackedVector2Array,
	wrist_bone: Vector2,
	outward: Vector2
) -> PackedVector2Array:
	var trimmed := PackedVector2Array()
	for index in range(points.size()):
		var point := points[index]
		var depth := (point - wrist_bone).dot(outward)
		if depth >= WRIST_OUTLINE_OVERSHOOT:
			trimmed.append(point)
			continue
		if index > 0:
			var previous := points[index - 1]
			var previous_depth := (previous - wrist_bone).dot(outward)
			if previous_depth > WRIST_OUTLINE_OVERSHOOT and not is_equal_approx(previous_depth, depth):
				var amount := (previous_depth - WRIST_OUTLINE_OVERSHOOT) / (previous_depth - depth)
				trimmed.append(previous.lerp(point, clampf(amount, 0.0, 1.0)))
		break
	return trimmed


func _build_fill_strip(
	center_points: PackedVector2Array,
	left_side: PackedVector2Array,
	right_side: PackedVector2Array
) -> Array:
	var segments: Array = []
	for index in range(center_points.size() - 1):
		_append_fill_triangle(
			segments,
			left_side[index],
			left_side[index + 1],
			right_side[index + 1]
		)
		_append_fill_triangle(
			segments,
			left_side[index],
			right_side[index + 1],
			right_side[index]
		)
	return segments


func _append_fill_triangle(
	segments: Array,
	point_a: Vector2,
	point_b: Vector2,
	point_c: Vector2
) -> void:
	if absf((point_b - point_a).cross(point_c - point_a)) < 0.01:
		return
	segments.append(PackedVector2Array([point_a, point_b, point_c]))


## 根部圆头（填充/衬底共用）：垂直于起始切线的半圆，朝向根部后方。
func _build_root_cap(
	center: Vector2,
	path_direction: Vector2,
	radius: float
) -> PackedVector2Array:
	var cap := PackedVector2Array()
	var side := Vector2(-path_direction.y, path_direction.x)
	for index in range(19):
		var angle := TAU * float(index) / 18.0
		cap.append(
			center
			+ side * cos(angle) * radius
			+ path_direction * sin(angle) * radius
		)
	return cap


## 桌沿穿越衬底：沿手臂中心线截取桌沿前后 [-5, +12]px 的一段，按带状
## 半宽生成三角形条带（不用整多边形，弯曲段内侧不会自交导致三角化失败）。
func _build_edge_underlay(
	path: PackedVector2Array,
	root: Vector2,
	start_direction: Vector2,
	band_half_width: float
) -> Array:
	var normal := _table_surface_normal()
	var edge_point := _project_to_table_edge(root)
	var extended := PackedVector2Array()
	extended.append(root - start_direction * 10.0)
	for point in path:
		extended.append(point)
	var segment := PackedVector2Array()
	for index in range(extended.size()):
		var point := extended[index]
		var depth := (point - edge_point).dot(normal)
		if depth >= EDGE_UNDERLAY_BEHIND and depth <= EDGE_UNDERLAY_FRONT:
			if segment.is_empty() and index > 0:
				var previous := extended[index - 1]
				var previous_depth := (previous - edge_point).dot(normal)
				if not is_equal_approx(previous_depth, depth):
					var amount := (EDGE_UNDERLAY_BEHIND - previous_depth) / (depth - previous_depth)
					segment.append(previous.lerp(point, clampf(amount, 0.0, 1.0)))
			segment.append(point)
			continue
		if depth > EDGE_UNDERLAY_FRONT and not segment.is_empty():
			var previous := extended[index - 1]
			var previous_depth := (previous - edge_point).dot(normal)
			if not is_equal_approx(previous_depth, depth):
				var amount := (EDGE_UNDERLAY_FRONT - previous_depth) / (depth - previous_depth)
				segment.append(previous.lerp(point, clampf(amount, 0.0, 1.0)))
			break
	if segment.size() < 2:
		return []
	var sides := _build_side_lines(segment, _constant_widths(segment.size(), band_half_width))
	return _build_fill_strip(segment, sides[0], sides[1])


## 根部轮廓连接弧：从一侧轮廓起点绕根部后方到另一侧。
func _build_root_cap_arc(
	center: Vector2,
	path_direction: Vector2,
	radius: float
) -> PackedVector2Array:
	var side := Vector2(-path_direction.y, path_direction.x)
	var arc := PackedVector2Array()
	for index in range(11):
		var angle := PI * float(index) / 10.0
		arc.append(
			center
			+ side * cos(angle) * radius
			- path_direction * sin(angle) * radius
		)
	return arc


func _build_edge_contact_shadow(
	root: Vector2,
	half_width: float
) -> PackedVector2Array:
	var tangent := _table_edge_tangent()
	var normal := _table_surface_normal()
	var center := _project_to_table_edge(root) + normal * 5.0
	var shadow := PackedVector2Array()
	for index in range(16):
		var angle := TAU * float(index) / 16.0
		shadow.append(
			center
			+ tangent * cos(angle) * half_width * 0.92
			+ normal * sin(angle) * 5.4
		)
	return shadow


func _table_edge_tangent() -> Vector2:
	return (TABLE_BACK_RIGHT - TABLE_BACK_LEFT).normalized()


func _table_surface_normal() -> Vector2:
	var tangent := _table_edge_tangent()
	var normal := Vector2(-tangent.y, tangent.x)
	if normal.y < 0.0:
		normal = -normal
	return normal


func _project_to_table_edge(point: Vector2) -> Vector2:
	var tangent := _table_edge_tangent()
	return TABLE_BACK_LEFT + tangent * (point - TABLE_BACK_LEFT).dot(tangent)


func _table_back_edge_y(x_position: float) -> float:
	var amount := clampf(
		(x_position - TABLE_BACK_LEFT.x) / (TABLE_BACK_RIGHT.x - TABLE_BACK_LEFT.x),
		0.0,
		1.0
	)
	return lerpf(TABLE_BACK_LEFT.y, TABLE_BACK_RIGHT.y, amount)
