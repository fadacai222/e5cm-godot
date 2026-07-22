extends SceneTree
## ALL COMBO / ALL PERFECT 六阶段动画与旧版契约。

const AUTOLOADS := [
	["AssetLoader", "res://autoload/asset_loader.gd"],
]

var _failures := 0
var _created: Array[Node] = []


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _near(value: float, expected: float, tolerance := 0.5) -> bool:
	return absf(value - expected) <= tolerance


func _viewport_color_stats(viewport: Viewport, rect: Rect2i) -> Dictionary:
	if RenderingServer.get_rendering_device() == null:
		return {}
	RenderingServer.force_draw()
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		return {}
	var clipped := rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return {}
	var total := 0
	var near_white := 0
	var sum := Vector3.ZERO
	for y in range(clipped.position.y, clipped.end.y, 4):
		for x in range(clipped.position.x, clipped.end.x, 4):
			var color := image.get_pixel(x, y)
			total += 1
			sum += Vector3(color.r, color.g, color.b)
			if color.r > 0.92 and color.g > 0.92 and color.b > 0.92:
				near_white += 1
	if total <= 0:
		return {}
	return {
		"average": Color(sum.x / total, sum.y / total, sum.z / total, 1.0),
		"near_white_ratio": float(near_white) / float(total),
		"samples": total,
	}


