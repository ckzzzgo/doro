extends GDCubismEffectHitArea

@export var model:GDCubismUserModel
@export var root:Node2D

var pressed: bool = false
var current_button_id: int

signal hit

func _ready() -> void:
	# 插件的 hit_area_entered 必须显式连接才会有人收到。本项目的场景文件里没有
	# 任何 [connection]（信号一律在代码里连），这条一直漏了，导致 hit 从未 emit、
	# touch.gd 的 _on_hit_area 从未被调用 —— 抚摸永远只走 _input 的兜底分支。
	hit_area_entered.connect(_on_hit_area_entered)

func _input(event):
	if event is InputEventMouseButton:
		# 只跟踪左右键。滚轮事件在 Godot 里只有 pressed=true、没有配对的释放事件，
		# 一并跟踪会让 pressed 在用户滚一次滚轮（调桌宠大小）之后永久卡在 true，
		# 此后 _process 每帧都白跑一次命中检测、插件持续发 entered/exited 信号。
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			pressed = event.is_pressed()
			current_button_id = event.button_index

func _process(_delta):
	# set_target 必须在按住期间每帧调用：插件的 _target_update 每帧消费后即复位，
	# 不重新投点就不会做命中判定。这里实时取鼠标位置，不再依赖 MouseMotion 事件，
	# 避免按住不动时用的是上一次移动的旧坐标。
	if pressed == true:
		set_target(_to_model_local(root.get_viewport().get_mouse_position()))

## 视口坐标 -> 模型局部坐标（即 hit area mesh 顶点所在的空间）。
##
## 场景里有 Camera2D，视口坐标和世界坐标之间差着画布变换，所以必须先过一次
## canvas_transform 的逆变换，再交给 to_local()。model.to_local() 本身已经处理了
## 模型的 position / rotation / scale（含 flip_h 造成的负 scale），不需要额外补偿。
##
## 旧实现 recalc_mouse_position() 是从官方 demo 里用途相反的 recalc_model_position()
## 逆推出来的：demo 会把 model.scale 设成自适应值 viewport.y / canvas_size，而本项目
## 把 scale 硬编码成 0.3。两者不等（0.3 vs 640/1800≈0.356），命中坐标被系统性缩掉
## 约 18.5%，靠外侧的区域（如 Leg_back_L 的右半边）会漏判。
func _to_model_local(viewport_pos: Vector2) -> Vector2:
	var world: Vector2 = root.get_viewport().get_canvas_transform().affine_inverse() * viewport_pos
	return model.to_local(world)

func _on_hit_area_entered(_model: GDCubismUserModel, id: String) -> void:
	hit.emit(id, current_button_id)
