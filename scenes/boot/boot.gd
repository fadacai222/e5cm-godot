extends Control
## 原版单图启动幻灯片：黑底居中、2 秒渐显、1 秒停留、1.5 秒渐隐。

const STARTUP_IMAGE := "backmovies/开场动画/001.png"
const FADE_IN_SEC := 2.0
const HOLD_SEC := 1.0
const FADE_OUT_SEC := 1.5
const RewardCatalogScript := preload("res://core/reward_catalog.gd")

@onready var splash: TextureRect = $SplashImage
var _finished := false
var _sequence_tween: Tween


func _ready() -> void:
	if OS.get_environment("E5CM_RELEASE_ASSET_PROBE") == "1":
		call_deferred("_run_release_asset_probe")
		return
	if root_has_status_hud():
		StatusHud.visible = false
	PublicSystemMenu.visible = false
	splash.texture = AssetLoader.tex(STARTUP_IMAGE)
	splash.modulate.a = 0.0
	if splash.texture == null or OS.get_environment("E5CM_SKIP_BOOT") == "1":
		_finish()
		return
	_play_sequence()


func _release_song_library_probe() -> Dictionary:
	var result := {
		"sidecar_exists": false,
		"embedded_dev_index_absent": true,
		"counts_match": false,
		"paths_exist": false,
		"expected_total": 0,
		"loaded_total": 0,
		"mode_count": 0,
		"failed_keys": [],
	}
	if not OS.has_feature("e5cm_release"):
		result["sidecar_exists"] = true
		result["counts_match"] = true
		result["paths_exist"] = true
		return result

	var sidecar_path := OS.get_executable_path().get_base_dir().path_join(
		"release-song-index.json").replace("\\", "/")
	result["sidecar_exists"] = FileAccess.file_exists(sidecar_path)
	result["embedded_dev_index_absent"] = not FileAccess.file_exists(
		"res://assets/e5cm_runtime/song_index.json")
	if not bool(result["sidecar_exists"]):
		return result

	var parsed = JSON.parse_string(FileAccess.get_file_as_string(sidecar_path))
	if not parsed is Dictionary:
		return result
	var songs_by_key = parsed.get("songsByKey", {})
	if not songs_by_key is Dictionary:
		return result

	var failed_keys: Array[String] = []
	var loaded_total := 0
	var counts_match := true
	var paths_exist := true
	for raw_key in (songs_by_key as Dictionary).keys():
		var key := str(raw_key)
		var key_parts := key.split("/", false, 1)
		var expected_entries = (songs_by_key as Dictionary).get(raw_key, [])
		if key_parts.size() != 2 or not expected_entries is Array:
			counts_match = false
			failed_keys.append(key)
			continue
		var loaded: Array = SongLibrary.get_songs(str(key_parts[0]), str(key_parts[1]))
		loaded_total += loaded.size()
		if loaded.size() != (expected_entries as Array).size():
			counts_match = false
			failed_keys.append("%s:%d!=%d" % [key, loaded.size(), (expected_entries as Array).size()])
		for raw_song in loaded:
			if not raw_song is Dictionary:
				paths_exist = false
				continue
			var song: Dictionary = raw_song
			for field in ["sm", "mp3", "cover"]:
				var path := str(song.get(field, ""))
				if path.is_empty() or not FileAccess.file_exists(path):
					paths_exist = false
					if failed_keys.size() < 20:
						failed_keys.append("%s:%s" % [key, field])

	var expected_total := int(parsed.get("songVariantCount", 0))
	result["expected_total"] = expected_total
	result["loaded_total"] = loaded_total
	result["mode_count"] = (songs_by_key as Dictionary).size()
	result["counts_match"] = counts_match and loaded_total == expected_total
	result["paths_exist"] = paths_exist
	result["failed_keys"] = failed_keys
	return result


