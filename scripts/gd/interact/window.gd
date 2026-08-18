extends Node2D

const DoroLog = preload("res://scripts/gd/utils/debug_log.gd")

@export var enable_window_drag:bool = true
@export var enable_docking: bool = true
@export var model: GDCubismUserModel
@export var anim_controller: AnimationController
@export var dock_thresh:float = 0.3
@export var dock_pop_offset:int = 110
@export var dock_pop_expression_reset_time:float = 30
@export var dock_to_taskbar:bool = false

const STEP_SIZE = 0.05
const MIN_SCALE = 0.1

const DOCK_LEFT = 0
const DOCK_RIGHT = 1
const DOCK_TOP = 2
const DOCK_BOTTOM = 3
const DOCK_NONE = 4
const DOCK_POS_OFFSET = 380


@onready var BASE_WINDOW_WIDTH = get_tree().root.get_size().x
@onready var BASE_WINDOW_HEIGHT = get_tree().root.get_size().y
@onready var mouseTracker = get_node("/root/MouseTracker")
@onready var windowManager = get_node("/root/WindowManager")
@onready var mouseDetection = get_node("/root/MouseDetection")
@onready var config: ConfigManager = get_node("/root/Config")

var dragging: bool = false
var input_mode_active: bool = false
var docking: bool = false
var docking_dir: int = DOCK_NONE
var docking_time_counter:TimeCounter = TimeCounter.new(dock_pop_expression_reset_time)

var window_scale: float = 1.0
var drag_start_mouse_pos: Vector2i
var drag_start_window_pos: Vector2i
var _drag_hover_lost_frames: int = 0

var fullscreen_check_timer = Timer.new()
var is_other_app_fullscreen = false

signal window_scale_changed
signal window_pos_changed
signal other_app_fullscreen
signal window_middle_click
signal window_docking

func _ready() -> void:
	load_config()
	bind_signals()
	set_up_fullscreen_detector()
	update_window()

	add_child(docking_time_counter)
	mouseDetection.connect("MouseEntered", docking_time_counter.increase)

func _process(delta: float) -> void:
	dock_pop()
	_guard_drag_stuck()

func _input(event: InputEvent) -> void:
	# 左键拖动窗口：即使在输入模式（打字模仿）下也允许拖动，方便用户随时把
	# 桌宠移开，不会在打字时被挡住屏幕。输入模式下仍跳过停靠/滚轮缩放等。
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if enable_window_drag:
				var move_effect: MoveEffect = $GDCubismUserModel/Animation/EffectMove
				var rand_move = $GDCubismUserModel/Animation/EffectMove/EffectRandMove
				if move_effect.is_moving:
					move_effect.stop()
				rand_move.timer.set_paused(true)
				dragging = true
				drag_start_mouse_pos = mouseTracker.GetMousePosition()
				drag_start_window_pos = get_tree().root.position
				DoroLog.d("[DORO] DRAG press mouse=%s win=%s input_mode=%s t=%d" % [str(drag_start_mouse_pos), str(drag_start_window_pos), str(input_mode_active), Time.get_ticks_msec()])
		else:
			_end_drag("release")
		return

	# 拖动过程中移动窗口：同样放到输入模式判定之前，否则打字模式下鼠标一动
	# 就被下面的 input_mode_active 分支把 dragging 重置，拖动依然失败。
	if event is InputEventMouseMotion and dragging:
		var cur_mouse_pos = mouseTracker.GetMousePosition()
		var delta_pos = cur_mouse_pos - drag_start_mouse_pos
		var new_position = drag_start_window_pos + delta_pos
		if enable_docking:
			new_position = dock_to_edge(new_position, dock_thresh)
		get_tree().root.position = new_position
		return

	if input_mode_active:
		if dragging:
			DoroLog.d("[DORO] DRAG force-reset by input_mode gate t=%d" % Time.get_ticks_msec())
		dragging = false
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed and not docking:
				window_middle_click.emit()
		# Window rescaling
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			increase_window_size()
			window_scale_changed.emit("window_scale", window_scale)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			decrease_window_size()
			window_scale_changed.emit("window_scale", window_scale)

