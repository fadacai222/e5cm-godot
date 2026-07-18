extends Node
## 端到端自动驾驶器：真实运行游戏，自动走完 投币→登陆→资料→模式→子模式→选歌→加载→游玩→结算，
## 每步截图到 user://shots/，最后退出。用法：godot --path . res://tests/autotest.tscn

var _step := 0
var _shots_dir := "user://shots"
var _original_runtime: Dictionary = {}
var _user_file_snapshots: Dictionary = {}
var _finishing := false
const CaptureContract = preload("res://tests/parity/capture_contract.gd")
const USER_FILES := [
	"user://credits.cfg",
	"user://profile.json",
	"user://records.json",
	"user://favorites.json",
	"user://settings.cfg",
]


func _ready() -> void:
	_configure_capture_window()
	var configured_shots_dir := OS.get_environment("E5CM_SHOTS_DIR").strip_edges()
	if not configured_shots_dir.is_empty():
		_shots_dir = configured_shots_dir
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	_snapshot_user_files()
	_prepare_test_state()
	_run()


func _configure_capture_window() -> void:
	# Windows 会把带标题栏的 1920x1080 窗口压进工作区，实际纹理曾变成 1886x1061。
	# 无边框窗口可让窗口客户区与目标截图尺寸严格一致。
	var window := get_window()
	window.mode = Window.MODE_WINDOWED
	window.borderless = true
	window.position = Vector2i.ZERO
	window.size = CaptureContract.EXPECTED_SIZE


func _prepare_test_state() -> void:
	_original_runtime = {
		"credits": GameState.credits,
		"persist_credits": GameState.persist_credits,
		"autoplay": SettingsStore.autoplay,
		"profile_persist": ProfileStore.persist_enabled,
		"settings_persist": SettingsStore.persist_enabled,
	}
	GameState.persist_credits = false
	ProfileStore.persist_enabled = false
	SettingsStore.persist_enabled = false
	GameState.credits = 0
	SettingsStore.autoplay = true


func _restore_runtime_state() -> void:
	if _original_runtime.is_empty():
		return
	GameState.credits = int(_original_runtime.get("credits", 0))
	GameState.persist_credits = bool(_original_runtime.get("persist_credits", true))
	SettingsStore.autoplay = bool(_original_runtime.get("autoplay", false))
	ProfileStore.persist_enabled = bool(_original_runtime.get("profile_persist", true))
	SettingsStore.persist_enabled = bool(_original_runtime.get("settings_persist", true))
	_original_runtime.clear()


func _snapshot_user_files() -> void:
	_user_file_snapshots.clear()
	for path: String in USER_FILES:
		_user_file_snapshots[path] = {
			"exists": FileAccess.file_exists(path),
			"bytes": FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray(),
		}


func _restore_user_files() -> void:
	for path: String in USER_FILES:
		var snapshot: Dictionary = _user_file_snapshots.get(path, {})
		if bool(snapshot.get("exists", false)):
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file:
				file.store_buffer(snapshot.get("bytes", PackedByteArray()))
				file.close()
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _exit_tree() -> void:
	_restore_runtime_state()
	_restore_user_files()


func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%02d_%s.png" % [_shots_dir, _step, name]
	var result: Dictionary = CaptureContract.save_png_checked(img, path)
	if not bool(result.get("ok", false)):
		await _abort("invalid screenshot: %s" % str(result.get("error", "unknown error")))
		return
	_step += 1
	print("[autotest] shot: %s 1920x1080 (scene=%s)" % [name,
		get_tree().current_scene.name if get_tree().current_scene else "?"])


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _scene() -> Node:
	return get_tree().current_scene


func _wait_for_scene(scene_name: String, timeout_sec := 3.0) -> Node:
	var elapsed := 0.0
	while elapsed < timeout_sec:
		var current := _scene()
		if current != null and current.name == scene_name:
			return current
		await _wait(0.1)
		elapsed += 0.1
	return null


func _abort(reason: String) -> void:
	push_error("[autotest] ABORT: %s" % reason)
	await _finish(1)


func _finish(exit_code: int) -> void:
	if _finishing:
		return
	_finishing = true
	_restore_runtime_state()
	_restore_user_files()
	if AudioDirector.has_method("release_for_shutdown"):
		AudioDirector.release_for_shutdown()
	if exit_code == 0:
		print("[autotest] DONE, shots in %s" % ProjectSettings.globalize_path(_shots_dir))
	await _wait(0.2)
	get_tree().quit(exit_code)


