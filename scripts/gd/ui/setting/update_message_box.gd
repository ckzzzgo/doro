extends Node

## 检查更新 / 自动更新。
##
## 版本信息读的是公开发布仓库里的 version.json，不是源码仓库的 GitHub API：
## 源码仓库是私有的，匿名请求它的 API 会返回 404（GitHub 对私有仓库故意不返回 403，
## 以免泄露仓库是否存在），所以旧实现永远只会显示「无法获取最新版本」，
## 而且提示语还把人往网络问题上引 —— 其实网络没有任何问题。
##
## 用 raw 地址而不是 GitHub API：raw 不需要任何凭据，也没有 API 那样明确的
## 每小时 60 次匿名配额。但它同样有防滥用限流 —— 短时间内反复请求会返回 429，
## 实测过。桌宠只在用户手动点检查更新时请求一次，正常使用撞不到，
## 但代码仍需把 429 单独讲清楚，否则用户只会看到一个莫名的数字。
const VERSION_URL := "https://raw.githubusercontent.com/ckzzzgo/dororo-release/main/version.json"
const RELEASES_URL := "https://github.com/ckzzzgo/dororo-release/releases/latest"

const MSG_PATH := "NinePatchRect/VBoxContainer/MarginContainer/VBoxContainer/Message"
const JUMP_PATH := "NinePatchRect/VBoxContainer/MarginContainer/VBoxContainer/HBoxContainer/JumpButton"
const UPDATE_PATH := "NinePatchRect/VBoxContainer/MarginContainer/VBoxContainer/HBoxContainer/UpdateButton"
const CANCEL_PATH := "NinePatchRect/VBoxContainer/MarginContainer/VBoxContainer/HBoxContainer/CancelButton"

## 更新过程中用到的目录，放在 user:// 下 —— 必须在安装目录之外：
## 安装目录整个会被替换掉，把安装包或助手放在里面等于自己抽自己的地毯。
const WORK_DIR := "user://update"

var http_request: HTTPRequest

## 解析出来的最新版信息（version / package.url / size / sha256）
var latest_info: Dictionary = {}

var _dl: HTTPRequest
var _dl_path: String = ""
var _busy := false
## 仅在下载进行中为真。必须与 _busy 分开：下载完成后还要经历校验、拉起助手等步骤，
## 若继续按下载进度刷文案，会把后续状态立刻覆盖掉 —— 用户只会看到界面永远停在
## 「100%」，以为卡死了。
var _downloading := false

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

	if response_code == 429:
		_msg("检查更新太频繁被暂时限流了，\n过几分钟再试就好。")
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
		# 只有拿到完整的下载信息、且本次是从真实安装目录运行时，才提供一键更新
		if _can_self_update():
			get_node(UPDATE_PATH).show()
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

# ------------------------------------------------------------------ 一键更新

## 本次运行是否具备自动更新的条件。
## 编辑器里跑没有安装目录可换；助手不在同级目录时也没法替换。
func _can_self_update() -> bool:
	if OS.has_feature("editor"):
		return false
	if not latest_info.has("package"):
		return false
	var pkg: Dictionary = latest_info["package"]
	if not (pkg.has("url") and pkg.has("sha256")):
		return false
	return FileAccess.file_exists(_updater_source_path())

## 测试用的覆盖点：留空则取 exe 所在目录（正常运行的行为）。
## 有这个口子才能在不动真实安装目录的前提下端到端验证整条更新链路。
var install_dir_override: String = ""

func _install_dir() -> String:
	if not install_dir_override.is_empty():
		return install_dir_override
	return OS.get_executable_path().get_base_dir()

func _updater_source_path() -> String:
	return _install_dir().path_join("DoroUpdater.exe")

func _on_update_button_pressed() -> void:
	if _busy:
		return
	_busy = true
	get_node(UPDATE_PATH).disabled = true
	get_node(JUMP_PATH).hide()

	var pkg: Dictionary = latest_info["package"]
	var name: String = str(pkg.get("name", "Dororo_update.zip"))

	DirAccess.make_dir_recursive_absolute(WORK_DIR)
	_dl_path = WORK_DIR.path_join(name)

	_dl = HTTPRequest.new()
	add_child(_dl)
	# 直接落盘。104MB 的包不能先攒在内存里。
	_dl.download_file = _dl_path
	_dl.request_completed.connect(_on_download_completed)

	_msg("正在下载新版本……")
	_downloading = true
	var err := _dl.request(str(pkg["url"]))
	if err != OK:
		_downloading = false
		_fail("下载没能开始（错误码 %d）。" % err)