func _run_release_asset_probe() -> void:
	await get_tree().process_frame
	var song_probe := _release_song_library_probe()
	var checks := {
		"startup_texture": AssetLoader.tex(STARTUP_IMAGE) != null,
		"song_select_background": AssetLoader.tex_key("背景_选歌") != null,
		"player_button_texture": AssetLoader.tex_key("1P按钮") != null,
		"arrow_atlas": not AssetLoader.arrow_atlas("原版默认").is_empty(),
		"key_atlas": not AssetLoader.key_atlas("原版默认").is_empty(),
		"judge_atlas": not AssetLoader.judge_atlas("原版默认").is_empty(),
		"number_atlas": not AssetLoader.number_atlas("原版默认").is_empty(),
		"key_effect_atlas": not AssetLoader.key_effect_atlas("原版默认").is_empty(),
		"blood_bar_atlas": not AssetLoader.blood_bar_atlas().is_empty(),
		"judge_text_atlas": not AssetLoader.judge_text_atlas().is_empty(),
		"player_select_video": AssetLoader.resource_exists(AssetLoader.res_path("视频_玩家")),
		"release_feature_enabled": OS.has_feature("e5cm_release"),
		"release_sidecar_index": bool(song_probe.get("sidecar_exists", false)),
		"embedded_dev_song_index_absent": bool(song_probe.get(
			"embedded_dev_index_absent", false)),
		"release_song_counts_match_sidecar": bool(song_probe.get("counts_match", false)),
		"release_song_paths_exist": bool(song_probe.get("paths_exist", false)),
		"milestone_sound_removed": not AssetLoader.resource_exists(
			"res://assets/e5cm_runtime/冷资源/Buttonsound/点击-增益5.mp3"),
		"reward_catalog_v5": RewardCatalogScript.CATALOG_VERSION == 5
			and RewardCatalogScript.new().validate_catalog().is_empty(),
		"reward_identity_component": ResourceLoader.exists("res://ui/player_identity_view.gd"),
		"reward_center_component": ResourceLoader.exists("res://ui/reward_center.gd"),
		"reward_presenter": get_node_or_null("/root/RewardPresenter") != null,
		"reward_milestones": get_node_or_null("/root/RewardMilestoneService") != null,
	}
	var sound_keys := [
		"音乐_UI", "音乐_开始", "音乐_show", "音乐_devil", "音乐_remix", "音乐_club",
		"刷卡音效", "开始游戏", "准备就绪音效", "结算音效", "gameover",
	]
	for sound_key in sound_keys:
		var path := AssetLoader.sound(sound_key)
		checks["sound_%s" % sound_key] = not path.is_empty() \
				and ResourceLoader.exists(path) \
				and load(path) is AudioStream
	var failed: Array[String] = []
	for key in checks:
		if not bool(checks[key]):
			failed.append(str(key))
	print("E5CM_RELEASE_SONG_PROBE=%s" % JSON.stringify(song_probe))
	print("E5CM_RELEASE_ASSET_PROBE=%s" % JSON.stringify(checks))
	if failed.is_empty():
		print("E5CM_RELEASE_ASSET_PROBE_PASSED")
		get_tree().quit(0)
	else:
		printerr("E5CM_RELEASE_ASSET_PROBE_FAILED=%s" % ",".join(failed))
		get_tree().quit(41)


func root_has_status_hud() -> bool:
	return get_node_or_null("/root/StatusHud") != null


func _play_sequence() -> void:
	_sequence_tween = create_tween()
	_sequence_tween.tween_property(splash, "modulate:a", 1.0, FADE_IN_SEC).set_trans(Tween.TRANS_LINEAR)
	_sequence_tween.tween_interval(HOLD_SEC)
	_sequence_tween.tween_property(splash, "modulate:a", 0.0, FADE_OUT_SEC).set_trans(Tween.TRANS_LINEAR)
	await _sequence_tween.finished
	_sequence_tween = null
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if root_has_status_hud():
		StatusHud.visible = true
	SceneRouter.change_to("coin", {}, false)


func _unhandled_input(event: InputEvent) -> void:
	# 原版启动幻灯片中 ESC 直接退出程序，不作为跳过键。
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_tree().quit()


func _exit_tree() -> void:
	if _sequence_tween != null and _sequence_tween.is_valid():
		_sequence_tween.kill()
	_sequence_tween = null
	if root_has_status_hud():
		StatusHud.visible = true
