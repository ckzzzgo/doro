extends Node2D

@export var model: GDCubismUserModel
@export var window: Node2D
@export var move_effect: MoveEffect
@export var rand_move: Node

const InputStageScript = preload("res://scripts/gd/interact/input_stage_v3.gd")
const WorkArmsScript = preload("res://scripts/gd/interact/work_arms.gd")
const DoroLog = preload("res://scripts/gd/utils/debug_log.gd")

const LISTEN_PORT := 47329
const PREVIEW_ARGUMENT := "--capture-input-preview"
const PREVIEW_ENVIRONMENT := "DORO_CAPTURE_INPUT_PREVIEW"
const MIN_ACTIVE_TIME := 3.0
const IDLE_TIMEOUT := 7.0
const PRESS_DURATION := 0.16
const PAW_TURN_DURATION := 0.055
# 爪子贴图切换（TURN↔PRESS）后，scale 与手臂粗细按此速率连续插值到新贴图
# 实测值，消除按下瞬间"爪子突然放大、腕口变粗"的跳变。
const VISUAL_BLEND_RATE := 34.0
# PRESS 爪腕管在贴图内自顶部向下倾斜约 6.1°（实测中心线斜率 -0.106 px/y），
# TURN 爪近似竖直（0.7°）。手臂需沿腕管轴进入，PRESS 姿态的腕口朝向要补偿
# 这一倾角，避免手臂在腕口处与贴图腕管错位。
const PRESS_TUBE_TILT_RAD := 0.106

# 过渡爪在贴图切换/复位时承担中间形态；按下/复位共享同一条腕骨插值。
const PRESS_POSE_RATE := 28.0
const RETURN_POSE_RATE := 15.0
const REST_SNAP_DISTANCE := 0.7
const REST_SNAP_ROTATION := 0.01

const KEYBOARD_IDLE_PAW_TEXTURE_PATH := "res://assets/images/input_reaction/paw_round_v3.png"
const PAW_TURN_TEXTURE_PATH := "res://assets/images/input_reaction/paw_turn_connected_v2.png"
const KEYBOARD_PRESS_PAW_TEXTURE_PATH := "res://assets/images/input_reaction/paw_press_connected_v2.png"
const MOUSE_IDLE_PAW_TEXTURE_PATH := "res://assets/images/input_reaction/paw_round_v3.png"
const MOUSE_PRESS_PAW_TEXTURE_PATH := "res://assets/images/input_reaction/paw_press_connected_v2.png"

# ---- 贴图实测数据（由素材透明像素边界测得，单位：源像素）----
# 按压爪 710x720：腕口切面在贴图顶边，中心 x=+49，外轮廓半宽 224，轮廓粗 21；
# 肉垫按压点 (-48.5, 250)。过渡爪 815x720：腕口中心 x=+4.5，外半宽 219，轮廓 21.5。
const PRESS_SOCKET_LOCAL := Vector2(49.0, -360.0)
const PRESS_CONTACT_LOCAL := Vector2(-48.5, 250.0)
const TURN_SOCKET_LOCAL := Vector2(4.5, -360.0)
# 待机圆爪 1254x1254：无开放腕口；等效腕骨点取在爪顶（与过渡爪静置骨点一致）。
const IDLE_SOCKET_LOCAL := Vector2(4.7, -389.0)
const PRESS_SOCKET_OUTER_HALF := 224.0
const TURN_SOCKET_OUTER_HALF := 219.0
const PRESS_SOCKET_OUTLINE_PX := 21.0
const TURN_SOCKET_OUTLINE_PX := 21.5

const KEYBOARD_IDLE_PAW_SCALE := Vector2(0.074, 0.074)
const KEYBOARD_TURN_PAW_SCALE := Vector2(0.078, 0.080)
const KEYBOARD_PRESS_PAW_SCALE := Vector2(0.092, 0.082)
const MOUSE_IDLE_PAW_SCALE := Vector2(0.074, 0.074)
const MOUSE_TURN_PAW_SCALE := Vector2(0.078, 0.080)
const MOUSE_PRESS_PAW_SCALE := Vector2(0.092, 0.082)

const PAW_ROTATION_MIN := deg_to_rad(-72.0)
const PAW_ROTATION_MAX := deg_to_rad(72.0)
const PAW_ROTATION_SAMPLES := 289
const PAW_ROTATION_PENALTY := 0.02

