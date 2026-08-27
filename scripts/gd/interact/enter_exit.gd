extends Node

## 入场 / 退场：从屏幕边缘跑进来、跑出去。
##
## 故意不用 class_name，跟 debug_log.gd 同一个理由：全局类名要靠扫描才会写进
## global_script_class_cache.cfg，而本项目是纯命令行 --headless --export-release
## 打包的，漏扫一次引用它的脚本会整批解析失败。调用方用 preload 拿。
##
## 三个地方共用同一套动作，行为一致：
##   启动          window.gd 在 _ready 末尾把窗口挪到屏幕外，再跑进来
##   退出          托盘 / 工具栏的「退出」，跑出去之后才真正 quit
##   别的程序全屏  tray.gd 收到 other_app_fullscreen，跑出去之后才隐藏
##
## 复用的是她本来就有的跑步动作（AnimationController.run()，随机走动用的也是它），
## 所以看上去跟她平时跑动是同一件事，不是新长出来的一段演出。

const DoroLog = preload("res://scripts/gd/utils/debug_log.gd")

## 跑步速度（像素/秒）。平时随机走动是 250 —— 那个速度跑到屏幕外，在宽屏上要五秒
## 多，点了「退出」还要等五秒是不能接受的。
##
## 速度恒定，时长由距离算出来：屏幕中间出发约 1.4 秒，靠边出发就快一些。
## 试过反过来做（固定 1 秒、距离不够就把起点往屏幕外推），结果是那 1 秒里有小半秒
## 她还在屏幕外面看不见；退出时更明显 —— 人早跑没了，进程还要再等半秒才关，像卡住。
const RUN_SPEED := 700.0
## 防瞬移的下限。她已经贴着边缘时真实行程只有几十像素，不兜一下就是「啪」地一闪。
const MIN_DURATION := 0.35
## 上限。宽屏最远端出发会超过 2 秒，超了就提速压回来（最快约 1000 px/s）。
const MAX_DURATION := 2.0
## 目标点再往屏幕外多推一点，确保整个窗口连边都不剩。
const OFFSCREEN_MARGIN := 40

@export var window: Node2D
@export var model: GDCubismUserModel
@export var anim_controller: AnimationController
@export var move_effect: MoveEffect
@export var rand_move: Node

var _tween: Tween
var _playing := false
## 退场前的位置，入场要跑回这儿。
var _rest_pos := Vector2i.ZERO
var _has_rest := false


func _ready() -> void:
	# 全屏隐藏那条路会 get_tree().paused = true。树一暂停 Tween 就不走了 ——
	# 退场动画必须在暂停**之前**跑完（靠回调保证），而入场是在解除暂停之后跑的。
	# 即便如此这里也设成 ALWAYS：别的地方（比如设置窗口）要是哪天也暂停树，
	# 这段动画不该跟着卡死在半路。
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_playing() -> bool:
	return _playing


## 跑出屏幕外。跑完才调 after —— 退出、隐藏都得等它，不然人还没跑出去画面就没了。
func run_out(after := Callable()) -> void:
	var root := get_tree().root
	# 人根本不在画面上（已经手动隐藏、或别的程序全屏把她藏了）时没有可演的，
	# 直接办正事。不然在隐藏状态下点「退出」还要空等一段动画，而画面上什么都没发生
	# —— 实测那次距离是 0，白白等 0.35 秒。
	if window and not window.visible:
		DoroLog.d("[DORO] enter_exit 已隐藏，跳过退场 t=%d" % Time.get_ticks_msec())
		if after.is_valid():
			after.call()
		return
	# 正在播的时候不是忽略，而是掉头。别的程序刚全屏、马上又退出全屏，两个方向会在
	# 一两秒内先后到达；忽略掉后一个，她就永远停在屏幕外回不来了。
	#
	# 但「家」的坐标不能重记：此刻她可能正跑在半路，甚至已经在屏幕外，把那个位置
	# 记成家，下次入场就跑到屏幕外去了。只有从家里出发时才记。
	if not _playing:
		_rest_pos = root.position
		_has_rest = true
	_play(_offscreen_target(root.position, root.size), after)


## 从屏幕外跑回来。rest 不给就用上次 run_out 记下的位置。
func run_in(rest := Vector2i.ZERO, after := Callable()) -> void:
	var root := get_tree().root
	var target := rest
	if target == Vector2i.ZERO:
		target = _rest_pos if _has_rest else root.position
	# 只有「她本来就不在场上」才需要先瞬移到屏幕外。正跑到一半被叫回来的话，从当前
	# 位置直接掉头就行 —— 瞬移会让她凭空跳一下。
	#
	# 瞬移和启动 Tween 在同一帧里做完，所以不会出现「先在终点闪一下再跑」的帧。
	if not _playing:
		root.position = _offscreen_target(target, root.size)
	_rest_pos = target
	_has_rest = true
	_play(target, after)


