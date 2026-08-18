extends Node

@export var enable: bool = true
@export var controller: AnimationController
@export var model: GDCubismUserModel
@export var particle: GPUParticles2D
@export var hit_area: GDCubismEffectHitArea

var current_hit_area: String

## 右键按下后，等几帧让命中判定先出结果，再决定表情。
## 命中信号要等模型下一帧跑完 effect 才发出，若按下就立刻定表情，摸身体会先闪一下
## 「开心」再变成「不开心」，摸脸则反过来闪一下「不开心」。两三帧（约 100ms）内定下来，
## 用户感觉不到延迟，却能避免这种闪烁。
const HIT_WAIT_FRAMES := 3
var _pending_frames: int = 0

func _ready() -> void:
	# 命中区域的两级信号都得在代码里连：插件 hit_area_entered -> handler 的 hit -> 这里。
	# 第二级原先也漏了，所以摸脸/摸腿分不开，永远只有兜底的那一种反应。
	if hit_area:
		hit_area.hit.connect(_on_hit_area)
	else:
		# 别静默失败：没接上就退化成"摸哪都一样"，正是修复前的症状
		push_warning("EffectTouch.hit_area 未设置，摸脸/摸身体将无法区分")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and enable:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.is_pressed():
				_pending_frames = HIT_WAIT_FRAMES
				current_hit_area = ""
			else:
				_pending_frames = 0
				_stroke(false, "")

func _process(_delta: float) -> void:
	if _pending_frames <= 0:
		return
	_pending_frames -= 1
	if _pending_frames == 0:
		# 等满都没有部位结果（例如点在完全透明处）-> 按身体处理
		_stroke(true, "")

## 参数名刻意不叫 enable：本节点有个 @export var enable，同名参数会把它遮蔽，
## 函数体内再想读那个开关就会静默拿到参数值。
func _stroke(active: bool, hit_id: String):
	if active:
		current_hit_area = hit_id
		if hit_id == "head":
			# 摸头（脸 + 头发）才开心
			controller.set_expression("SmileEyeClosed")
			particle.emitting = true
		else:
			# 身子和腿都不高兴，也不冒爱心
			controller.set_expression("Sullen")
			particle.emitting = false
	else:
		current_hit_area = ""
		controller.set_expression("Idle")
		particle.emitting = false

func _on_hit_area(id: String, button_id: int) -> void:
	if button_id == MOUSE_BUTTON_RIGHT and enable:
		_pending_frames = 0
		_stroke(true, id)
