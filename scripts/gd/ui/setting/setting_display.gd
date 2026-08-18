extends Node

## 帧率设置。
##
## 这里原本有三项：FPS 限制（勾选框 + 30~200 滑条）、垂直同步、MSAA。后两项对一个
## Live2D 桌宠意义很小，已去掉：
##   垂直同步 —— 帧率本来就压得比显示器刷新率低，不会撕裂，开了只多一点输入延迟；
##   MSAA     —— 它磨平的是多边形边缘，而 doro 的轮廓是贴图里透明像素的边界，管不到。
## 滑条也换成三个档位：它能选出 70、110 这类既不对齐显示器刷新率、也没有实际
## 收益的数字，让人纠结的成本大于收益。
##
## 注意帧率只影响渲染。鼠标穿透检测（MouseDetection）跑在物理帧上、每两帧检测一次，
## 也就是固定约 30 次/秒，不随这里的档位变化。

const TIER_POWER_SAVE := 0
const TIER_STANDARD := 1
const TIER_MONITOR := 2

const TIER_FPS := {TIER_POWER_SAVE: 30, TIER_STANDARD: 60}

@onready var _config: ConfigManager = get_node("/root/Config")
@onready var _option: OptionButton = $FPSContainer/OptionButton
var _section: ConfigSection

func _ready() -> void:
	_section = _config.add_section(&"display")

	_migrate_old_keys()
	_label_monitor_tier()
	_bind_components()
	_config.save_config()
	_section.load_props()
	_load_config()

## 从旧版本（勾选框 + 滑条）升级上来时，把原来的数值折算成最接近的档位，
## 否则用户的设置会静默回到默认的 30。只在 fps_tier 还不存在时折算一次；
## 旧键留在配置文件里不管，它们不再被读取，也不影响什么。
func _migrate_old_keys() -> void:
	# 默认值不能传 null：ConfigFile 会把 null 当作「没给默认值」，键不存在时
	# 会往控制台打一条 ERROR —— 全新用户每次启动都会看到。所以用哨兵值判断。
	if _config.get_value("display", "fps_tier", -1) != -1:
		return

	var old_limit = _config.get_value("display", "fps_limit", -1)
	var old_fps = _config.get_value("display", "max_fps", -1.0)
	var had_limit := old_limit is bool
	var had_fps := (old_fps is float or old_fps is int) and float(old_fps) > 0.0
	if not had_limit and not had_fps:
		return

	var tier := TIER_STANDARD
	if had_limit and old_limit == false:
		# 原来是「不限制」，三个档位里最接近这个意图的是跟随显示器
		tier = TIER_MONITOR
	elif had_fps:
		# 按当初填的数值猜意图，而不是单纯找最近的数字：滑条能拉到 200，
		# 拉那么高的人想要的是「越高越好」，对应跟随显示器；折算成 60 是吃亏的
		# —— 在 60Hz 屏上看不出来，换到高刷屏就明显了。
		var f := float(old_fps)
		if f <= 45.0:
			tier = TIER_POWER_SAVE
		elif f <= 75.0:
			tier = TIER_STANDARD
		else:
			tier = TIER_MONITOR
	_config.set_value("display", "fps_tier", tier)

## 第三档的实际帧率取决于显示器，直接写进选项文字里，省得用户猜。
func _label_monitor_tier() -> void:
	_option.set_item_text(TIER_MONITOR, "跟随显示器（%d FPS）" % _monitor_fps())

func _monitor_fps() -> int:
	var hz := DisplayServer.screen_get_refresh_rate(DisplayServer.window_get_current_screen())
	# 虚拟显示器和部分驱动查不到刷新率，会返回 -1，这时退回 60
	return int(round(hz)) if hz >= 30.0 else 60

func _tier_fps(tier: int) -> int:
	return TIER_FPS.get(tier, _monitor_fps())

func _bind_components():
	_section.set_prop(&"fps_tier", TIER_POWER_SAVE)
	_section.bind(&"fps_tier").with(_update_fps_tier).to_option_button(_option)

func _load_config():
	var tier: int = _section.get_prop(&"fps_tier")
	_option.select(tier)
	_apply_tier(tier)

func _update_fps_tier(_name, value):
	_apply_tier(int(value))

func _apply_tier(tier: int) -> void:
	Engine.set_max_fps(_tier_fps(tier))