## 从 pos 出发，就近选左右边缘，算出「完全跑出屏幕」的落点。
##
## 只走横向。竖直方向跑配上这个侧面视角的跑步动作会很怪 —— 她是在地上跑，不是在飞。
func _offscreen_target(pos: Vector2i, size: Vector2i) -> Vector2i:
	var rect := DisplayServer.screen_get_usable_rect(
		DisplayServer.window_get_current_screen())
	var to_left := pos.x + size.x - rect.position.x
	var to_right := rect.end.x - pos.x
	var target_x := rect.position.x - size.x - OFFSCREEN_MARGIN if to_left <= to_right \
		else rect.end.x + OFFSCREEN_MARGIN
	return Vector2i(target_x, pos.y)


func _play(target: Vector2i, after: Callable) -> void:
	var root := get_tree().root
	var from := root.position
	var dist := Vector2(from).distance_to(Vector2(target))
	var duration := clampf(dist / RUN_SPEED, MIN_DURATION, MAX_DURATION)

	# 掉头时把上一个 Tween 连同它的 finished 回调一起丢掉。那个回调可能是
	# 「隐藏窗口 + 暂停整棵树」，要是让它在掉头之后才执行，她就被藏在半路上了。
	if _tween and _tween.is_valid():
		_tween.kill()
	_playing = true

	# 打字模式下她坐在桌前，桌子、键盘、爪子、手臂都是 InputReaction 画的独立部件，
	# 跟着窗口一起跑出去就成了「她扛着桌子跑」。先退出打字模式，恢复成平时的样子再跑。
	#
	# 不能只是把那些部件藏了：打字模式还改了她的位置、旋转、朝向和身体透明度，
	# 光藏部件她会保持着趴在桌前的姿势跑。_deactivate_work_mode 会把这些一起复原，
	# 也正是打字停顿超时后走的那条路。
	#
	# 拖到边缘停靠时本来也是这么处理的（input_reaction._process 里那段 docking 判定），
	# 这里同一个道理。
	#
	# 这一步必须排在下面「按住随机走动」之前：_deactivate_work_mode 结尾会把
	# rand_move.enable 恢复成进打字模式前的值，而那个 setter 会顺手把计时器解除暂停。
	# 顺序反了就等于刚按住又被放开，计时器要是快到点了，随机走动会在跑动途中插进来
	# 抢窗口位置。
	if window and window.input_mode_active:
		var ir := window.get_node_or_null("InputReaction")
		if ir and ir.has_method("_deactivate_work_mode"):
			ir._deactivate_work_mode()

	# 把会抢窗口位置的东西按住：随机走动的计时器一到点就会发起自己的移动，
	# 两个 Tween 同时写 root.position，画面会来回抽。
	if move_effect:
		move_effect.stop()
		move_effect.enable = false
	if rand_move and rand_move.timer:
		rand_move.timer.set_paused(true)

	# 停靠状态下 window.dock_pop 每帧强制 model.flip_h = false，朝向会被它按回去；
	# 而且她正要离开边缘，本来也不该还算停靠着。
	if window and window.docking:
		window.docking = false
	# 把菜单收掉。中键叫出来的设置栏浮在她头顶，她跑出画面时那条栏跟着一起跑，很怪。
	# 停靠时本来就是这么处理的（gui.gd 的 _on_window_docking），这里同一个道理。
	if window:
		var gui := window.get_node_or_null("GUI")
		if gui:
			gui.visible = false

	if model:
		model.flip_h = target.x > from.x
	if anim_controller:
		anim_controller.run()

	_tween = create_tween()
	_tween.tween_property(root, "position", target, duration)
	_tween.finished.connect(_finish.bind(after))
	DoroLog.d("[DORO] enter_exit 开跑 %s -> %s 距离=%.0f 时长=%.2fs t=%d"
		% [str(from), str(target), dist, duration, Time.get_ticks_msec()])


func _finish(after: Callable) -> void:
	_playing = false
	if anim_controller:
		anim_controller.idle()
	if move_effect:
		move_effect.enable = true
	if rand_move and rand_move.timer and rand_move.enable:
		rand_move.timer.set_paused(false)
	DoroLog.d("[DORO] enter_exit 跑完 t=%d" % Time.get_ticks_msec())
	if after.is_valid():
		after.call()