const WORK_ARM_SIDE_KEYBOARD := 0
const WORK_ARM_SIDE_MOUSE := 1
const PAW_ARM_COLOR := Color("#fcfbfb")
const PAW_ARM_OUTLINE_COLOR := Color("#150f11")
const SHOULDER_CENTER := Vector2(0, 32)
const SHOULDER_RADIUS := Vector2(165, 92)
const SHOULDER_POINT_COUNT := 48
const MOUSE_SHOULDER_ANCHOR := Vector2(-180, 27)
const KEYBOARD_SHOULDER_ANCHOR := Vector2(138, 68)
const WORK_HEAD_FOLLOW_SMOOTHING := 0.02
const WORK_HEAD_MOTION_WEIGHT := 0.24

enum PawVisual { IDLE, TURN, PRESS }

## 键盘模式的总开关（互动菜单里那一项）。
##
## 关掉之后照旧监听输入 —— 鼠标跟随和抚摸这些还要用 —— 只是不再因为敲键盘
## 而进入打字模式。所以判断放在 _register_activity 里而不是干脆不启动监听。
var _keyboard_mode_enabled: bool = true

var _udp := PacketPeerUDP.new()
var _bridge_pid := -1
var _active := false
var _active_since := 0.0
var _last_activity := 0.0
var _last_mouse_activity := -100.0
var _mouse_position := Vector2.ZERO
var _last_mouse_position := Vector2.ZERO

# 键盘爪（屏幕右，_left_paw）与鼠标爪（屏幕左，_right_paw）各自的按键栈。
var _keyboard_keys: Array[int] = []
var _keyboard_last_key := -1
var _keyboard_press_until := 0.0
var _mouse_button := 1
var _mouse_press_until := 0.0
var _mouse_buttons: Array[int] = []

var _saved_model_position := Vector2.ZERO
var _saved_model_rotation := 0.0
var _saved_model_scale := Vector2.ONE
var _saved_model_flip_h := false
var _saved_body_opacity := 1.0
var _rand_move_was_enabled := false
var _was_docked := false
var _mouse_follow: Node
var _animation_tree: AnimationTree
var _saved_head_follow_smoothing := 0.1
var _saved_head_motion_weight := 0.8

var _stage: Node2D
var _work_arms: Node2D
var _left_paw: Sprite2D
var _right_paw: Sprite2D
var _shoulder_fill: Polygon2D
var _shoulder_outline: Line2D
var _left_idle_texture: Texture2D
var _turn_texture: Texture2D
var _left_press_texture: Texture2D
var _right_idle_texture: Texture2D
var _right_press_texture: Texture2D

# 唯一腕骨状态：世界坐标腕骨点 + 腕口朝向角。贴图切换/旋转/复位全部由
# 这两个状态驱动，Sprite2D.position 按当前贴图实测腕口反算，骨点永不断开。
var _left_bone := Vector2.ZERO
var _left_rot := 0.0
var _left_rest_bone := Vector2.ZERO
var _left_visual := PawVisual.IDLE
var _left_action_active := false
var _left_phase_changed_at := -100.0
var _right_bone := Vector2.ZERO
var _right_rot := 0.0
var _right_rest_bone := Vector2.ZERO
var _right_visual := PawVisual.IDLE
var _right_action_active := false
var _right_phase_changed_at := -100.0

# 爪子当前显示缩放（每帧向目标贴图实测缩放插值）；贴图可瞬时切换，但
# scale 连续，保证腕口粗度/手臂粗细随爪子平滑过渡，不会突然跳变。
var _left_scale := KEYBOARD_IDLE_PAW_SCALE
var _right_scale := MOUSE_IDLE_PAW_SCALE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 70
	_mouse_follow = model.get_node_or_null("Animation/EffectMouseFollow")
	_animation_tree = model.get_node_or_null("Animation/AnimationTree") as AnimationTree
	_create_visuals()
	if (
		PREVIEW_ARGUMENT in OS.get_cmdline_user_args()
		or OS.get_environment(PREVIEW_ENVIRONMENT) == "1"
	):
		# 开发工具，按需加载：见 scripts/gd/dev/input_preview_capture.gd
		call_deferred("_run_dev_preview_capture")
	else:
		_start_listener()


func _exit_tree() -> void:
	_udp.close()
	if _bridge_pid > 0:
		OS.kill(_bridge_pid)


