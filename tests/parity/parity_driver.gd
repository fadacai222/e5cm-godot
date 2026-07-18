extends Node
## 单状态 Godot 对等驱动器。
## E5CM_PARITY_STATE_ID=coin.idle
## E5CM_PARITY_OUTPUT_ROOT=C:/.../parity/current/godot

const StateLoader = preload("res://tests/parity/state_loader.gd")
const FixtureController = preload("res://tests/parity/fixture_controller.gd")
const CaptureController = preload("res://tests/parity/capture_controller.gd")
const StateExporter = preload("res://tests/parity/state_exporter.gd")

var _fixtures
var _finishing := false


func _ready() -> void:
	call_deferred("_detach_and_run")


func _detach_and_run() -> void:
	reparent(get_tree().root)
	await get_tree().process_frame
	await _run()


func _exit_tree() -> void:
	if _fixtures != null:
		_fixtures.restore()


func _run() -> void:
	var loader = StateLoader.new()
	var manifest: Dictionary = loader.load_manifest("res://parity/state_manifest.json")
	var state_id := OS.get_environment("E5CM_PARITY_STATE_ID").strip_edges()
	if state_id.is_empty():
		await _fail("E5CM_PARITY_STATE_ID is required")
		return
	var state: Dictionary = loader.find_state(manifest, state_id)
	if state.is_empty():
		await _fail("unknown parity state: %s" % state_id)
		return

	var capture = CaptureController.new()
	capture.configure_window(get_window())
	_fixtures = FixtureController.new()
	var fixture_digests: Dictionary = _fixtures.begin(state.get("context", {}))
	var driver: Dictionary = state.get("godot", {})
	var scene_name := str(driver.get("scene", ""))
	var context: Dictionary = state.get("context", {})
	SceneRouter.change_to(scene_name, _scene_payload(scene_name, context), false)
	var scene := await _wait_for_scene(scene_name, 5.0)
	if scene == null:
		await _fail("timeout waiting for scene: %s" % scene_name)
		return
	_apply_fixture(scene_name, scene, str(driver.get("fixture", "default")), context)
	for raw_action in driver.get("actions", []):
		var action: Dictionary = raw_action
		var error := _execute_action(scene_name, scene, str(action.get("name", "")), action.get("params", {}))
		if not error.is_empty():
			await _fail(error)
			return
		await get_tree().process_frame

	var exporter = StateExporter.new()
	var stable_frames := int(state.get("stableFrames", 3))
	var stable_count := 0
	var previous := ""
	var exported := {}
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		exported = exporter.export(scene_name, scene, state_id)
		var wait: Dictionary = state.get("wait", {})
		var matched := _condition(loader.value_at_path(exported, str(wait.get("path", ""))),
			str(wait.get("operator", "equals")), wait.get("expected"))
		var stability := {}
		var stability_paths: Array = state.get("stabilityPaths", [str(wait.get("path", ""))])
		for raw_path in stability_paths:
			var stable_path := str(raw_path)
			stability[stable_path] = loader.value_at_path(exported, stable_path)
		var fingerprint := JSON.stringify(stability)
		stable_count = stable_count + 1 if matched and fingerprint == previous else (1 if matched else 0)
		previous = fingerprint
		if stable_count >= stable_frames:
			break
		await get_tree().process_frame
	if stable_count < stable_frames:
		await _fail("state did not become stable: %s" % state_id)
		return

	await get_tree().process_frame
	await get_tree().process_frame
	var output_root := OS.get_environment("E5CM_PARITY_OUTPUT_ROOT").strip_edges()
	if output_root.is_empty():
		output_root = ProjectSettings.globalize_path("res://parity/current/godot")
	var output_dir := output_root.path_join(state_id)
	DirAccess.make_dir_recursive_absolute(output_dir)
	var frame_path := output_dir.path_join("frame.png")
	var capture_result: Dictionary = capture.capture(get_viewport(), frame_path)
	if not bool(capture_result.get("ok", false)):
		await _fail(str(capture_result.get("error", "capture failed")))
		return
	exported["fixtureDigests"] = fixture_digests
	_write_json(output_dir.path_join("state.json"), exported)
	_write_json(output_dir.path_join("capture.json"), capture_result)
	_write_json(output_dir.path_join("metadata.json"), {
		"stateId": state_id,
		"sourceProject": "e5cm-godot",
		"width": int(capture_result.get("width", 0)),
		"height": int(capture_result.get("height", 0)),
		"sha256": FileAccess.get_sha256(frame_path),
		"scene": scene_name,
		"fixture": str(driver.get("fixture", "default")),
		"fixtureDigests": fixture_digests,
		"animation": state.get("context", {}).get("animation"),
		"renderer": RenderingServer.get_video_adapter_name(),
		"fullscreen": false,
	})
	print("[parity] PASS %s %s" % [state_id, frame_path])
	await _finish(0)


