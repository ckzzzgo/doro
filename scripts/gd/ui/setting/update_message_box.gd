extends Node

## 检查更新 / 自动更新。
##
## 版本信息读的是仓库根目录的 version.json，不是 GitHub 的 releases API。
##
## 曾经有一版直接请求源码仓库的 GitHub API，那时仓库是私有的，匿名请求一律返回
## 404（GitHub 对私有仓库故意不返回 403，以免泄露仓库是否存在），于是永远显示
## 「无法获取最新版本」，提示语还把人往网络问题上引 —— 其实网络没毛病。
## 仓库现在已经公开，那个具体障碍没有了，但仍然不走 API：
##
##   一是 version.json 里带安装包的 sha256，releases API 不提供，
##     而一键更新要靠它校验下载完整性；
##   二是 raw 地址没有 API 那样明确的每小时 60 次匿名配额。
##
## raw 也有防滥用限流，短时间内反复请求会返回 429，实测过。桌宠只在用户手动点
## 检查更新时请求一次，正常使用撞不到，但代码仍需把 429 单独讲清楚，
## 否则用户只会看到一个莫名的数字。
##
## 2026-08 起源码和发布合并到同一个仓库，这两个地址从 dororo-release 改到 doro。
## 装了 1.4.4 及更早版本的机器仍在轮询旧地址，检查更新会失败（当时全网累计
## 下载 43 次，基本只有作者和一位测试者，让他们手动下一次即可）。
const VERSION_URL := "https://raw.githubusercontent.com/ckzzzgo/doro/main/version.json"
const RELEASES_URL := "https://github.com/ckzzzgo/doro/releases/latest"
## 一键更新只认这个前缀下的下载地址，理由见 _can_self_update。
const PACKAGE_URL_PREFIX := "https://github.com/ckzzzgo/doro/releases/download/"

## 检查更新的网络超时。
##
## Godot 的 HTTPRequest 默认 timeout = 0，意思是「永不超时」。请求一旦挂住
## —— 不是被拒绝，而是握手包丢进黑洞没人回 —— request_completed 就永远不触发，
## 界面死在「正在检查更新……」上。用户看到的是无限转圈，分不清程序卡死还是网络慢。
## 这不是理论问题，是用户实际反馈过的现象。
##
## 为什么直连必然挂住：HTTPRequest 既不读 Windows 系统代理，也不读 HTTP_PROXY
## 环境变量。梯子若只开「系统代理」模式，本程序全程直连 raw.githubusercontent.com，
## 等于没挂梯子；只有 TUN / 增强模式（在网卡层接管流量）才对本程序生效。
## 所以「明明挂了梯子却检查不到」是必然结果，不是偶发。
##
## 修不了可达性，至少要让它失败得明确：10 秒后收工，把原因和退路一起告诉用户。
const CHECK_TIMEOUT_SEC := 8.0

## 下载源，按顺序试，第一个空串表示直连 GitHub。
##
## 为什么要有这个：国内没梯子的用户根本连不上 GitHub，这不是代码能修的——包放在
## 那儿，够不着就是够不着。唯一的出路是换一个够得着的地方拿同一个文件。这几个是
## 公共的 GitHub 加速服务，用法是把完整的 GitHub 地址接在它后面。
##
## 名单是**实测**出来的，不是照着记忆写的：逐个取过 version.json 比对内容一致，
## 又用 Range 请求取过安装包前 2 KB 比对字节、并核对 content-length 与直连相同
## （99776005）。试过但当时不通的：ghproxy.net、mirror.ghproxy.com、ghp.ci、
## hub.gitmirror.com、raw.gitmirror.com。jsdelivr 能取 version.json 但不代理
## Release 附件，所以没收进来——一个源要能同时干两件事，否则逻辑要分叉。
##
## 还专门验过一条决定成败的性质：这三个都是**自己转发内容**（第一跳就是 200），
## 不是回一个 302 把人打回 github.com。若是后者，连不上 GitHub 的用户跟着跳转
## 照样到不了，这个机制就等于没做。以后往名单里加新的，这一条必须先验。
##
## 这类服务生死很快。哪天全都不通了，用户仍有「手动下载」那条退路，不会卡死。
##
## 安全性：包下完一定校验 sha256（见 _on_download_completed），镜像给了坏东西会被
## 直接丢弃。但 sha256 本身来自 version.json，若 version.json 也是从镜像取的，
## 信任链的根就落在那个镜像上了——所以直连永远排第一，只有它不通才退而求其次；
## 另外 _package_url_ok 会要求 package.url 必须是 github.com，镜像改不了下载目标。
const MIRRORS := [
	"",
	"https://gh-proxy.com/",
	"https://ghfast.top/",
	"https://gh.llkk.cc/",
]

## 当前用第几个源。检查更新时逐个试，试通了下载就继续用它——已知它通，没必要重试直连。
var _source := 0

## 下载卡死的判定阈值：多久没收到任何新字节就认为断了。
##
## 这里不能用 HTTPRequest.timeout —— 那是整个请求的时限，而安装包 100MB+，
## 慢网用户正常下十几分钟，固定时限会把他们误杀。改成盯「有没有进度」：
## 只要字节数还在涨就一直等，彻底不动了才判失败。
const DL_STALL_SEC := 30.0

