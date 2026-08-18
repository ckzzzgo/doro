extends GDCubismEffectHitArea

@export var model:GDCubismUserModel
@export var root:Node2D

var pressed: bool = false
var current_button_id: int

## 发出「摸到了哪个部位」。参数是 REGION_HEAD 或 REGION_BODY。
signal hit

const REGION_HEAD := "head"
const REGION_BODY := "body"

## 头 / 身 的分界线，取模型局部坐标的 y（向下为正）。
##
## 为什么不用「点落在哪个网格里」判断：
##   - 插件自带的 hit_area_entered 只做包围盒判定，而 Face 的包围盒是 792x751，
##     横跨大半个身子；
##   - 改成三角形级判定也不行 —— Live2D 的网格互相大幅重叠，头发网格的三角形一直
##     覆盖到身子上（那里头发贴图是透明的，看不见，但几何上仍然包含它）。实测她身子
##     中部的白色像素会被 Hair_side 系列网格判成「头」。
##     也就是说「点在哪个网格里」并不等于「用户看到的是哪个部位」。
##   - 模型只声明了 Face 和 Leg_back_L 两个命中区，中间还漏一大片。
##
## 局部坐标不受姿态影响（旋转/位移都作用在模型节点上，不改局部坐标），所以停靠、
## 打字模式下这条分界同样成立。阈值按渲染出的头身交界实测：视口 y≈400（缩放 1、
## 模型位于原点、scale 0.3）对应局部 y≈267，取 200 略偏上，让下巴一带仍算头。
const HEAD_BODY_SPLIT_Y := 200.0

var _last_region: String = ""

func _ready() -> void:
	# 插件自身的 hit_area_entered 这里不再使用（只有包围盒精度，且只覆盖两个区），
	# 部位判定改由 _process 每帧自行解析。
	pass

func _input(event):
	if event is InputEventMouseButton:
		# 只跟踪左右键。滚轮事件在 Godot 里只有 pressed=true、没有配对的释放事件，
		# 一并跟踪会让 pressed 在用户滚一次滚轮（调桌宠大小）之后永久卡在 true。
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			pressed = event.is_pressed()
			current_button_id = event.button_index
			if not pressed:
				_last_region = ""

func _process(_delta):
	# 只在右键按住时解析部位：左键是拖窗口，没必要每帧算。
	if not pressed or current_button_id != MOUSE_BUTTON_RIGHT:
		return

	var local := _to_model_local(root.get_viewport().get_mouse_position())
	# 仍然投点：插件内部的 entered/exited 状态机靠它推进，将来若要用回声明式命中区不必再改。
	set_target(local)

	var region := region_at(local)
	if region != _last_region:
		_last_region = region
		hit.emit(region, current_button_id)

## 给定模型局部坐标，返回摸到的是头还是身子。
func region_at(local: Vector2) -> String:
	return REGION_BODY if local.y >= HEAD_BODY_SPLIT_Y else REGION_HEAD

## 视口坐标 -> 模型局部坐标（即网格顶点所在的空间）。
##
## 场景里有 Camera2D，视口坐标和世界坐标之间差着画布变换，所以必须先过一次
## canvas_transform 的逆变换，再交给 to_local()。model.to_local() 本身已经处理了
## 模型的 position / rotation / scale（含 flip_h 造成的负 scale），不需要额外补偿。
func _to_model_local(viewport_pos: Vector2) -> Vector2:
	var world: Vector2 = root.get_viewport().get_canvas_transform().affine_inverse() * viewport_pos
	return model.to_local(world)