func _scene_payload(scene_name: String, context: Dictionary) -> Dictionary:
	if scene_name != "gameplay":
		return {}
	var major := str(context.get("majorMode", "竞速"))
	var sub := str(context.get("subMode", "club"))
	var wanted_relative := str(context.get("songRelativePath", "")).replace("\\", "/")
	var wanted_chart := str(context.get("chartType", "")).strip_edges().to_lower()
	for raw_song in SongLibrary.get_songs(major, sub):
		if not raw_song is Dictionary:
			continue
		var song: Dictionary = raw_song
		var full_sm := str(song.get("sm", "")).replace("\\", "/")
		var relative_tail := wanted_relative.trim_prefix("songs/")
		if not wanted_relative.is_empty() \
				and not (full_sm.ends_with(wanted_relative) or full_sm.ends_with(relative_tail)):
			continue
		var chart := str(song.get("charttype", "")).strip_edges().to_lower()
		if not wanted_chart.is_empty() and not chart.is_empty() and chart != wanted_chart:
			continue
		return {
			"sm": song.get("sm", ""), "mp3": song.get("mp3", ""),
			"cover": song.get("cover", ""), "name": song.get("name", ""),
			"star": int(context.get("level", song.get("star", 0))),
			"mode": major, "submode": sub,
			"sm_key": song.get("sm_key", wanted_relative),
			"prefer_double": wanted_chart.contains("double"), "couple": false,
			"target_charttype": wanted_chart if not wanted_chart.is_empty() else chart,
		}
	# 防御兜底：Manifest 路径存在但曲库缓存尚未刷新时，直接从歌曲目录补齐音频和封面。
	var absolute_sm := AssetLoader.abs_path(wanted_relative)
	var song_dir := absolute_sm.get_base_dir()
	var mp3 := ""
	var cover := ""
	var access := DirAccess.open(song_dir)
	if access != null:
		access.list_dir_begin()
		var entry := access.get_next()
		while not entry.is_empty():
			if not access.current_is_dir():
				var lower := entry.to_lower()
				if mp3.is_empty() and lower.get_extension() in ["mp3", "ogg"]:
					mp3 = song_dir.path_join(entry)
				elif lower == "bann.jpg" or (cover.is_empty() and lower.get_extension() in ["png", "jpg", "jpeg", "webp"]):
					cover = song_dir.path_join(entry)
			entry = access.get_next()
		access.list_dir_end()
	return {
		"sm": absolute_sm, "mp3": mp3, "cover": cover,
		"name": str(context.get("songTitle", wanted_relative.get_file().get_basename())),
		"star": int(context.get("level", 0)), "mode": major, "submode": sub,
		"sm_key": wanted_relative, "prefer_double": wanted_chart.contains("double"),
		"couple": false, "target_charttype": wanted_chart,
	}


func _apply_fixture(scene_name: String, scene: Node, fixture: String, context: Dictionary) -> void:
	if scene_name == "coin":
		GameState.credits = int(context.get("credit", 0))
		scene._update_credit_label(GameState.credits)
		scene._refresh(false)
		if fixture == "ready" and not GameState.has_enough_credits():
			GameState.credits = GameState.CREDITS_PER_GAME
			scene._update_credit_label(GameState.credits)
			scene._refresh(false)
		# 固定闪烁相位：让"请投币！"和顶部提示在捕获窗口内处于可见秒。
		if scene.has_method("reset_blink_phase"):
			scene.reset_blink_phase()


