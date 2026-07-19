extends SceneTree
## Combo 断连逐级降档、DIY 段位与三模式进度条回归。

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
var _decay_levels: Array[int] = []


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _on_combo_fx_level_changed(level: int) -> void:
	_decay_levels.append(level)


func _profile_fixture() -> Dictionary:
	return {
		"昵称": "DIY玩家",
		"头像文件": "",
		"统计": {},
		"进度": {
			"最大等级": 70,
			"经验版本": 2,
			"段位": "",
			"花式": {"等级": 1, "经验": 0.0, "累计歌曲": 0, "累计首数": 0},
			"竞速": {"等级": 1, "经验": 0.0, "累计歌曲": 0, "累计首数": 0},
			"diy": {"等级": 19, "经验": 7.0, "累计歌曲": 21, "累计首数": 7},
		},
	}


func _initialize() -> void:
	for entry in AUTOLOADS:
		if root.get_node_or_null(entry[0]) == null:
			var node: Node = load(entry[1]).new()
			node.name = entry[0]
			root.add_child(node)
			_created.append(node)
	await process_frame
	root.get_node("SettingsStore").persist_enabled = false
	root.get_node("GameState").persist_credits = false
	var profile_store = root.get_node("ProfileStore")
	profile_store.persist_enabled = false
	profile_store.profile = _profile_fixture()
	profile_store.call("refresh_rank_cache", false)

	_check(profile_store.has_method("get_highest_mode_level_for_display")
		and int(profile_store.call("get_highest_mode_level_for_display")) == 19
		and int(profile_store.call("get_rank_index_for_display")) == 2
		and str(profile_store.call("get_rank_label_for_display")) == "2段"
		and str(profile_store.profile.get("进度", {}).get("段位", "")) == "2",
		"DIY 19 级参与段位计算并显示为 2 段",
		"rank=%s" % str(profile_store.call("get_rank_label_for_display")))

	var milestone_fx = load("res://fx/combo_milestone_fx.gd").new()
	root.add_child(milestone_fx)
	if milestone_fx.has_signal("level_changed"):
		milestone_fx.connect("level_changed", _on_combo_fx_level_changed)
	milestone_fx.call("play_milestone", 300, false)
	var decay_contract: bool = milestone_fx.has_method("start_decay") \
		and milestone_fx.has_method("is_decaying") \
		and milestone_fx.has_method("decay_level_hold_seconds_for_test") \
		and milestone_fx.has_method("decay_final_fade_seconds_for_test")
	_check(decay_contract, "百连层提供断连逐级降档状态机")
	if decay_contract:
		milestone_fx.call("start_decay")
		var step := float(milestone_fx.call("decay_level_hold_seconds_for_test"))
		var fade := float(milestone_fx.call("decay_final_fade_seconds_for_test"))
		_check(bool(milestone_fx.call("is_decaying"))
			and int(milestone_fx.call("milestone_level_for_test")) == 3,
			"300 Combo 断连后先保留当前第三档，不瞬间清空")
		milestone_fx.call("_process", step + 0.01)
		_check(int(milestone_fx.call("milestone_level_for_test")) == 2
			and bool(milestone_fx.call("is_active")),
			"断连后第三档降为第二档")
		milestone_fx.call("_process", step + 0.01)
		_check(int(milestone_fx.call("milestone_level_for_test")) == 1
			and bool(milestone_fx.call("is_active")),
			"断连后第二档降为第一档")
		milestone_fx.call("_process", step + fade * 0.5)
		_check(bool(milestone_fx.call("is_active"))
			and float(milestone_fx.call("decay_visibility_for_test")) > 0.0
			and float(milestone_fx.call("decay_visibility_for_test")) < 1.0,
			"第一档结束后平滑淡出，不突然消失")
		milestone_fx.call("_process", fade + 0.05)
		_check(not bool(milestone_fx.call("is_active"))
			and int(milestone_fx.call("milestone_level_for_test")) == 0
			and _decay_levels == [3, 2, 1, 0],
			"断连完整按 3→2→1→0 降档并同步档位信号",
			str(_decay_levels))
		milestone_fx.call("play_milestone", 300, false)
		milestone_fx.call("start_decay")
		milestone_fx.call("_process", step + 0.01)
		milestone_fx.call("play_milestone", 300, true)
		_check(not bool(milestone_fx.call("is_decaying"))
			and int(milestone_fx.call("milestone_level_for_test")) == 3
			and is_equal_approx(float(milestone_fx.call("decay_visibility_for_test")), 1.0)
			and float(milestone_fx.call("global_gold_intensity_for_test")) < 0.8,
			"降档途中重新触发里程碑会取消衰减并按最新性能模式恢复")
		milestone_fx.call("stop_effect")

	var menu: Node = load("res://ui/esc_menu.gd").new(true)
	root.add_child(menu)
	await process_frame
	menu.call("open_menu")
	menu.call("_set_tab", 4)
	await process_frame
	var content_body := menu.get_node_or_null("ModernMenu/ContentPanel/ContentBody") as Control
	var esc_diy_bar := content_body.get_node_or_null(
		"ProfileProgressCard/diyProgress/diyExperienceProgress") if content_body else null
	var esc_diy_level := content_body.get_node_or_null(
		"ProfileProgressCard/diyProgress/Level") as Label if content_body else null
	var esc_rank_label := content_body.get_node_or_null(
		"ProfileProgressCard/ProfileRankLabel") as Label if content_body else null
	_check(esc_rank_label != null and esc_rank_label.text == "2段",
		"ESC 段位文字跟随 DIY 19 级更新为 2 段",
		esc_rank_label.text if esc_rank_label else "missing")
	_check(esc_diy_bar != null and esc_diy_level != null and esc_diy_level.text.contains("19"),
		"ESC 用户信息页显示 DIY 第三进度条与真实等级",
		esc_diy_level.text if esc_diy_level else "missing")
	profile_store.set_mode_progress_preview("DIY", {
		"等级": 20, "经验": 3.0, "累计歌曲": 22, "累计首数": 8,
	})
	await process_frame
	await process_frame
	var refreshed_esc_diy_level := content_body.get_node_or_null(
		"ProfileProgressCard/diyProgress/Level") as Label if content_body else null
	_check(refreshed_esc_diy_level != null and refreshed_esc_diy_level.text.contains("20"),
		"ESC 用户信息页在打开状态下实时同步 DIY 经验预览",
		refreshed_esc_diy_level.text if refreshed_esc_diy_level else "missing")
	profile_store.clear_mode_progress_preview("DIY")
	await process_frame

	var profile_scene := (load("res://scenes/profile/profile.tscn") as PackedScene).instantiate()
	root.add_child(profile_scene)
	await process_frame
	await process_frame
	var profile_diy_bar := profile_scene.get_node_or_null("DiyExperienceProgress") as ProgressBar
	var profile_diy_label := profile_scene.get_node_or_null("DiyLevelLabel") as Label
	var profile_diy_value := profile_scene.get_node_or_null("DiyExpValue") as Label
	var profile_rank_badge := profile_scene.get_node_or_null("RankBadge") as TextureRect
	_check(profile_rank_badge != null and profile_rank_badge.texture != null
		and profile_rank_badge.texture.resource_path.replace("\\", "/").contains("/等级/2.png"),
		"磁卡登录后的个人资料段位徽章跟随 DIY 19 级切换到二段",
		profile_rank_badge.texture.resource_path \
			if profile_rank_badge != null and profile_rank_badge.texture != null else "missing")
	_check(profile_diy_bar != null and profile_diy_label != null and profile_diy_value != null
		and profile_diy_label.text == "DIY经验值："
		and profile_diy_value.text == "Lv. 19"
		and profile_diy_bar.value > 0.0,
		"磁卡登录后的个人资料页显示 DIY 第三进度条",
		"label=%s value=%s bar=%s" % [
			profile_diy_label.text if profile_diy_label else "missing",
			profile_diy_value.text if profile_diy_value else "missing",
			profile_diy_bar.value if profile_diy_bar else -1.0,
		])

	for node in [profile_scene, menu, milestone_fx]:
		if is_instance_valid(node) and node.get_parent() == root:
			root.remove_child(node)
			node.free()
	if root.get_node("AudioDirector").has_method("release_for_shutdown"):
		root.get_node("AudioDirector").release_for_shutdown()
	await create_timer(0.2).timeout
	for i in range(_created.size() - 1, -1, -1):
		var node := _created[i]
		if is_instance_valid(node) and node.get_parent() == root:
			root.remove_child(node)
			node.free()
	await process_frame
	print("ALL COMBO DECAY/DIY RANK/PROGRESS TESTS PASSED" if _failures == 0 else
		"%d COMBO DECAY/DIY RANK/PROGRESS TEST(S) FAILED" % _failures)
	quit(_failures)