func _process(delta: float) -> void:
	_read_packets()
	var now := _now()
	if not _active:
		return

	_lock_work_mode_facing_left()
	if move_effect.is_moving:
		move_effect.stop()
	# 拖到屏幕边缘停靠时，键盘/手/桌子这些打字视觉件也要跟着身体一起躲起来，
	# 与普通模式保持一致的"拖到边缘就躲起来"逻辑（键盘模式 / 普通模式统一）。
	if window.docking != _was_docked:
		_was_docked = window.docking
		if window.docking:
			_set_visuals_visible(false)
		else:
			_apply_work_pose()
			_set_visuals_visible(true)
	_update_paws(now, delta)
	if now - _last_activity >= IDLE_TIMEOUT and now - _active_since >= MIN_ACTIVE_TIME:
		_deactivate_work_mode()


func _create_visuals() -> void:
	_left_idle_texture = _load_png_texture(KEYBOARD_IDLE_PAW_TEXTURE_PATH)
	_turn_texture = _load_png_texture(PAW_TURN_TEXTURE_PATH)
	_left_press_texture = _load_png_texture(KEYBOARD_PRESS_PAW_TEXTURE_PATH)
	_right_idle_texture = _load_png_texture(MOUSE_IDLE_PAW_TEXTURE_PATH)
	_right_press_texture = _load_png_texture(MOUSE_PRESS_PAW_TEXTURE_PATH)
	_create_shoulder_backdrop()

	_stage = InputStageScript.new()
	_stage.name = "DeskKeyboardMouse"
	_stage.z_index = 0
	add_child(_stage)

	_work_arms = WorkArmsScript.new()
	_work_arms.name = "WorkArms"
	add_child(_work_arms)

	_left_rest_bone = _rest_bone_for(
		_stage.get_keyboard_idle_center(),
		KEYBOARD_TURN_PAW_SCALE
	)
	_right_rest_bone = _rest_bone_for(
		_stage.get_mouse_idle_center(),
		MOUSE_TURN_PAW_SCALE
	)
	_left_bone = _left_rest_bone
	_right_bone = _right_rest_bone

	_left_paw = Sprite2D.new()
	_left_paw.name = "KeyboardPaw"
	_left_paw.texture = _left_idle_texture
	_left_paw.scale = KEYBOARD_IDLE_PAW_SCALE
	_left_paw.z_index = 2
	add_child(_left_paw)
	_place_paw(_left_paw, PawVisual.IDLE, _left_bone, _left_rot)

	_right_paw = Sprite2D.new()
	_right_paw.name = "MousePaw"
	_right_paw.texture = _right_idle_texture
	_right_paw.scale = MOUSE_IDLE_PAW_SCALE
	_right_paw.z_index = 2
	add_child(_right_paw)
	_place_paw(_right_paw, PawVisual.IDLE, _right_bone, _right_rot)

	_work_arms.update_arms(
		KEYBOARD_SHOULDER_ANCHOR,
		_left_bone,
		MOUSE_SHOULDER_ANCHOR,
		_right_bone,
		false,
		false
	)

	_set_visuals_visible(false)


func _start_listener() -> void:
	var bind_error := _udp.bind(LISTEN_PORT, "127.0.0.1")
	if bind_error != OK:
		push_warning("Doro input listener could not bind UDP port %d: %s" % [LISTEN_PORT, error_string(bind_error)])
		return

	var bridge_path := OS.get_executable_path().get_base_dir().path_join("DoroInputBridge.exe")
	if not FileAccess.file_exists(bridge_path):
		var source_path := ProjectSettings.globalize_path("res://helpers/DoroInputBridge.exe")
		if FileAccess.file_exists(source_path):
			bridge_path = source_path
		else:
			push_warning("DoroInputBridge.exe was not found; global input reactions are disabled.")
			return

	_bridge_pid = OS.create_process(
		bridge_path,
		PackedStringArray(["--port", str(LISTEN_PORT), "--parent", str(OS.get_process_id())]),
		false
	)
	if _bridge_pid <= 0:
		push_warning("Doro input listener failed to start.")


func _read_packets() -> void:
	while _udp.get_available_packet_count() > 0:
		var packet := _udp.get_packet().get_string_from_ascii()
		# 只认本机发来的包。socket 本身绑在 127.0.0.1 上，理论上收不到外部流量，
		# 但收下什么就照着动爪子这件事不该只靠绑定地址兜着 —— 多这一行几乎没有成本。
		if _udp.get_packet_ip() != "127.0.0.1":
			continue
		var parts := packet.split("|")
		if parts.is_empty():
			continue

		match parts[0]:
			"KD":
				if parts.size() >= 2:
					_on_key_down(parts[1].to_int())
			"KU":
				if parts.size() >= 2:
					_on_key_up(parts[1].to_int())
			"MD":
				if parts.size() >= 2:
					_on_mouse_down(parts[1].to_int())
			"MU":
				if parts.size() >= 2:
					_on_mouse_up(parts[1].to_int())
			"MM":
				if parts.size() >= 3:
					_on_mouse_move(Vector2(parts[1].to_float(), parts[2].to_float()))


