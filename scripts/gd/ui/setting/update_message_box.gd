extends Node

## 检查更新。
##
## 版本信息读的是公开发布仓库里的 version.json，不是源码仓库的 GitHub API：
## 源码仓库是私有的，匿名请求它的 API 会返回 404（GitHub 对私有仓库故意不返回 403，
## 以免泄露仓库是否存在），所以旧实现永远只会显示「无法获取最新版本」，
## 而且提示语还把人往网络问题上引 —— 其实网络没有任何问题。
##
## 另外 raw 地址没有 GitHub API 那样的每小时 60 次匿名限流，也不需要任何凭据。
const VERSION_URL := "https://raw.githubusercontent.com/ckzzzgo/dororo-release/main/version.json"
const RELEASES_URL := "https://github.com/ckzzzgo/dororo-release/releases/latest"

const MSG_PATH := "NinePatchRect/VBoxContainer/MarginContainer/VBoxContainer/Message"
const JUMP_PATH := "NinePatchRect/VBoxContainer/MarginContainer/VBoxContainer/HBoxContainer/JumpButton"

var http_request: HTTPRequest

## 解析出来的最新版信息，留给后续的自动下载用（package.url / sha256 / size）
var latest_info: Dictionary = {}

func _ready() -> void:
	get_node("NinePatchRect/VBoxContainer/TitleBar").set_close_button_visibility(false)
	http_request = HTTPRequest.new()
	add_child(http_request)
	check_for_updates()

func _msg(text: String) -> void:
	get_node(MSG_PATH).set_text(text)

func check_for_updates() -> void:
	_msg("正在检查更新……")

	# 先连信号再发请求。原实现顺序是反的，理论上请求可能在连接完成前就回来，
	# 那样回调永远不会被调用，界面会一直停在初始文案上。
	http_request.request_completed.connect(_on_request_completed)

	var error := http_request.request(VERSION_URL)
	if error != OK:
		_msg("检查更新失败：无法发起网络请求（错误码 %d）" % error)

func _on_request_completed(result: int, response_code: int, _headers, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_msg("检查更新失败：连接不上服务器，请检查网络。")
		return

	if response_code != 200:
		_msg("检查更新失败：服务器返回 %d。" % response_code)
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("version"):
		_msg("检查更新失败：版本信息格式不对。")
		return

	latest_info = parsed
	var current: String = str(ProjectSettings.get_setting("application/config/version"))
	var latest: String = str(parsed["version"])

	if is_update_available(current, latest):
		_msg("发现新版本 v%s\n当前 v%s" % [latest, current])
		get_node(JUMP_PATH).show()
	else:
		_msg("已是最新版本 v%s" % current)

## 逐段比较版本号。两边都容忍 v 前缀，段数不同时缺的按 0 算
## （这样 1.0 与 1.0.0 视为相同，而 1.0.1 比 1.0 新）。
static func is_update_available(current_version: String, latest_version: String) -> bool:
	var cur := current_version.strip_edges().trim_prefix("v").split(".")
	var lat := latest_version.strip_edges().trim_prefix("v").split(".")

	for i in range(max(cur.size(), lat.size())):
		var c := int(cur[i]) if i < cur.size() else 0
		var l := int(lat[i]) if i < lat.size() else 0
		if l > c:
			return true
		if l < c:
			return false

	return false

func _on_jump_button_pressed() -> void:
	# 优先跳该版本的说明页，没有就跳 releases 列表
	var url: String = str(latest_info.get("notes_url", RELEASES_URL))
	OS.shell_open(url)

func _on_cancel_button_pressed() -> void:
	queue_free()
