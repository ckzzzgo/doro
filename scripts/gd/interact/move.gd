extends Node
class_name MoveEffect

@export var enable: bool = true
@export var window: Node2D
@export var model: GDCubismUserModel
@export var anim_controller: AnimationController
@export var rand_move: Node

@export var speed:float = 250

var is_moving: bool = false
var move_tween: Tween
var ok_to_move: bool
var move_lock : bool = false  # 移动锁，结点持有该锁，运动将被优先执行
	
func _process(delta: float) -> void:
	var prev_ok := ok_to_move
	ok_to_move = enable and not window.dragging and not window.input_mode_active and (not window.docking or move_lock)
	if ok_to_move != prev_ok:
		print("[DORO] ok_to_move %s->%s (enable=%s drag=%s input_mode=%s docking=%s lock=%s t=%d)" % [str(prev_ok), str(ok_to_move), str(enable), str(window.dragging), str(window.input_mode_active), str(window.docking), str(move_lock), Time.get_ticks_msec()])
	if !ok_to_move:
		stop()
	
func move(target_pos: Vector2i, override: bool = false, pre_call: Callable = Callable(), post_call: Callable = Callable()):
	# 直接读当前状态，避免依赖上一帧缓存的 ok_to_move：打字模式/拖拽在同一帧内
	# 刚生效时（move._process 先于 InputReaction._process 运行），随机移动计时器
	# 可能趁隙在 ok_to_move 尚未重算前触发 Run + 位移。这里做即时兜底。
	if window.input_mode_active or window.dragging:
		print("[DORO] move DENIED(fresh) input_mode=%s drag=%s t=%d" % [str(window.input_mode_active), str(window.dragging), Time.get_ticks_msec()])
		return
	if not ok_to_move:
		print("[DORO] move DENIED target=%s override=%s (drag=%s input_mode=%s docking=%s t=%d)" % [str(target_pos), str(override), str(window.dragging), str(window.input_mode_active), str(window.docking), Time.get_ticks_msec()])
		return

	if override and not move_lock:
		stop()
		move_lock = true
		anim_controller.idle()
		if rand_move.enable:
			rand_move.timer.set_paused(false)
	elif is_moving:
		print("[DORO] move SKIP already-moving target=%s t=%d" % [str(target_pos), Time.get_ticks_msec()])
		return

	is_moving = true
	print("[DORO] move START target=%s override=%s t=%d" % [str(target_pos), str(override), Time.get_ticks_msec()])
	_clear_tween()

	var direction = _get_movement_direction(target_pos)
	var duration = get_tree().root.get_window().position.distance_to(target_pos) / speed

	move_tween = create_tween()
	_on_movement_started(direction)

	if pre_call.is_valid():
		pre_call.call()
		print("[DORO] move pre_call invoked t=%d" % Time.get_ticks_msec())

	move_tween.tween_property(get_tree().root.get_window(), "position", target_pos, duration)
	move_tween.finished.connect(_on_movement_finished.bind(post_call))

func stop():
	# 未在移动时（例如打字模式 / 拖拽期间 ok_to_move 恒为 false，_process 每帧都会
	# 调到这里）直接返回，避免每帧重复调用 _on_movement_finished 刷日志。
	if not is_moving:
		return
	print("[DORO] move STOP interrupt t=%d" % Time.get_ticks_msec())
	_clear_tween()
	_on_movement_finished()
	# 移动被中断（拖拽 / 停靠 / 进入打字模式 / 随机移动被禁用）：立即恢复
	# 待机动画并解挂随机移动计时器，否则 DORO 会保持"跑步"动画却停在原地不动。
	if anim_controller:
		anim_controller.idle()
	if rand_move and rand_move.enable:
		rand_move.timer.set_paused(false)

func _get_movement_direction(target_pos: Vector2) -> bool:
	var current_pos = get_tree().root.get_window().position
	return target_pos.x > current_pos.x
		
func _on_movement_finished(post_call: Callable = Callable()):
	print("[DORO] move FINISH t=%d" % Time.get_ticks_msec())
	is_moving = false
	
	if move_lock:
		move_lock = false
	
	if post_call.is_valid():
		post_call.call()

func _on_movement_started(direction):
	print("[DORO] move STARTED dir=%s t=%d" % [str(direction), Time.get_ticks_msec()])
	model.flip_h = direction
	
func _clear_tween():
	if move_tween and move_tween.is_valid():
		move_tween.kill()