func _on_key_down(virtual_key: int) -> void:
	_register_activity(false)
	var key: int = _stage.normalize_vk(virtual_key)
	if not _stage.has_key(key):
		return

	_stage.press_key(key)
	_keyboard_keys.erase(key)
	_keyboard_keys.append(key)
	_keyboard_last_key = key
	_keyboard_press_until = _now() + PRESS_DURATION


func _on_key_up(virtual_key: int) -> void:
	_register_activity(false)
	var key: int = _stage.normalize_vk(virtual_key)
	_stage.release_key(key)
	_keyboard_keys.erase(key)


func _on_mouse_down(button: int) -> void:
	_register_activity(true)
	if button != 1 and button != 2:
		return
	_mouse_button = button
	_mouse_buttons.erase(button)
	_mouse_buttons.append(button)
	_mouse_press_until = _now() + PRESS_DURATION
	_stage.press_mouse(button)


func _on_mouse_up(button: int) -> void:
	_register_activity(true)
	if button != 1 and button != 2:
		return
	_mouse_buttons.erase(button)
	if not _mouse_buttons.is_empty():
		_mouse_button = _mouse_buttons.back()
	_stage.release_mouse(button)


func _on_mouse_move(position: Vector2) -> void:
	_mouse_position = position
	if _last_mouse_position == Vector2.ZERO:
		_last_mouse_position = position
		return

	if position.distance_to(_last_mouse_position) >= 2.0:
		_register_activity(true)
	_last_mouse_position = position


## 记录一次输入活动。仅键盘活动（mouse_activity == false）会触发打字模式；
## 鼠标移动/按压只刷新活动时间戳（保持打字模式存活、供鼠标爪按压跟随），
## 不会独自把桌宠拽进打字模式。
func _register_activity(mouse_activity: bool) -> void:
	var now := _now()
	_last_activity = now
	if mouse_activity:
		_last_mouse_activity = now
	# 拖到屏幕边缘停靠（躲起来）时，按键盘不再触发打字模式：桌宠已藏起，
	# 必须等用户主动把她拖离边缘后才能再次进入键盘模式。
	#
	# 另外，往桌宠自己的输入框里打字时也不进：这个模式表达的是「你在别的软件里干活，
	# 我在旁边陪着」，对着她说话时进入它语义上就是错的。而且打字模式那套桌面图
	# z_index 是 70、盖在 GUI（z_index 0）之上，会把聊天栏压住。
	if not _keyboard_mode_enabled:
		return
	if not _active and not mouse_activity and not window.docking and not _own_text_field_focused():
		DoroLog.d("[DORO] work-mode TRIGGER by keyboard t=%d" % Time.get_ticks_msec())
		_activate_work_mode()


## 桌宠自己的界面里是否有文本框正在接收输入（聊天输入框、设置里的各个输入框）。
## 用焦点所有者判断而不是单独盯聊天栏，这样任何文本框都自动覆盖到。
func _own_text_field_focused() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit


func _activate_work_mode() -> void:
	DoroLog.d("[DORO] _activate_work_mode rand_move_was=%s is_moving=%s t=%d" % [str(rand_move.enable), str(move_effect.is_moving), Time.get_ticks_msec()])
	_active = true
	_active_since = _now()
	_last_activity = _active_since

	_saved_model_position = model.position
	_saved_model_rotation = model.rotation
	_saved_model_scale = model.scale
	_saved_model_flip_h = model.flip_h
	_saved_body_opacity = model.Body_group
	_rand_move_was_enabled = rand_move.enable
	if _mouse_follow:
		_saved_head_follow_smoothing = float(_mouse_follow.get("smooth_factor"))
		_mouse_follow.set("smooth_factor", WORK_HEAD_FOLLOW_SMOOTHING)
	if _animation_tree:
		_saved_head_motion_weight = float(
			_animation_tree.get("parameters/HeadAdd/add_amount")
		)
		_animation_tree.set(
			"parameters/HeadAdd/add_amount",
			WORK_HEAD_MOTION_WEIGHT
		)

	window.input_mode_active = true
	# 不再在此处强制 dragging = false：打字模式会在点击宠物拖动窗口的那一刻
	# 激活（拖动按下即触发鼠标活动），若把它重置，刚开始的拖动会立即失效，
	# 用户就再也无法在打字时把挡屏的桌宠拖走。
	rand_move.enable = false
	if move_effect.is_moving:
		move_effect.stop()

	_apply_work_pose()
	_set_visuals_visible(not window.docking)
	_was_docked = window.docking


