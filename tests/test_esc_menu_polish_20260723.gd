extends SceneTree
## 2026-07-23 ESC 背景、挑战层级与 Combo 箭头叠加层专项契约。

var _failures := 0


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _initialize() -> void:
	var settings = root.get_node("SettingsStore")
	settings.persist_enabled = false
	root.get_node("ProfileStore").persist_enabled = false
	root.get_node("RewardService").persist_enabled = false
	root.get_node("ChallengeService").persist_enabled = false
	settings.performance_mode = false
	settings.background_mode = "图片"
	settings.image_slideshow = false
	settings.video_background_name = ""
	settings.background_brightness_level = 0

	var menu = load("res://ui/esc_menu.gd").new(true)
	root.add_child(menu)
	await process_frame
	menu.call("_set_tab", 1)
	await process_frame
	var images: Array = menu.get("_background_images")
	var videos: Array = menu.get("_background_videos")
	var body := menu.get_node("ModernMenu/ContentPanel/ContentBody") as Control
	var canvas := body.get_node_or_null("LivePreview/PreviewCanvas") as Control
	var preview := canvas.get_node_or_null("PreviewImage") as TextureRect if canvas else null
	var brightness_dim := canvas.get_node_or_null("BrightnessDim") as ColorRect if canvas else null
	var strip := body.get_node_or_null("LivePreview/BackgroundThumbnailStrip") as Control
	_check(images.size() > 1,
		"图片背景页扫描到多张原版背景供用户切换", str(images))
	_check(preview != null and preview.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED \
		and canvas.clip_contents,
		"图片实时预览按完整比例缩小进预览框，不再裁掉画面边缘")
	_check(brightness_dim != null and is_zero_approx(brightness_dim.color.a) \
		and is_zero_approx(float(settings.call("background_dim_alpha"))),
		"背景亮度 100% 完全移除黑色蒙版")
	_check(strip != null and strip.get_child_count() >= 2,
		"背景预览下方显示多图缩略选择带")
	if images.size() > 1:
		var before := str(settings.image_background_name)
		menu.call("_step_image_background", 1)
		_check(str(settings.image_background_name) != before,
			"图片背景左右切换会写入独立选择项并刷新预览")
	_check(videos.size() > 1,
		"视频背景页扫描到多段原版视频供用户切换", str(videos))
	if videos.size() > 1:
		var before_video := str(settings.video_background_name)
		menu.call("_step_video_background", 1)
		_check(str(settings.video_background_name) != before_video,
			"视频背景左右切换会写入独立选择项")

	var gameplay_probe = load("res://scenes/gameplay/gameplay.gd").new()
	gameplay_probe.set("payload", {"cover": ""})
	var resolved := str(gameplay_probe.call("_resolve_image_background_path"))
	_check(not resolved.is_empty() and resolved.ends_with(str(settings.image_background_name)),
		"Gameplay 图片模式读取用户选择的背景，而不是固定使用歌曲封面", resolved)
	var resolved_video := str(gameplay_probe.call("_find_gameplay_video_path"))
	_check(not resolved_video.is_empty() and resolved_video.ends_with(str(settings.video_background_name)),
		"Gameplay 视频模式读取用户选择的视频背景", resolved_video)
	gameplay_probe.free()

	menu.call("_set_tab", 5)
	await process_frame
	var dashboard := body.get_node_or_null("ChallengeDashboard") as Control
	var daily := dashboard.get_node_or_null("DailyColumn") as Control if dashboard else null
	var weekly := dashboard.get_node_or_null("WeeklyColumn") as Control if dashboard else null
	_check(daily != null and weekly != null and daily.size.x > weekly.size.x * 1.35,
		"今日挑战以宽主栏呈现，周常缩窄为次级信息")
	var daily_frame = daily.get_node_or_null("ColumnFrame") if daily else null
	var weekly_frame = weekly.get_node_or_null("ColumnFrame") if weekly else null
	_check(daily_frame != null and weekly_frame != null \
		and float(daily_frame.scanline_color.a) > float(weekly_frame.scanline_color.a),
		"每日主任务的亮度/扫描线强于周常，形成清晰视觉焦点")

	var field = load("res://scenes/gameplay/note_field.gd").new()
	root.add_child(field)
	await process_frame
	field.call("setup", 5, 4.0, false)
	field.call("set_combo_gold_fx_level", 2)
	field.call("set_combo_lane_fx_enabled", true)
	field.call("set_combo_arrow_overlay_enabled", false)
	_check(not bool(field.call("is_combo_gold_fx_enabled")) \
		and bool(field.call("is_combo_lane_fx_enabled")),
		"箭头 Combo 叠加层可单独关闭且不误伤轨道描边粒子")
	field.call("set_combo_arrow_overlay_enabled", true)
	_check(bool(field.call("is_combo_gold_fx_enabled")),
		"箭头 Combo 叠加层可按当前档位即时恢复")

	for node in [field, menu]:
		if is_instance_valid(node) and node.get_parent() == root:
			root.remove_child(node)
			node.free()
	if root.get_node("AudioDirector").has_method("release_for_shutdown"):
		root.get_node("AudioDirector").release_for_shutdown()
	await create_timer(0.15).timeout
	print("ALL ESC MENU POLISH TESTS PASSED" if _failures == 0 else
		"%d ESC MENU POLISH TEST(S) FAILED" % _failures)
	quit(_failures)