func _initialize() -> void:
	for entry in AUTOLOADS:
		if root.get_node_or_null(entry[0]) == null:
			var node: Node = load(entry[1]).new()
			node.name = entry[0]
			root.add_child(node)
			_created.append(node)
	await process_frame

	var host := Control.new()
	host.name = "AchievementTestHost"
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	await process_frame
	var viewport_size := root.get_viewport().get_visible_rect().size
	var test_background := ColorRect.new()
	test_background.name = "TestBlackBackground"
	test_background.color = Color.BLACK
	test_background.size = viewport_size
	test_background.z_index = -1000
	host.add_child(test_background)

	var hud := Control.new()
	hud.name = "DummyTopHud"
	hud.size = viewport_size
	hud.position = Vector2.ZERO
	hud.z_index = 100
	host.add_child(hud)
	var judge := Node2D.new()
	judge.name = "DummyJudgement"
	judge.position = Vector2.ZERO
	judge.z_index = 0
	host.add_child(judge)
	var hud_base_position := hud.position
	var hud_base_scale := hud.scale
	var hud_base_modulate := hud.modulate
	var hud_base_z := hud.z_index
	var judge_base_position := judge.position
	var judge_base_scale := judge.scale
	var judge_base_modulate := judge.modulate
	var judge_base_z := judge.z_index
	var judge_pivot := Vector2(viewport_size.x * 0.5, 210.0)
	var judge_base_pivot_global := judge.to_global(judge_pivot)

	var achievement_script: Script = load("res://fx/achievement_anim.gd")
	var combo: Control = achievement_script.new() as Control
	host.add_child(combo)
	await process_frame
	_check(combo.play("full_combo", hud, judge), "All Combo 原版素材可完整启动")
	var initial_state: Dictionary = combo.state_for_test()
	_check(_near(float(initial_state.get("total_duration", 0.0)), 5.1667, 0.001),
		"六阶段总时长恢复为原版约 5.1667 秒", str(initial_state))
	_check(combo.get_node_or_null("AchievementContent/AchievementBar") != null
		and combo.get_node_or_null("AchievementContent/AchievementMainGroup/AchievementSpectrum") != null
		and combo.get_node_or_null("AchievementContent/AchievementLabel") != null,
		"底板、50段频谱、主体和标签均为独立原版部件")
	var dim := combo.get_node("AchievementDim") as ColorRect
	var flash_layer := combo.get_node("AchievementFlash") as ColorRect
	_check(dim.size == viewport_size and flash_layer.size == viewport_size
		and _near(dim.color.a, 136.0 / 255.0, 0.001),
		"全程使用原版136/255黑色遮罩且爆闪层覆盖完整视口",
		"dim=%s alpha=%.4f flash=%s viewport=%s" % [dim.size, dim.color.a,
			flash_layer.size, viewport_size])

	var bar_texture: Texture2D = root.get_node("AssetLoader").tex(
		"UI-img/游戏界面/full_combo/bar.png")
	var board_texture: Texture2D = root.get_node("AssetLoader").tex(
		"UI-img/游戏界面/full_combo/board.png")
	var expected_bar_width := minf(float(bar_texture.get_width()) * 0.82,
		maxf(720.0, viewport_size.x * 0.86)) * 1.22
	var expected_board_width := minf(float(board_texture.get_width()) * 0.86,
		maxf(188.0, minf(viewport_size.x, viewport_size.y) * 0.38)) * 0.95
	_check(_near(float(initial_state.get("bar_width", 0.0)), expected_bar_width, 0.6)
		and _near(float(initial_state.get("board_width", 0.0)), expected_board_width, 0.6),
		"底板与 Board 使用原版响应式尺寸公式",
		"state=%s expected_bar=%.2f expected_board=%.2f" % [initial_state,
			expected_bar_width, expected_board_width])

	combo.seek_for_test(0.34)
	var bar := combo.get_node("AchievementContent/AchievementBar") as TextureRect
	var stage1_state: Dictionary = combo.state_for_test()
	_check(str(stage1_state.get("phase", "")) == "阶段1 底板入场"
		and _near(bar.rotation_degrees, 4.5, 0.01)
		and float(stage1_state.get("arrow_phase", 0.0)) > 0.0,
		"阶段1 固定4.5度斜角并播放底板内部循环箭头", str(stage1_state))
	combo.seek_for_test(0.05)
	_check(bar.position.x < -bar.size.x * 0.35,
		"底板从屏幕左侧大偏移回弹入场", str(bar.position))
	combo.seek_for_test(0.82)

	var main_group := combo.get_node("AchievementContent/AchievementMainGroup") as Control
	var board := main_group.get_node("AchievementBoard") as TextureRect
	var ring := main_group.get_node("AchievementRingLight") as TextureRect
	var wind := main_group.get_node("AchievementWind") as TextureRect
	var flash := combo.get_node("AchievementFlash") as ColorRect
	var stage2_state: Dictionary = combo.state_for_test()
	var spectrum_state: Dictionary = stage2_state.get("spectrum", {})
	_check(str(stage2_state.get("phase", "")) == "阶段2 Board入场"
		and main_group.visible and main_group.scale.x >= 0.95 and main_group.scale.x <= 1.28
		and float(spectrum_state.get("bars", 0)) == 50
		and float(spectrum_state.get("peak", 0.0)) > 0.0,
		"阶段2 主体回弹入场并启用50段动态假频谱", str(stage2_state))
	_check(_near(board.size.x, expected_board_width, 0.6)
		and ring.size.x > board.size.x and wind.size.x < ring.size.x,
		"Board/Ring/Wind 尺寸恢复原版层级而非过度放大",
		"board=%s ring=%s wind=%s" % [board.size, ring.size, wind.size])
	_check(_near(board.rotation_degrees, 0.82 * 57.0, 0.05)
		and _near(ring.rotation_degrees, 0.82 * 28.0, 0.05)
		and _near(wind.rotation_degrees, 0.82 * -96.0, 0.05)
		and flash.color.a > 0.0,
		"Board、Ring、Wind 使用原版57/28/-96度每秒转速并触发白色爆闪",
		"board=%.2f ring=%.2f wind=%.2f flash=%.3f" % [board.rotation_degrees,
			ring.rotation_degrees, wind.rotation_degrees, flash.color.a])

	combo.seek_for_test(1.40)
	var label := combo.get_node("AchievementContent/AchievementLabel") as TextureRect
	var label_target_width := float(combo.get("_label_target_width"))
	var label_target_height := float(combo.get("_label_target_height"))
	_check(label.visible and _near(label.rotation_degrees, 5.0, 0.01)
		and label.size.x > label_target_width * 0.60
		and label.size.x < label_target_width * 1.10
		and _near(label.size.y, label_target_height, 0.6)
		and label.modulate.a >= 178.0 / 255.0,
		"阶段3 Label 固定5度并以非等比横向展开",
		"size=%s target=(%.1f, %.1f) alpha=%.3f" % [label.size,
			label_target_width, label_target_height, label.modulate.a])

	combo.seek_for_test(4.32)
	var stage5_state: Dictionary = combo.state_for_test()
	_check(str(stage5_state.get("phase", "")) == "阶段5 整体收尾"
		and float(stage5_state.get("pixel_scale", 1.0)) > 1.5
		and float(stage5_state.get("content_alpha", 1.0)) < 1.0
		and label.size.x > label_target_width * 1.10,
		"阶段5 Label再放大且整个成就层像素化淡出", str(stage5_state))

	combo.seek_for_test(4.92)
	var stage6_state: Dictionary = combo.state_for_test()
	_check(bool(stage6_state.get("stage6_started", false))
		and str(stage6_state.get("phase", "")) == "阶段6 HUD回收"
		and hud.z_index > combo.z_index and judge.z_index > combo.z_index,
		"阶段6 将 HUD 与判定区提升到黑色遮罩上方独立回收", str(stage6_state))
	_check(hud.position.y < hud_base_position.y and hud.scale.x < 1.0
		and hud.modulate.a < hud_base_modulate.a,
		"顶部 HUD 向上、缩小并淡出",
		"position=%s scale=%s alpha=%.3f" % [hud.position, hud.scale, hud.modulate.a])
	_check(judge.position.y > judge_base_position.y and judge.scale.x < 1.0
		and judge.modulate.a < judge_base_modulate.a,
		"判定区向下、缩小并淡出",
		"position=%s scale=%s alpha=%.3f" % [judge.position, judge.scale, judge.modulate.a])

	combo.seek_for_test(5.1666)
	var judge_end_pivot_global := judge.to_global(judge_pivot)
	_check(_near(hud.position.y - hud_base_position.y, -96.0, 0.1)
		and _near(hud.scale.x / hud_base_scale.x, 0.96, 0.001)
		and _near(judge_end_pivot_global.y - judge_base_pivot_global.y, 36.0, 0.1)
		and _near(judge.scale.x / judge_base_scale.x, 0.82, 0.001),
		"阶段6终点精确回收：HUD上移96px/缩至0.96，判定区下移36px/缩至0.82",
		"hud_pos=%s hud_scale=%s judge_pivot_delta=%s judge_scale=%s" % [hud.position,
			hud.scale, judge_end_pivot_global - judge_base_pivot_global, judge.scale])

	combo.abort_and_restore()
	await process_frame
	_check(hud.position == hud_base_position and hud.scale == hud_base_scale
		and hud.modulate == hud_base_modulate and hud.z_index == hud_base_z
		and judge.position == judge_base_position and judge.scale == judge_base_scale
		and judge.modulate == judge_base_modulate and judge.z_index == judge_base_z,
		"异常中断会完整恢复 HUD 与判定区状态")

	var perfect: Control = achievement_script.new() as Control
	host.add_child(perfect)
	await process_frame
	_check(perfect.play("full_perfect"), "All Perfect 原版素材可完整启动")
	perfect.seek_for_test(1.10)
	await process_frame
	await process_frame
	var perfect_state: Dictionary = perfect.state_for_test()
	var perfect_bar := perfect.get_node("AchievementContent/AchievementBar") as TextureRect
	var perfect_bar_rect := Rect2i(
		Vector2i(floori(perfect_bar.global_position.x), floori(perfect_bar.global_position.y)),
		Vector2i(ceili(perfect_bar.size.x), ceili(perfect_bar.size.y)))
	var perfect_bar_stats := _viewport_color_stats(root.get_viewport(), perfect_bar_rect)
	var perfect_label := perfect.get_node("AchievementContent/AchievementLabel") as TextureRect
	_check((perfect_state.get("main_color", Color.BLACK) as Color).is_equal_approx(Color8(233, 146, 32))
		and perfect_label.texture.resource_path.contains("full_perfect"),
		"All Perfect 使用橙金主题色和独立素材目录", str(perfect_state))
	_check(not (perfect_state.get("main_color", Color.BLACK) as Color).is_equal_approx(
		initial_state.get("main_color", Color.BLACK) as Color),
		"All Combo 与 All Perfect 频谱主题色互相独立")
	var rendered_average := perfect_bar_stats.get("average", Color.BLACK) as Color
	_check(perfect_bar_stats.is_empty() or (
		float(perfect_bar_stats.get("near_white_ratio", 1.0)) < 0.08
		and rendered_average.r > rendered_average.b * 2.0),
		"All Perfect 底板实际帧缓冲保持橙金色，不得整块白屏",
		str(perfect_bar_stats))
	perfect.abort_and_restore()
	await process_frame

	var invalid: Control = achievement_script.new() as Control
	host.add_child(invalid)
	await process_frame
	_check(not invalid.play("ordinary"), "普通结算不会误启动成就动画")
	invalid.queue_free()

	host.queue_free()
	await process_frame
	for i in range(_created.size() - 1, -1, -1):
		var node := _created[i]
		if is_instance_valid(node) and node.get_parent() == root:
			root.remove_child(node)
			node.free()
	await process_frame
	print("ALL ACHIEVEMENT ANIMATION PARITY TESTS PASSED" if _failures == 0 else
		"%d ACHIEVEMENT ANIMATION PARITY TEST(S) FAILED" % _failures)
	quit(_failures)
