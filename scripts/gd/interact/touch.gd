extends Node

@export var enable: bool = true
@export var controller: AnimationController
@export var model: GDCubismUserModel
@export var particle: GPUParticles2D
@export var hit_area: GDCubismEffectHitArea

var current_hit_area: String

func _ready() -> void:
	# 命中区域的两级信号都得在代码里连：插件 hit_area_entered -> handler 的 hit -> 这里。
	# 第二级原先也漏了，所以摸脸/摸腿分不开，永远只有兜底的"高兴"。
	if hit_area:
		hit_area.hit.connect(_on_hit_area)
	else:
		# 别静默失败：没接上就退化成"任意位置右键都只给高兴"，正是修复前的症状
		push_warning("EffectTouch.hit_area 未设置，摸脸/摸腿将无法区分")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and enable:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_stroke(event.is_pressed(), "")

## 参数名刻意不叫 enable：本节点有个 @export var enable，同名参数会把它遮蔽，
## 函数体内再想读那个开关就会静默拿到参数值。
func _stroke(active: bool, hit_id: String):
	if active:
		current_hit_area = hit_id
		match hit_id:
			"Face":
				controller.set_expression("SmileEyeClosed")
				particle.emitting = true
			"Leg_back_L":
				# 摸腿是"不高兴"那一档，别再冒爱心
				controller.set_expression("Sullen")
				particle.emitting = false
			_:
				# 未命中特定区域时，任意位置右键抚摸也给出抚摸反应
				controller.set_expression("SmileEyeClosed")
				particle.emitting = true
	else:
		current_hit_area = ""
		controller.set_expression("Idle")
		particle.emitting = false

## 精确命中比 _input 的兜底晚一帧（插件的命中判定要等模型下一帧跑 effect 才 emit），
## 所以这里是覆盖兜底结果，摸腿最终落到 Sullen。
func _on_hit_area(id: String, button_id: int) -> void:
	if button_id == MOUSE_BUTTON_RIGHT and enable:
		_stroke(true, id)