func _deactivate_work_mode() -> void:
	DoroLog.d("[DORO] _deactivate_work_mode rand_move_was=%s t=%d" % [str(_rand_move_was_enabled), Time.get_ticks_msec()])
	_active = false
	_set_visuals_visible(false)

	model.position = _saved_model_position
	model.rotation = _saved_model_rotation
	model.flip_h = _saved_model_flip_h
	model.scale = _saved_model_scale
	model.Body_group = _saved_body_opacity
	if _mouse_follow:
		_mouse_follow.set("smooth_factor", _saved_head_follow_smoothing)
	if _animation_tree:
		_animation_tree.set(
			"parameters/HeadAdd/add_amount",
			_saved_head_motion_weight
		)

	window.input_mode_active = false
	rand_move.enable = _rand_move_was_enabled


## 打字模式下锁定朝左。
##
## 原来这里把 scale 直接写成 Vector2(0.30, 0.30) —— 那个数字恰好等于场景里模型的
## 缩放，所以一直没出问题，但它把「翻转回来」和「重设大小」两件事混在了一起：
## 一旦有人在场景里调整模型大小，进打字模式就会被悄悄拉回 0.30。
## 现在只取绝对值消掉翻转，不碰实际大小。
func _lock_work_mode_facing_left() -> void:
	if model.flip_h or model.scale.x < 0.0 or model.scale.y < 0.0:
		model.flip_h = false
		model.scale = Vector2(absf(model.scale.x), absf(model.scale.y))


## 打字模仿时的基准姿态（桌面位 + 朝左 + 打字身体组）。激活工作模式和
## 从屏幕边缘停靠恢复时复用，保证两处姿态一致。
func _apply_work_pose() -> void:
	model.position = Vector2(22, -25)
	model.rotation = 0.0
	_lock_work_mode_facing_left()
	model.Body_group = 0.0