const MSG_PATH := "Root/VBoxContainer/MarginContainer/VBoxContainer/Message"
const JUMP_PATH := "Root/VBoxContainer/MarginContainer/VBoxContainer/HBoxContainer/JumpButton"
const UPDATE_PATH := "Root/VBoxContainer/MarginContainer/VBoxContainer/HBoxContainer/UpdateButton"

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

## 停滞检测用：上次见到的已下载字节数，和距上次增长过了多久
var _dl_last_bytes := 0
var _dl_stall := 0.0

func _ready() -> void:
	get_node("Root/VBoxContainer/TitleBar").set_close_button_visibility(false)
	http_request = HTTPRequest.new()
	add_child(http_request)
	# 信号在这里连一次就够。原来连在 check_for_updates 里，那时它只被调用一次所以没事；
	# 现在要为每个候选源重试，连在那儿会越连越多，一次回调触发好几遍。
	http_request.request_completed.connect(_on_request_completed)
	check_for_updates()

func _msg(text: String) -> void:
	get_node(MSG_PATH).set_text(text)

func check_for_updates() -> void:
	_source = 0
	_try_check()


## 用第 _source 个源发一次请求。失败由 _on_request_completed 决定要不要换下一个。
func _try_check() -> void:
	_msg("正在检查更新……" if _source == 0 else "直连不通，正在试备用线路（%d/%d）……"
		% [_source, MIRRORS.size() - 1])

	# 必须在 request() 之前设置，本次请求才受这个时限约束
	http_request.timeout = CHECK_TIMEOUT_SEC

	var error := http_request.request(_via(VERSION_URL))
	if error != OK:
		_msg("检查更新失败：无法发起网络请求（错误码 %d）" % error)


## 把地址接到当前源后面。直连时前缀是空串，等于原样返回。
func _via(url: String) -> String:
	return MIRRORS[_source] + url


## 还有没有没试过的源；有就换到下一个并重来。
func _next_source() -> bool:
	_source += 1
	return _source < MIRRORS.size()

func _on_request_completed(result: int, response_code: int, _headers, body: PackedByteArray) -> void:
	# 网络层面没通：换下一个源再试，全都试完了才认输。
	if result != HTTPRequest.RESULT_SUCCESS:
		if _next_source():
			_try_check()
			return
		var why := "网络错误（代码 %d）" % result
		if result == HTTPRequest.RESULT_TIMEOUT:
			why = "等了 %d 秒没有任何回应" % int(CHECK_TIMEOUT_SEC)
		_offline("直连和 %d 条备用线路都连不上：%s。" % [MIRRORS.size() - 1, why])
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

## 网络到不了时的统一出口。
##
## 原来只说「请检查网络」，这句话对用户毫无用处 —— 他的网络通常好得很，能上网页、
## 能上微信，只是这一个域名连不上。他会去重启路由器，然后回来骂程序坏了。
## 所以这里必须给三样东西：到底哪一步不通、他自己能动手的办法、以及一条不依赖
## 网络自动化的退路（手动下载）。
func _offline(reason: String) -> void:
	_msg("%s\n有梯子的话需要开 TUN / 增强模式，\n只设系统代理对本程序无效。\n也可以手动下载新版。" % reason)
	# 自动更新走不通时把跳转按钮放出来，否则用户看着一条报错无路可走
	get_node(JUMP_PATH).show()

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
	if not str(pkg["url"]).begins_with(PACKAGE_URL_PREFIX):
		# version.json 可能是从第三方镜像取回来的。包本身有 sha256 兜底，但那个
		# sha256 也写在同一份 version.json 里 —— 光靠它，被掉包的清单可以自圆其说。
		# 所以再钉一条：下载地址必须是本仓库的 Release，镜像只能当搬运工，不能改目的地。
		push_warning("version.json 里的下载地址不是本仓库的 Release，已拒绝一键更新：%s"
			% str(pkg["url"]))
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

	# 检查更新时哪个源试通了，下载就继续用它 —— 已知它到得了，没必要再从直连重来一遍。
	_msg("正在下载新版本……" if _source == 0 else "正在通过备用线路下载……")
	_downloading = true
	_dl_last_bytes = 0
	_dl_stall = 0.0
	var err := _dl.request(_via(str(pkg["url"])))
	if err != OK:
		_downloading = false
		_fail("下载没能开始（错误码 %d）。" % err)

func _process(delta: float) -> void:
	if not _downloading or _dl == null:
		return

	var got := _dl.get_downloaded_bytes()

	# 卡死判定。连接阶段 got 还是 0，这段时间同样计入 —— 「一直连不上」和
	# 「下到一半断了」对用户是同一件事：界面不动了。两者都该有个说法，
	# 而不是让「正在下载新版本……」停在那里过夜。
	if got > _dl_last_bytes:
		_dl_last_bytes = got
		_dl_stall = 0.0
	else:
		_dl_stall += delta
		if _dl_stall >= DL_STALL_SEC:
			_fail("下载卡住了：%d 秒没有任何进度。\n换个网络再试，或手动下载新版。" % int(DL_STALL_SEC))
			return

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
		# 先显式取消，再释放。卡死那条路径上请求还挂着，
		# 只 queue_free 依赖析构去断连接，不如自己断干净。
		_dl.cancel_request()
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