func _run() -> void:
	await _wait(0.5)
	SceneRouter.change_to("coin", {}, false)
	await _wait(1.0)
	await _shot("coin_insert")

	# 投3币 → 玩家选择
	for i in 3:
		GameState.insert_coin()
		await _wait(0.15)
	await _wait(0.5)
	await _shot("coin_player_select")

	_scene()._pick(1)
	await _wait(1.0)
	await _shot("login_select")

	# 游客直接进大模式？为了覆盖 VIP 路径走刷卡
	_scene()._pick("VIP")
	await _wait(0.5)
	await _shot("login_swipe")
	_scene()._auto_swiping = true
	await _wait(1.5)
	await _shot("profile")
	_scene()._open_nickname_editor()
	await _wait(0.35)
	await _shot("profile_nickname_editor")
	_scene()._close_editor()

	_scene()._confirm()
	await _wait(1.0)
	await _shot("mode_select")

	_scene()._confirm(1)  # 第一次：选中竞速并展开大图，与原版对照路径一致
	await _wait(0.5)
	await _shot("mode_selected")
	_scene()._confirm(1)  # 第二次：确认进入
	await _wait(0.42)
	await _shot("submode_entering")
	await _wait(1.25)
	await _shot("submode_select")

	# 选 club（找索引）
	var sub = _scene()
	var idx := 0
	for i in (sub._items as Array).size():
		if str(sub._items[i]).to_lower().contains("club"):
			idx = i
			break
	sub._confirm(idx)  # 第一次：选中并显示大图标
	await _wait(0.5)
	await _shot("submode_selected")
	sub._confirm(idx)  # 第二次：确认进入
	await _wait(1.5)
	await _shot("song_select")

	_scene()._on_slot_settings()
	await _wait(0.5)
	await _shot("song_settings")
	_scene().esc_menu.close_menu()

	# 玩法/星级筛选面板
	_scene()._on_slot_filter()
	await _wait(0.5)
	await _shot("song_filter")
	_scene().filter_panel.close()

	# 详情大图页（单击卡片/踏板确认进入）
	_scene()._refresh_detail(true)
	await _wait(0.8)
	await _shot("song_detail")

	_scene()._start_song()
	await _wait(1.0)
	await _shot("loading")

	_scene()._go()
	var gameplay := await _wait_for_scene("Gameplay", 5.0)
	if gameplay == null:
		await _abort("timeout waiting for scene: Gameplay")
		return
	await _wait(0.25)
	await _shot("gameplay_ready_start")
	await _wait(0.85)
	await _shot("gameplay_ready_go")
	await _wait(1.15)
	await _shot("gameplay_active")
	await _wait(13.0)  # 自动打到音符密集区（本曲前奏约13秒）
	await _shot("gameplay_autoplay")
	# ESC 菜单
	var gp = _scene()
	gp.conductor.pause()
	gp.esc_menu.open_menu()
	await _wait(0.5)
	await _shot("gameplay_esc_menu")
	gp.esc_menu.close_menu()
	await _wait(4.0)
	await _shot("gameplay_autoplay2")

	# 直接跳结算。预填前两把经验，确保第 3 把真实进入经验面板阶段。
	var mode := str(GameState.big_mode)
	var progress := ProfileStore.get_mode_progress(mode)
	GameState.flow.start_new_match()
	GameState.flow.settle_song_exp(mode, progress, 1, "S", 0, 0, 0)
	GameState.flow.settle_song_exp(mode, progress, 2, "S", 0, 0, 0)
	GameState.flow.current_round = 3
	_scene()._finish_song(false)
	# 全 P/全连会先播放约 3.2 秒成就动画，3 秒等待会把旧 Gameplay 当成结算节点。
	var settlement := await _wait_for_scene("Settlement", 8.0)
	if settlement == null or not is_instance_valid(settlement):
		await _abort("timeout waiting for scene: Settlement")
		return
	await _wait(0.45)
	await _shot("settlement_phase1_counting")
	await _wait(1.15)
	await _shot("settlement_phase1_grade")
	var phase_wait := 0.0
	while is_instance_valid(settlement) and int(settlement._phase) < 2 and phase_wait < 8.0:
		await _wait(0.1)
		phase_wait += 0.1
	if not is_instance_valid(settlement) or int(settlement._phase) < 2:
		await _abort("settlement did not reach phase 2")
		return
	await _wait(0.2)
	await _shot("settlement_phase2_exp")
	if int(settlement._phase) < 3:
		settlement._enter_phase3()
	await _wait(0.2)
	await _shot("settlement_phase3_continue")

	await _finish(0)