func _process(_delta: float) -> void:
	if not _downloading or _dl == null:
		return
	var got := _dl.get_downloaded_bytes()
	if got <= 0:
		return
	var total := _dl.get_body_size()
	if total > 0:
		_msg("正在下载新版本…… %d%%\n%s / %s" % [
			int(got * 100.0 / total), _size_text(got), _size_text(total)])
	else:
		_msg("正在下载新版本…… %s" % _size_text(got))

## 小于 1MB 时用 KB，否则用 MB —— 否则几 KB 的包会显示成「0.0 / 0.0 MB」，看着像坏了。
func _size_text(bytes: int) -> String:
	if bytes < 1048576:
		return "%.0f KB" % (bytes / 1024.0)
	return "%.1f MB" % (bytes / 1048576.0)

func _on_download_completed(result: int, response_code: int, _headers, _body) -> void:
	_downloading = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail("下载失败：连接中断，请检查网络后重试。")
		return
	if response_code != 200:
		_fail("下载失败：服务器返回 %d。" % response_code)
		return

	_msg("正在校验安装包……")

	var pkg: Dictionary = latest_info["package"]
	var expect: String = str(pkg["sha256"]).to_lower()
	var actual := FileAccess.get_sha256(_dl_path).to_lower()
	if actual != expect:
		# 校验不过一律放弃：宁可不更新，也不能把来源不明或损坏的包装上去
		DirAccess.remove_absolute(_dl_path)
		_fail("安装包校验不通过，已丢弃。\n请稍后重试或手动下载。")
		return

	# 助手必须从安装目录之外运行，否则替换到自己所在目录会失败
	var updater := WORK_DIR.path_join("DoroUpdater.exe")
	if not _extract_updater_from_package(_dl_path, updater):
		# 包里取不到就退回旧做法：用当前安装目录里那份
		if DirAccess.copy_absolute(_updater_source_path(), updater) != OK:
			_fail("无法准备更新助手。")
			return

	var args := PackedStringArray([
		"--zip", ProjectSettings.globalize_path(_dl_path),
		"--target", _install_dir(),
		"--pid", str(OS.get_process_id()),
	])
	var pid := OS.create_process(ProjectSettings.globalize_path(updater), args)
	if pid <= 0:
		_fail("无法启动更新助手。")
		return

	_msg("即将重启完成更新……")
	# 助手会等本进程退出后再替换文件并把新版拉起来
	await get_tree().create_timer(0.8).timeout
	get_tree().quit()

func _fail(text: String) -> void:
	_busy = false
	_downloading = false
	_msg(text)
	get_node(UPDATE_PATH).disabled = false
	get_node(JUMP_PATH).show()
	if _dl:
		_dl.queue_free()
		_dl = null

func _on_jump_button_pressed() -> void:
	# 优先跳该版本的说明页，没有就跳 releases 列表
	var url: String = str(latest_info.get("notes_url", RELEASES_URL))
	OS.shell_open(url)

func _on_cancel_button_pressed() -> void:
	if _busy:
		return
	queue_free()


## 优先使用新版安装包里的更新助手，而不是当前安装目录里那份。
##
## 助手本身也会有 bug —— 1.1.4 升 1.1.5 那次失败就出在助手身上。如果永远用「已安装
## 的」那份，助手的修复得等用户手动重装一次才生效：这一次更新用的仍是旧助手，
## 等于修复永远慢一个版本，而且偏偏是在更新坏掉的时候没法靠更新修好。
## 改成从刚下载的包里取，修复在下一次更新就能起作用。
##
## 包已经过 sha256 校验，里面的助手与官方发布的一致，可信。取不到则退回旧做法。
func _extract_updater_from_package(zip_path: String, out_path: String) -> bool:
	var reader := ZIPReader.new()
	if reader.open(ProjectSettings.globalize_path(zip_path)) != OK:
		return false

	# 包内路径带版本号（Dororo_vX.Y.Z_win/DoroUpdater.exe），按结尾匹配
	var entry := ""
	for f in reader.get_files():
		if f == "DoroUpdater.exe" or f.ends_with("/DoroUpdater.exe"):
			entry = f
			break
	if entry.is_empty():
		reader.close()
		return false

	var data := reader.read_file(entry)
	reader.close()
	if data.is_empty():
		return false

	var fa := FileAccess.open(out_path, FileAccess.WRITE)
	if fa == null:
		return false
	fa.store_buffer(data)
	fa.close()
	return true