## 每帧：先推进两只爪子的腕骨状态（位置 + 朝向），再按当前贴图反算精灵
## 位置，最后把腕骨参数交给手臂渲染器。全程同一套规则，无按键特例。
func _update_paws(now: float, delta: float) -> void:
	var keyboard_key := _current_or_recent_key(
		_keyboard_keys,
		_keyboard_last_key,
		_keyboard_press_until,
		now
	)
	var keyboard_pressed := keyboard_key >= 0
	var mouse_paw_pressed := not _mouse_buttons.is_empty() or now < _mouse_press_until

	if keyboard_pressed != _left_action_active:
		_left_action_active = keyboard_pressed
		_left_phase_changed_at = now
	if mouse_paw_pressed != _right_action_active:
		_right_action_active = mouse_paw_pressed
		_right_phase_changed_at = now

	# ---- 键盘爪腕骨 ----
	var left_target_bone := _left_rest_bone
	var left_target_rot := 0.0
	var left_rate := RETURN_POSE_RATE
	if keyboard_pressed:
		var contact: Vector2 = _stage.get_key_center(keyboard_key)
		var root: Vector2 = _work_arms.get_arm_root(KEYBOARD_SHOULDER_ANCHOR, contact)
		var pose := _solve_press_pose(contact, root, KEYBOARD_PRESS_PAW_SCALE)
		left_target_bone = pose[0]
		left_target_rot = pose[1]
		left_rate = PRESS_POSE_RATE
	var left_blend := 1.0 - exp(-left_rate * delta)
	_left_bone = _left_bone.lerp(left_target_bone, left_blend)
	_left_rot = lerp_angle(_left_rot, left_target_rot, left_blend)
	var left_at_rest := (
		not keyboard_pressed
		and _left_bone.distance_to(_left_rest_bone) <= REST_SNAP_DISTANCE
		and absf(_left_rot) <= REST_SNAP_ROTATION
	)
	# 手臂是否已完全收回（腕骨没入桌沿后沿，不再绘制手臂）：此时爪子必须立即
	# 切回无腕口的待机圆爪贴图，让圆爪滑入待机位，避免"空腕口"过渡爪悬在桌沿。
	var left_arm_root: Vector2 = _work_arms.get_arm_root(KEYBOARD_SHOULDER_ANCHOR, _left_bone)
	var left_arm_retracted: bool = _work_arms.is_wrist_retracted(left_arm_root, _left_bone)
	if left_at_rest:
		_left_bone = _left_rest_bone
		_left_rot = 0.0

	if keyboard_pressed and now - _left_phase_changed_at >= PAW_TURN_DURATION:
		_left_visual = PawVisual.PRESS
	elif left_at_rest or left_arm_retracted:
		_left_visual = PawVisual.IDLE
	else:
		_left_visual = PawVisual.TURN
	var left_scale_target := _scale_for_visual(_left_visual, true)
	_left_scale = _left_scale.lerp(
		left_scale_target,
		1.0 - exp(-VISUAL_BLEND_RATE * delta)
	)
	_apply_paw_visual(_left_paw, _left_visual, true)

	# ---- 鼠标爪腕骨 ----
	var right_target_bone := _right_rest_bone
	var right_target_rot := 0.0
	var right_rate := RETURN_POSE_RATE
	if mouse_paw_pressed:
		var contact: Vector2 = _stage.get_mouse_button_center(_mouse_button)
		var root: Vector2 = _work_arms.get_arm_root(MOUSE_SHOULDER_ANCHOR, contact)
		var pose := _solve_press_pose(contact, root, MOUSE_PRESS_PAW_SCALE)
		right_target_bone = pose[0]
		right_target_rot = pose[1]
		right_rate = PRESS_POSE_RATE
	var right_blend := 1.0 - exp(-right_rate * delta)
	_right_bone = _right_bone.lerp(right_target_bone, right_blend)
	_right_rot = lerp_angle(_right_rot, right_target_rot, right_blend)
	var right_at_rest := (
		not mouse_paw_pressed
		and _right_bone.distance_to(_right_rest_bone) <= REST_SNAP_DISTANCE
		and absf(_right_rot) <= REST_SNAP_ROTATION
	)
	# 与左爪同理：手臂一收回（腕骨没入桌沿），立即切回无腕口的圆爪待机贴图。
	var right_arm_root: Vector2 = _work_arms.get_arm_root(MOUSE_SHOULDER_ANCHOR, _right_bone)
	var right_arm_retracted: bool = _work_arms.is_wrist_retracted(right_arm_root, _right_bone)
	if right_at_rest:
		_right_bone = _right_rest_bone
		_right_rot = 0.0

	if mouse_paw_pressed and now - _right_phase_changed_at >= PAW_TURN_DURATION:
		_right_visual = PawVisual.PRESS
	elif right_at_rest or right_arm_retracted:
		_right_visual = PawVisual.IDLE
	else:
		_right_visual = PawVisual.TURN
	var right_scale_target := _scale_for_visual(_right_visual, false)
	_right_scale = _right_scale.lerp(
		right_scale_target,
		1.0 - exp(-VISUAL_BLEND_RATE * delta)
	)
	_apply_paw_visual(_right_paw, _right_visual, false)

	# ---- 手臂：中心线终点与末端切线完全由腕骨决定 ----
	var left_arm := _arm_metrics(_left_visual, true)
	var right_arm := _arm_metrics(_right_visual, false)
	_work_arms.update_arms(
		_work_arms.get_arm_root(KEYBOARD_SHOULDER_ANCHOR, _left_bone),
		_left_bone,
		_work_arms.get_arm_root(MOUSE_SHOULDER_ANCHOR, _right_bone),
		_right_bone,
		not left_at_rest,
		not right_at_rest,
		left_arm[0],
		right_arm[0],
		_arm_outward(_left_visual, _left_rot, _left_scale.x, true),
		_arm_outward(_right_visual, _right_rot, _right_scale.x, false),
		left_arm[1],
		right_arm[1]
	)


## 由目标按压点（键帽中心）反解腕骨位置与腕口朝向：贴图肉垫按压点精确
## 落在按键中心，腕口朝向尽量指向手臂根部，附带轻微回正偏好。
func _solve_press_pose(contact: Vector2, root: Vector2, press_scale: Vector2) -> Array:
	var contact_scaled := Vector2(
		PRESS_CONTACT_LOCAL.x * press_scale.x,
		PRESS_CONTACT_LOCAL.y * press_scale.y
	)
	var socket_scaled := Vector2(
		PRESS_SOCKET_LOCAL.x * press_scale.x,
		PRESS_SOCKET_LOCAL.y * press_scale.y
	)
	var contact_offset := contact_scaled - socket_scaled
	var best_rotation := 0.0
	var best_score := INF
	for index in range(PAW_ROTATION_SAMPLES):
		var amount := float(index) / float(PAW_ROTATION_SAMPLES - 1)
		var candidate := lerpf(PAW_ROTATION_MIN, PAW_ROTATION_MAX, amount)
		var bone := contact - contact_offset.rotated(candidate)
		var to_root: Vector2 = root - bone
		if to_root.length_squared() < 1.0:
			continue
		var angular_error := absf(
			Vector2.UP.rotated(candidate).angle_to(to_root.normalized())
		)
		var score := angular_error + absf(candidate) * PAW_ROTATION_PENALTY
		if score < best_score:
			best_score = score
			best_rotation = candidate
	return [contact - contact_offset.rotated(best_rotation), best_rotation]