## 结束一次拖动：与松开左键共用同一收尾逻辑，保证两条路径行为一致。
func _end_drag(reason: String) -> void:
	if not dragging:
		return
	dragging = false
	var rand_move = $GDCubismUserModel/Animation/EffectMove/EffectRandMove
	if rand_move.enable:
		rand_move.timer.set_paused(false)
	window_pos_changed.emit("window_pos", get_tree().root.position)
	DoroLog.d("[DORO] DRAG end (%s) win=%s t=%d" % [reason, str(get_tree().root.position), Time.get_ticks_msec()])

## 拖动过程中，若鼠标移出模型（模型被停靠推离窗口、或鼠标甩出窗口），窗口会
## 被 MouseDetection 置为点击穿透（WS_EX_TRANSPARENT），此时松开的 WM_LBUTTONUP
## 会被丢弃，dragging 将永远卡在 true —— 之后鼠标一旦回到模型上，窗口就会一直
## 贴着鼠标跑。这里兜底：鼠标连续几帧不在模型上（即点击穿透已开启、抬起必被
## 丢弃）时，主动收尾这次拖动。
func _guard_drag_stuck() -> void:
	if not dragging:
		_drag_hover_lost_frames = 0
		return
	if mouseDetection.mouse_hovered:
		_drag_hover_lost_frames = 0
		return
	_drag_hover_lost_frames += 1
	if _drag_hover_lost_frames >= 3:
		_end_drag("mouse-left-model")

func increase_window_size():
	window_scale += STEP_SIZE
	update_window()

func decrease_window_size():
	if window_scale < MIN_SCALE:
		return
	elif window_scale > MIN_SCALE:
		window_scale -= STEP_SIZE

	update_window()

func update_window():
	# 计算新的窗口尺寸
	var new_width = int(BASE_WINDOW_WIDTH * window_scale)
	var new_height = int(BASE_WINDOW_HEIGHT * window_scale)

	# 更新主视窗的大小
	get_tree().root.set_size(Vector2i(new_width, new_height))
	if enable_docking:
		var new_position = dock_to_edge(get_tree().root.position, dock_thresh)
		get_tree().root.position = new_position

func load_config():
	window_scale = config.get_window_config("window_scale", window_scale)
	var saved_pos = config.get_window_config("window_pos", get_tree().root.position)
	get_tree().root.position = _ensure_on_screen(saved_pos)


## 保证恢复出来的窗口位置至少还落在某块屏幕上。
##
## 上次保存的位置是当时那套显示器布局下的坐标。副屏被拔掉/关掉、分辨率或缩放改变、
## 多屏排布调整之后，那个坐标可能整个落到屏幕之外 —— 桌宠一启动就是隐形的，
## 用户会以为程序没打开，而且鼠标根本够不着她。
##
## 判据用「窗口中心是否落在某块屏幕内」：中心在屏内就一定抓得住；只有一条边勉强
## 露在屏幕上是够不着的，不算数。都不满足就放到主屏中央。
func _ensure_on_screen(pos: Vector2i) -> Vector2i:
	var size := Vector2i(
		int(BASE_WINDOW_WIDTH * window_scale),
		int(BASE_WINDOW_HEIGHT * window_scale))
	var center := pos + size / 2

	for i in DisplayServer.get_screen_count():
		var r := Rect2i(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i))
		if r.has_point(center):
			return pos

	var scr := DisplayServer.get_primary_screen()
	var sp := DisplayServer.screen_get_position(scr)
	var ss := DisplayServer.screen_get_size(scr)
	var fixed := sp + (ss - size) / 2
	push_warning("上次保存的窗口位置 %s 已不在任何屏幕内（显示器布局变了？），改到主屏中央 %s"
		% [str(pos), str(fixed)])
	return fixed

