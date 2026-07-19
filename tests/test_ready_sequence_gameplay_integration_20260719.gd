extends SceneTree
## Gameplay 集成回归：黑幕固定在背景与 UI 之间，判定区/HUD 始终满亮度。

const AUTOLOADS := [
	["AssetLoader", "res://autoload/asset_loader.gd"],
	["SharedVideoBackground", "res://autoload/shared_video_background.gd"],
	["SettingsStore", "res://autoload/settings_store.gd"],
	["GameState", "res://autoload/game_state.gd"],
	["ProfileStore", "res://autoload/profile_store.gd"],
	["SongLibrary", "res://autoload/song_library.gd"],
	["AudioDirector", "res://autoload/audio_director.gd"],
	["SceneRouter", "res://autoload/scene_router.gd"],
]

var _failures := 0
var _created: Array[Node] = []


func _check(condition: bool, label: String, detail := "") -> void:
	if condition:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _initialize() -> void:
	for entry in AUTOLOADS:
		if root.get_node_or_null(entry[0]) == null:
			var node: Node = load(entry[1]).new()
			node.name = entry[0]
			root.add_child(node)
			_created.append(node)
	await process_frame

	var settings = root.get_node("SettingsStore")
	settings.persist_enabled = false
	settings.show_ready_animation = true
	settings.autoplay = true
	settings.background_mode = "图片"
	settings.background_brightness_level = 0
	root.get_node("ProfileStore").persist_enabled = false
	root.get_node("GameState").persist_credits = false

	var base := "res://songs/竞速/club/SPEED_CLUB#12356_1612#11"
	root.get_node("SceneRouter").payload = {
		"sm": base.path_join("12356_1612 [SPEED_CLUB].sm"),
		"mp3": "",
		"cover": base.path_join("bann.jpg"),
		"name": "12356_1612",
		"star": 11,
		"mode": "竞速",
		"submode": "club",
		"sm_key": "songs/竞速/club/SPEED_CLUB#12356_1612#11/12356_1612 [SPEED_CLUB].sm",
		"prefer_double": true,
		"couple": false,
		"target_charttype": "pump-double",
	}

	var gameplay := (load("res://scenes/gameplay/gameplay.tscn") as PackedScene).instantiate() as Control
	root.add_child(gameplay)
	for _i in 60:
		if gameplay.get("ready_anim") != null and gameplay.get("note_field") != null:
			break
		await process_frame

	var ready = gameplay.get("ready_anim") as Control
	var hud := gameplay.get_node("LegacyTopHud") as Control
	var note_field = gameplay.get("note_field") as Node2D
	if ready == null or note_field == null:
		_check(false, "Gameplay 准备层与判定区成功建立")
		root.remove_child(gameplay)
		gameplay.free()
		quit(_failures)
		return
	var background := gameplay.get_node("GameplayBackground") as TextureRect
	var background_dim := gameplay.get_node("BackgroundDim") as ColorRect
	var note_region := gameplay.get_node("NoteFieldRegion") as Control

	_check(ready.visible and absf(background_dim.color.a - 1.0) <= 0.001,
		"加载页切入 Gameplay 的首帧由底层黑幕锁定全黑")
	_check(ready.get_node_or_null("SceneDim") == null,
		"READY 顶层不再放置会压暗 UI 的全屏蒙版")
	_check(background.z_index < background_dim.z_index
		and background_dim.z_index < note_region.z_index
		and note_region.z_index < hud.z_index
		and hud.z_index < ready.z_index,
		"层级固定为背景 < 黑幕 < 判定区 < 血条 < READY/GO",
		"bg=%d dim=%d note=%d hud=%d ready=%d" % [
			background.z_index, background_dim.z_index, note_region.z_index,
			hud.z_index, ready.z_index])
	_check(hud.modulate.a == 0.0 and note_field.modulate.a == 0.0,
		"谱面解析期间 HUD 与判定区不会抢先闪现")

	for _i in 180:
		if bool(gameplay.get("_chart_ready")):
			break
		await process_frame
	_check(bool(gameplay.get("_chart_ready")), "测试谱面成功载入")

	ready.call("seek_for_test", 1.45)
	gameplay.call("_update_ready_reveal")
	_check(absf(background_dim.color.a) <= 0.001,
		"背景先完整满亮度出现", str(background_dim.color.a))

	ready.call("seek_for_test", 2.45)
	gameplay.call("_update_ready_reveal")
	_check(absf(background_dim.color.a - 0.70) <= 0.01,
		"底层黑幕随后缓慢稳定到 70%", str(background_dim.color.a))

	ready.call("seek_for_test", 2.54)
	gameplay.call("_update_ready_reveal")
	var before: float = float(note_field.modulate.a)
	ready.call("seek_for_test", 2.55)
	gameplay.call("_update_ready_reveal")
	var after: float = float(note_field.modulate.a)
	_check(before == 0.0 and after == 1.0 and note_field.scale == Vector2.ONE,
		"判定区到点直接满亮度显示且不缩放",
		"before=%.3f after=%.3f" % [before, after])
	_check(background_dim.z_index < note_region.z_index and note_field.modulate == Color.WHITE,
		"70% 黑幕只压背景，不压暗判定区")

	ready.call("seek_for_test", 3.30)
	gameplay.call("_update_ready_reveal")
	_check(hud.modulate == Color.WHITE and hud.position.y > -260.0 and hud.position.y < 0.0,
		"顶部血条满亮度从屏幕外缓慢落入", str(hud.position))

	ready.call("seek_for_test", 7.65)
	gameplay.call("_update_ready_reveal")
	_check(background_dim.color.a > 0.45 and background_dim.color.a < 0.70,
		"右退期间黑幕平滑交还给正式背景亮度", str(background_dim.color.a))

	ready.call("seek_for_test", 8.15)
	gameplay.call("_update_ready_reveal")
	_check(absf(background_dim.color.a - 0.45) <= 0.01
		and hud.position.y == 0.0 and hud.modulate == Color.WHITE
		and note_field.modulate == Color.WHITE,
		"右退完成后恢复正式游戏亮度和完整 UI")

	root.remove_child(gameplay)
	gameplay.free()
	for node in _created:
		if is_instance_valid(node) and node.get_parent() != null:
			node.get_parent().remove_child(node)
			node.free()

	print("ALL READY GAMEPLAY INTEGRATION TESTS PASSED" if _failures == 0 else
		"%d READY GAMEPLAY INTEGRATION TEST(S) FAILED" % _failures)
	quit(_failures)