## 静置腕骨点：待机爪中心 + 过渡爪腕口缩放偏移。此时骨点位于桌沿后沿
## 之后，手臂求解器自然收缩为零长，无需单独的隐藏阈值。
func _rest_bone_for(idle_center: Vector2, turn_scale: Vector2) -> Vector2:
	return idle_center + Vector2(
		TURN_SOCKET_LOCAL.x * turn_scale.x,
		TURN_SOCKET_LOCAL.y * turn_scale.y
	)


func _set_paw_texture(paw: Sprite2D, texture: Texture2D, scale: Vector2) -> void:
	if paw.texture != texture:
		paw.texture = texture
	if not paw.scale.is_equal_approx(scale):
		paw.scale = scale


## 按腕骨状态与当前贴图的实测腕口反算精灵位置；切换贴图只换贴图与缩放，
## 骨点不动，因此不会产生瞬移。
func _place_paw(
	paw: Sprite2D,
	visual: int,
	bone: Vector2,
	bone_rot: float
) -> void:
	var socket_local := IDLE_SOCKET_LOCAL
	match visual:
		PawVisual.TURN:
			socket_local = TURN_SOCKET_LOCAL
		PawVisual.PRESS:
			socket_local = PRESS_SOCKET_LOCAL
	var scaled_socket := Vector2(
		socket_local.x * paw.scale.x,
		socket_local.y * paw.scale.y
	)
	paw.rotation = bone_rot
	paw.position = bone - scaled_socket.rotated(bone_rot)


func _apply_paw_visual(paw: Sprite2D, visual: int, keyboard_side: bool) -> void:
	var scale := _left_scale if keyboard_side else _right_scale
	match visual:
		PawVisual.IDLE:
			_set_paw_texture(
				paw,
				_left_idle_texture if keyboard_side else _right_idle_texture,
				scale
			)
		PawVisual.TURN:
			_set_paw_texture(
				paw,
				_turn_texture,
				scale
			)
		PawVisual.PRESS:
			_set_paw_texture(
				paw,
				_left_press_texture if keyboard_side else _right_press_texture,
				scale
			)
	var bone := _left_bone if keyboard_side else _right_bone
	var bone_rot := _left_rot if keyboard_side else _right_rot
	_place_paw(paw, visual, bone, bone_rot)


## 当前贴图对应的腕口外半宽与轮廓粗（世界像素，按爪子当前显示缩放缩放），
## 手臂与贴图腕管在切面处等宽、轮廓等粗，拼接处无台阶。
func _arm_metrics(visual: int, keyboard_side: bool) -> Array:
	var scale := _left_scale if keyboard_side else _right_scale
	match visual:
		PawVisual.PRESS:
			return [PRESS_SOCKET_OUTER_HALF * scale.x, PRESS_SOCKET_OUTLINE_PX * scale.x]
		PawVisual.TURN:
			return [TURN_SOCKET_OUTER_HALF * scale.x, TURN_SOCKET_OUTLINE_PX * scale.x]
		_:
			return [TURN_SOCKET_OUTER_HALF * scale.x, TURN_SOCKET_OUTLINE_PX * scale.x]


## 爪子目标显示缩放（贴图切换的目标值，实际显示值由 _left_scale/_right_scale
## 每帧向该值插值）。
func _scale_for_visual(visual: int, keyboard_side: bool) -> Vector2:
	match visual:
		PawVisual.PRESS:
			return KEYBOARD_PRESS_PAW_SCALE if keyboard_side else MOUSE_PRESS_PAW_SCALE
		PawVisual.TURN:
			return KEYBOARD_TURN_PAW_SCALE if keyboard_side else MOUSE_TURN_PAW_SCALE
		_:
			return KEYBOARD_IDLE_PAW_SCALE if keyboard_side else MOUSE_IDLE_PAW_SCALE