func bind_signals():
	window_scale_changed.connect(config.on_window_config_change)
	window_pos_changed.connect(config.on_window_config_change)
	other_app_fullscreen.connect($StatusIndicator/PopupMenu._on_other_app_fullscreen)
	# 这三条原先漏了：window_middle_click / window_docking 一直在 emit，但接收端的
	# gui.gd、chat_dialog_window.gd 里那几个 _on_ 回调从没被连上，表现为中键点桌宠
	# 没反应、停靠到屏幕边缘后工具栏和聊天框仍浮在原处不收起。
	window_middle_click.connect($GUI._on_window_middle_click)
	window_docking.connect($GUI._on_window_docking)
	window_docking.connect($GUI/ChatDialog._on_window_docking)

func set_up_fullscreen_detector():
	fullscreen_check_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	fullscreen_check_timer.wait_time = 0.5
	fullscreen_check_timer.timeout.connect(_check_other_app_fullscreen)
	add_child(fullscreen_check_timer)
	fullscreen_check_timer.start()
	set_fullscreen_status(config.get_section(&"system").get_prop(&"auto_hide"))

func set_fullscreen_status(status: bool):
	fullscreen_check_timer.set_paused(!status)

func dock_to_edge(win_pos: Vector2i, thresh: float):
	var screen_index := DisplayServer.window_get_current_screen()
	var screen_rect: Rect2i

	if dock_to_taskbar:
		screen_rect = DisplayServer.screen_get_usable_rect(screen_index)
	else:
		screen_rect = Rect2i(
			DisplayServer.screen_get_position(screen_index),
			DisplayServer.screen_get_size(screen_index)
		)

	var win_size = DisplayServer.window_get_size()
	var win_cpos = win_pos + win_size / 2

	var thresh_pixel = int(win_size.x * thresh)
	var dis_mouse_win_cpos = DisplayServer.mouse_get_position().distance_to(get_tree().root.position + win_size / 2)

	# 打字模式也允许拖到屏幕边缘触发停靠，但只更新停靠状态、不改动模型姿态 /
	# Body_group / 表情（停靠姿态由 dock_pop 每帧维护），避免干扰打字模仿的可见性。
	var reset_pose := not input_mode_active

	if  dragging and (dis_mouse_win_cpos > win_size.x or dis_mouse_win_cpos > win_size.y):
		# 当拖动时，鼠标距离窗口超出窗口大小时不停靠，防止窗口移不出当前屏幕
		if reset_pose:
			model.set_rotation_degrees(0)
			model.position = Vector2.ZERO
			model.Body_group = 1
			window_docking.emit(false, DOCK_NONE)
			anim_controller.set_expression("Idle")
			docking_time_counter.reset()
		docking = false
		docking_dir = DOCK_NONE
		return win_pos
	elif win_cpos.x - thresh_pixel < screen_rect.position.x:
		# 左侧停靠
		return _dock_to(win_pos, win_size, screen_rect, DOCK_LEFT)
	elif win_cpos.x + thresh_pixel > screen_rect.end.x:
		# 右侧停靠
		return _dock_to(win_pos, win_size, screen_rect, DOCK_RIGHT)
	elif win_cpos.y - thresh_pixel < screen_rect.position.y:
		# 顶部停靠
		return _dock_to(win_pos, win_size, screen_rect, DOCK_TOP)
	elif win_cpos.y + thresh_pixel > screen_rect.end.y:
		# 底部停靠
		return _dock_to(win_pos, win_size, screen_rect, DOCK_BOTTOM)
	else:
		# 不停靠
		if reset_pose:
			model.set_rotation_degrees(0)
			model.position = Vector2.ZERO
			model.Body_group = 1
			window_docking.emit(false, DOCK_NONE)
			anim_controller.set_expression("Idle")
			docking_time_counter.reset()
		docking = false
		docking_dir = DOCK_NONE
		return win_pos

	return win_pos

