extends SceneTree
## 游戏中切换箭头皮肤回归测试：判定序列帧不得丢失，Hold 平铺缓存不得串皮肤。
## 运行：Godot_v4.6.2-stable_win64_console.exe --headless --path . --script res://tests/test_runtime_arrow_skin_switch_20260723.gd

var _failures := 0


func _frame_anim_count(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		var script := child.get_script() as Script
		if script != null and script.resource_path == "res://fx/frame_anim.gd" \
				and not child.is_queued_for_deletion():
			count += 1
	return count


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _initialize() -> void:
	var settings := root.get_node_or_null("SettingsStore")
	var asset_loader := root.get_node_or_null("AssetLoader")
	if settings == null or asset_loader == null:
		print("  FAIL  项目自动加载器缺失")
		quit(1)
		return
	settings.persist_enabled = false
	await process_frame

	print("== Runtime arrow skin switch regression ==")
	var field: Node = load("res://scenes/gameplay/note_field.gd").new()
	root.add_child(field)

	# “马赛克”使用 a_00000.png 这类 5 位帧编号；运行时仍必须解析出四方向动画组。
	var mosaic_fx_atlas: Dictionary = asset_loader.key_effect_atlas("马赛克")
	var mosaic_groups: Dictionary = field.call("_build_fx_groups_from_atlas", mosaic_fx_atlas)
	var all_roles_present := true
	for role in ["hand", "lb", "lt", "cc"]:
		all_roles_present = all_roles_present and not (mosaic_groups.get(role, []) as Array).is_empty()
	_check(all_roles_present,
		"5 位帧编号皮肤仍保留完整判定动画",
		"roles=%s" % str(mosaic_groups.keys()))
	settings.arrow_skin = "马赛克"
	field.call("setup", 5, 4.0, false)
	field.call("spawn_hit_effect", 0)
	_check(_frame_anim_count(field) > 0,
		"游戏中切到 5 位编号皮肤后仍能生成轨道判定动画")

	# 历史皮肤的判定/数字图集使用不同 pf 编号，加载层必须统一提供语义别名。
	var gameplay_probe: Control = load("res://scenes/gameplay/gameplay.gd").new()
	for skin_name in ["几何", "05", "02", "马克笔"]:
		var judge_atlas: Dictionary = asset_loader.judge_atlas(skin_name)
		var number_atlas: Dictionary = asset_loader.number_atlas(skin_name)
		_check(judge_atlas.get("judge_perfect") is Texture2D \
				and judge_atlas.get("judge_cool") is Texture2D \
				and judge_atlas.get("judge_good") is Texture2D \
				and judge_atlas.get("judge_miss") is Texture2D \
				and judge_atlas.get("judge_combo") is Texture2D,
			"%s 判定图集提供统一语义别名" % skin_name,
			"keys=%s" % str(judge_atlas.keys()))
		_check(number_atlas.get("number_0") is Texture2D \
				and number_atlas.get("number_9") is Texture2D \
				and number_atlas.get("number_x") is Texture2D,
			"%s Combo 数字图集提供统一语义别名" % skin_name,
			"keys=%s" % str(number_atlas.keys()))
		gameplay_probe.set("_combo_judge_atlas", judge_atlas)
		gameplay_probe.set("_combo_number_atlas", number_atlas)
		_check(gameplay_probe.call("_combo_texture_for_test", "judge", "perfect") is Texture2D \
				and gameplay_probe.call("_combo_texture_for_test", "word", "combo") is Texture2D \
				and gameplay_probe.call("_combo_texture_for_test", "digit", "1") is Texture2D,
			"%s Gameplay 可实际显示判定与 Combo 动画" % skin_name)
		settings.arrow_skin = skin_name
		field.call("setup", 5, 4.0, false)
		var effect_count_before := _frame_anim_count(field)
		field.call("spawn_hit_effect", 2)
		_check(_frame_anim_count(field) > effect_count_before,
			"%s 轨道击中序列帧可实际创建" % skin_name)
	gameplay_probe.free()

	# Hold 平铺缓存键必须区分源皮肤；否则换皮后头尾已更新，身体仍复用旧纹理。
	var default_arrow: Dictionary = asset_loader.arrow_atlas("原版默认")
	var skin01_arrow: Dictionary = asset_loader.arrow_atlas("01")
	var default_repeat := default_arrow.get("arrow_repeat_lb") as Texture2D
	var skin01_repeat := skin01_arrow.get("arrow_repeat_lb") as Texture2D
	_check(default_repeat != null and skin01_repeat != null,
		"测试皮肤包含 Hold 身体纹理")
	if default_repeat != null and skin01_repeat != null:
		var default_tiled: Texture2D = field.call(
			"_tiled_hold_texture", default_repeat, "1:lb", 96, 160)
		var skin01_tiled: Texture2D = field.call(
			"_tiled_hold_texture", skin01_repeat, "1:lb", 96, 160)
		_check(default_tiled != skin01_tiled,
			"切换皮肤后 Hold 身体不复用旧皮肤缓存")

	field.free()
	if _failures == 0:
		print("\nALL RUNTIME ARROW SKIN SWITCH TESTS PASSED")
		quit(0)
	else:
		print("\n%d RUNTIME ARROW SKIN SWITCH TEST(S) FAILED" % _failures)
		quit(1)