## 腕口朝向外侧方向：PRESS 爪腕管在贴图内有实测倾角，需叠加补偿使手臂沿
## 腕管轴进入；倾角随爪子缩放进度渐入，避免 TURN→PRESS 时朝向瞬间跳变。
## TURN/IDLE 爪腕管近似竖直，无需补偿。
func _arm_outward(visual: int, bone_rot: float, display_scale_x: float, keyboard_side: bool) -> Vector2:
	if visual != PawVisual.PRESS:
		return Vector2.UP.rotated(bone_rot)
	var turn_scale := KEYBOARD_TURN_PAW_SCALE if keyboard_side else MOUSE_TURN_PAW_SCALE
	var press_scale := KEYBOARD_PRESS_PAW_SCALE if keyboard_side else MOUSE_PRESS_PAW_SCALE
	var progress := clampf(
		(display_scale_x - turn_scale.x) / (press_scale.x - turn_scale.x),
		0.0,
		1.0
	)
	return Vector2.UP.rotated(bone_rot + PRESS_TUBE_TILT_RAD * progress)


func _create_shoulder_backdrop() -> void:
	var shoulder_points := PackedVector2Array()
	for index in range(SHOULDER_POINT_COUNT):
		var angle := TAU * float(index) / float(SHOULDER_POINT_COUNT)
		shoulder_points.append(
			SHOULDER_CENTER
			+ Vector2(cos(angle) * SHOULDER_RADIUS.x, sin(angle) * SHOULDER_RADIUS.y)
		)

	_shoulder_fill = Polygon2D.new()
	_shoulder_fill.name = "ShoulderBackdrop"
	_shoulder_fill.polygon = shoulder_points
	_shoulder_fill.color = PAW_ARM_COLOR
	_shoulder_fill.z_as_relative = false
	_shoulder_fill.z_index = -4
	add_child(_shoulder_fill)

	# Only outline the upper shoulder arc. The desk hides the lower body, so a
	# closed ellipse would leave a second contour crossing through the desk edge.
	var outline_points := PackedVector2Array()
	var shoulder_arc_steps := int(SHOULDER_POINT_COUNT / 2)
	for index in range(shoulder_arc_steps + 1):
		var angle := PI + PI * float(index) / float(shoulder_arc_steps)
		outline_points.append(
			SHOULDER_CENTER
			+ Vector2(cos(angle) * SHOULDER_RADIUS.x, sin(angle) * SHOULDER_RADIUS.y)
		)
	_shoulder_outline = Line2D.new()
	_shoulder_outline.name = "ShoulderBackdropOutline"
	_shoulder_outline.points = outline_points
	_shoulder_outline.width = 4.0
	_shoulder_outline.default_color = PAW_ARM_OUTLINE_COLOR
	_shoulder_outline.antialiased = true
	_shoulder_outline.z_as_relative = false
	_shoulder_outline.z_index = -3
	add_child(_shoulder_outline)


func _current_or_recent_key(
	stack: Array[int],
	last_key: int,
	press_until: float,
	now: float
) -> int:
	if not stack.is_empty():
		return stack.back()
	if now < press_until:
		return last_key
	return -1


func _set_visuals_visible(value: bool) -> void:
	_stage.visible = value
	_work_arms.visible = value
	_shoulder_fill.visible = value
	_shoulder_outline.visible = value
	_left_paw.visible = value
	_right_paw.visible = value


func _load_png_texture(path: String) -> Texture2D:
	# 用资源加载系统（而非 FileAccess 直读 PNG）：
	# 导出版下 pck 内资源是导入后的格式（.ctex），FileAccess.open 源码 PNG 会失败，
	# ResourceLoader 会自动解析 .import 映射，编辑器与导出版均可用。
	var texture := ResourceLoader.load(path) as Texture2D
	if texture == null:
		push_error("Failed to load input-reaction asset: %s" % path)
		return ImageTexture.new()
	return texture


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## 开发用截图流程的入口。实现放在单独文件里，只有真的带了参数才去加载它。
func _run_dev_preview_capture() -> void:
	var script = load("res://scripts/gd/dev/input_preview_capture.gd")
	if script == null:
		push_error("找不到开发用的截图脚本")
		return
	await script.run(self)


## 由互动菜单里的「键盘模式」开关调用。
##
## 关掉时如果她正处在打字模式，立刻退出 —— 不能等那 7 秒空闲超时，
## 否则用户会以为开关点了没用。
func set_keyboard_mode_enabled(value: bool) -> void:
	_keyboard_mode_enabled = value
	if not value and _active:
		DoroLog.d("[DORO] 键盘模式被关掉，立刻退出打字模式 t=%d" % Time.get_ticks_msec())
		_deactivate_work_mode()