func _execute_action(scene_name: String, scene: Node, action: String, params: Dictionary) -> String:
	if scene_name == "coin":
		match action:
			"coin.set":
				GameState.credits = maxi(0, int(params.get("count", 0)))
				scene._update_credit_label(GameState.credits)
				scene._refresh(false)
				return ""
			"player.focus":
				var players := clampi(int(params.get("players", 1)), 1, 2)
				scene._pedal_pick = players
				scene._refresh(false)
				return ""
			"player.select":
				scene._pick(clampi(int(params.get("players", 1)), 1, 2))
				return ""
			"background.seek":
				var player := SharedVideoBackground.get("_player") as VideoStreamPlayer
				if player == null or player.stream == null:
					return "shared background video is unavailable"
				var seconds := clampf(float(params.get("seconds", 0.0)), 0.0, 600.0)
				# 预放大版由 pygame smoothscale 生成（原版运行时同管线），1:1 显示避免引擎缩放差异。
				var fixture_texture := load("res://parity/fixtures/video_coin_2_500_scaled.png") as Texture2D
				if fixture_texture == null:
					return "fixed background frame fixture is unavailable"
				player.stop()
				player.visible = false
				var fixed := SharedVideoBackground.get_node_or_null("ParityFixedVideoFrame") as TextureRect
				if fixed == null:
					fixed = TextureRect.new()
					fixed.name = "ParityFixedVideoFrame"
					fixed.position = Vector2(0, -180)
					fixed.size = Vector2(1920, 1440)
					fixed.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					fixed.stretch_mode = TextureRect.STRETCH_SCALE
					# 原版对视频帧用 smoothscale（双线性），NEAREST 会产生全屏块状边缘噪声。
					fixed.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
					fixed.mouse_filter = Control.MOUSE_FILTER_IGNORE
					SharedVideoBackground.add_child(fixed)
				fixed.texture = fixture_texture
				scene.set_meta("parity_background_time", seconds)
				return ""
	if scene_name == "gameplay":
		match action:
			"player.ready":
				_freeze_gameplay(scene, 0.0, false, params)
				return ""
			"player.seek":
				_freeze_gameplay(scene, maxf(0.0, float(params.get("seconds", 0.0))), false, params)
				return ""
			"player.nickname":
				var nickname := str(params.get("value", "")).strip_edges()
				if nickname.is_empty():
					return "player.nickname requires a non-empty value"
				scene._apply_gameplay_nickname(nickname)
				return ""
			"player.health":
				if scene.hp == null:
					return "gameplay HP system is unavailable"
				scene.hp.hp = clampi(int(params.get("totalHp", 700)), 0, 1200)
				scene._update_hud()
				return ""
			"player.pause":
				var current := float(scene.conductor.get_chart_time_raw()) if scene.conductor != null else 0.0
				_freeze_gameplay(scene, current, true)
				return ""
			"player.resume":
				if scene.esc_menu != null and scene.esc_menu.is_open():
					scene.esc_menu.close_menu()
				_freeze_gameplay(scene, float(scene.conductor.get_chart_time_raw()), false)
				return ""
	return "unsupported Godot parity action: %s/%s" % [scene_name, action]


func _freeze_gameplay(scene: Node, seconds: float, show_pause_menu: bool,
		fixture: Dictionary = {}) -> void:
	if scene.ready_anim != null:
		scene.ready_anim.seek_for_test(scene.ready_anim.total_duration())
	if scene.conductor != null:
		scene.conductor.seek_for_test(seconds, true)
	if scene.score != null and fixture.has("fixtureScore"):
		scene.score.current_score = int(fixture.get("fixtureScore", 0))
		scene.score.current_combo = int(fixture.get("fixtureCombo", 0))
		scene.score.max_combo = scene.score.current_combo
		scene.score.last_judge = "perfect"
		scene.score.counts = {"perfect": int(fixture.get("fixturePerfect", 0)),
			"cool": int(fixture.get("fixtureCool", 0)),
			"good": int(fixture.get("fixtureGood", 0)),
			"miss": int(fixture.get("fixtureMiss", 0))}
	if scene.note_field != null:
		scene.note_field.position = Vector2.ZERO
		scene.note_field.scale = Vector2.ONE
		scene.note_field.modulate.a = 1.0
		scene.note_field.update_field(seconds, 0.0)
	scene.hud.position = scene._hud_base_position
	scene.hud.modulate.a = 1.0
	scene._update_dynamic_hud(seconds, 0.0)
	scene._update_hud()
	if scene.vinyl != null:
		scene.vinyl.on_combo(scene.score.current_combo if scene.score != null else 0)
		scene.vinyl.seek_for_test(seconds)
	scene._set_visual_pause(show_pause_menu)
	if show_pause_menu:
		scene.esc_menu.open_menu()
	elif scene.esc_menu != null and scene.esc_menu.is_open():
		scene.esc_menu.visible = false


func _condition(actual: Variant, operator: String, expected: Variant) -> bool:
	match operator:
		"equals": return actual == expected
		"notEquals": return actual != expected
		"contains": return actual is String and str(actual).contains(str(expected))
		"exists": return actual != null
		"gt": return actual != null and actual > expected
		"gte": return actual != null and actual >= expected
		"lt": return actual != null and actual < expected
		"lte": return actual != null and actual <= expected
		"in": return expected is Array and expected.has(actual)
	return false


func _wait_for_scene(scene_name: String, timeout_sec: float) -> Node:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var current := get_tree().current_scene
		if current != null and current.name.to_snake_case() == scene_name:
			return current
		await get_tree().process_frame
	return null


func _write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(value, "  ", false))
		file.close()


func _fail(message: String) -> void:
	push_error("[parity] FAIL %s" % message)
	await _finish(1)


func _finish(code: int) -> void:
	if _finishing:
		return
	_finishing = true
	if _fixtures != null:
		_fixtures.restore()
		_fixtures = null
	if AudioDirector.has_method("release_for_shutdown"):
		AudioDirector.release_for_shutdown()
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(code)