func _dock_to(win_pos: Vector2i, win_size: Vector2i, screen_rect: Rect2i, dir: int) -> Vector2i:
	docking = true
	docking_dir = dir
	model.flip_h = false
	match dir:
		DOCK_LEFT:
			model.set_rotation_degrees(85)
			model.position.x = -DOCK_POS_OFFSET
			model.Body_group = 0
			window_docking.emit(true, DOCK_LEFT)
			return Vector2i(screen_rect.position.x, win_pos.y)
		DOCK_RIGHT:
			model.set_rotation_degrees(-95)
			model.position.x = DOCK_POS_OFFSET
			model.Body_group = 0
			window_docking.emit(true, DOCK_RIGHT)
			return Vector2i(screen_rect.end.x - win_size.x, win_pos.y)
		DOCK_TOP:
			model.set_rotation_degrees(175)
			model.position.y = -DOCK_POS_OFFSET
			model.Body_group = 0
			window_docking.emit(true, DOCK_TOP)
			return Vector2i(win_pos.x, screen_rect.position.y)
		DOCK_BOTTOM:
			model.set_rotation_degrees(-5)
			model.position.y = DOCK_POS_OFFSET
			model.Body_group = 0
			window_docking.emit(true, DOCK_BOTTOM)
			return Vector2i(win_pos.x, screen_rect.end.y - win_size.y)
	return win_pos

func dock_pop():
	# 打字模式下只有「没停靠」时才让位给打字姿态。一旦停靠，停靠姿态优先 ——
	# 否则整个探头逻辑在停靠期间根本不跑，鼠标扫过露出的部分毫无反应，
	# 而普通模式下是有反应的，两种模式行为不一致。
	# （input_reaction 在停靠时已经把打字用的桌面/爪子隐藏了，且它对姿态的应用是
	#   边沿触发的，只在停靠状态变化时执行一次，不会和这里每帧打架。）
	if input_mode_active and not docking:
		return

	if not docking:
		_set_dock_position(docking_dir)
		return

	# 每帧保持停靠姿态（旋转 / Body_group / 朝向），防止打字模式退出
	# 等路径把模型复位成未停靠的样子。
	_set_dock_rotation(docking_dir)
	model.Body_group = 0
	model.flip_h = false

	# 拖动中必须继续保持探头位，绝不能缩回：探头时可抓区域是露出的一整条，
	# 一旦按下左键就把模型缩回去，鼠标当场落到透明像素上 —— MouseDetection 会
	# 开启点击穿透，抬起事件被系统丢弃，这次拖动随即被 _guard_drag_stuck 撤销。
	# 结果就是"抓着她露出来的那截，怎么都拖不出边缘"。
	if dragging or mouseDetection.mouse_hovered:
		_set_dock_position(docking_dir, true)

		# 拖动中不改表情：正在被拖走，探头的疑惑/生气递进没有意义。
		if not dragging:
			var count = docking_time_counter.get_count()
			if count >= 6:
				anim_controller.set_expression("DockPopAngry")
			elif count >= 3:
				anim_controller.set_expression("Doubt")
	else:
		anim_controller.set_expression("Idle")
		_set_dock_position(docking_dir)

func _set_dock_rotation(dir: int) -> void:
	match dir:
		DOCK_LEFT:
			model.set_rotation_degrees(85)
		DOCK_RIGHT:
			model.set_rotation_degrees(-95)
		DOCK_TOP:
			model.set_rotation_degrees(175)
		DOCK_BOTTOM:
			model.set_rotation_degrees(-5)
		DOCK_NONE:
			model.set_rotation_degrees(0)

func _set_dock_position(dir: int, peek: bool = false) -> void:
	var offset := dock_pop_offset if peek else 0
	match dir:
		DOCK_LEFT:
			model.position.x = -DOCK_POS_OFFSET + offset
		DOCK_RIGHT:
			model.position.x = DOCK_POS_OFFSET - offset
		DOCK_TOP:
			model.position.y = -DOCK_POS_OFFSET + offset
		DOCK_BOTTOM:
			model.position.y = DOCK_POS_OFFSET - offset

func _check_other_app_fullscreen():
	var state = windowManager.IsOtherAppFullscreen()
	if state != is_other_app_fullscreen:
		other_app_fullscreen.emit(state)
	is_other_app_fullscreen = state
