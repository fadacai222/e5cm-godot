extends SceneTree
## 原版 E5CM-CG 关键视觉与交互契约回归测试。

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


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _near_rect(node: Control, expected: Rect2, tolerance := 2.0) -> bool:
	return node != null and node.position.distance_to(expected.position) <= tolerance \
		and node.size.distance_to(expected.size) <= tolerance


func _initialize() -> void:
	_check(int(ProjectSettings.get_setting("display/window/size/window_width_override", 0)) == 1920
		and int(ProjectSettings.get_setting("display/window/size/window_height_override", 0)) == 1080,
		"默认窗口覆盖尺寸为原生 1920×1080")
	for entry in AUTOLOADS:
		if root.get_node_or_null(entry[0]) == null:
			var node: Node = load(entry[1]).new()
			node.name = entry[0]
			root.add_child(node)
	await process_frame
	root.get_node("GameState").persist_credits = false
	root.get_node("ProfileStore").persist_enabled = false
	root.get_node("SettingsStore").persist_enabled = false
	root.get_node("GameState").big_mode = "竞速"
	root.get_node("GameState").sub_mode = "club"
	_check(root.get_node("SceneRouter").has_method("change_to_with_zoom"),
		"公共路由提供元素级放大换场能力")

	var profile := load("res://scenes/profile/profile.tscn").instantiate() as Control
	root.add_child(profile)
	await process_frame
	var top_panel := profile.get_node_or_null("ProfileTopPanel") as Control
	var bottom_panel := profile.get_node_or_null("ProfileBottomPanel") as Control
	_check(_near_rect(top_panel, Rect2(208.125, 175.3125, 1395, 285.9375)),
		"个人中心上面板使用原版坐标", str(Rect2(top_panel.position, top_panel.size)) if top_panel else "null")
	_check(_near_rect(bottom_panel, Rect2(200.625, 509.0625, 1404.375, 356.25)),
		"个人中心下面板使用原版坐标", str(Rect2(bottom_panel.position, bottom_panel.size)) if bottom_panel else "null")
	_check(profile.get_tree().get_nodes_in_group("profile_exp_bar").size() == 2,
		"个人中心仅显示原版花式与竞速经验条")
	profile.call("_open_nickname_editor")
	await process_frame
	var profile_editor := profile.get_node_or_null("ProfileEditorOverlay") as Control
	_check(profile_editor != null and profile_editor.mouse_filter == Control.MOUSE_FILTER_STOP,
		"资料编辑使用场景内遮罩并锁住背景输入")
	_check(profile.get_node_or_null("ProfileEditorOverlay/EditorPanel/NicknameInput") != null,
		"昵称二次弹层使用场景内输入框")
	if profile.has_method("_close_editor"):
		profile.call("_close_editor")
	elif profile.get("_nickname_dialog") != null:
		profile.get("_nickname_dialog").hide()
	profile.call("_open_avatar_editor")
	await process_frame
	_check(profile.get_node_or_null("ProfileEditorOverlay/EditorPanel/AvatarPathInput") != null,
		"头像编辑使用场景内路径输入与预览弹层")
	_check(profile.get_node_or_null("ProfileEditorOverlay/FileDialog") == null,
		"头像编辑不再调用原生文件选择对话框")
	if profile.has_method("_close_editor"):
		profile.call("_close_editor")
	profile.free()

	var mode := load("res://scenes/mode_select/mode_select.tscn").instantiate() as Control
	root.add_child(mode)
	await process_frame
	_check(int(mode.get("_selected")) == -1, "大模式入场不自动选中", str(mode.get("_selected")))
	_check(mode.get_node_or_null("ModePrompt") != null, "大模式未选择时显示居中提示")
	var mode_constants := (mode.get_script() as Script).get_script_constant_map()
	_check(is_equal_approx(float(mode_constants.get("ENTER_OFFSET", 0.0)), 120.0),
		"大模式按钮从原版下移 120px 的起点入场")
	var mode_button := mode.get_node_or_null("ModeButton0") as Control
	var mode_base: Vector2 = (mode.get("_base_positions") as Array)[0]
	_check(mode_button != null and mode_button.position.y > mode_base.y,
		"大模式首帧仍位于目标位下方", str(mode_button.position) if mode_button else "null")
	mode.free()

	var submode := load("res://scenes/submode_select/submode_select.tscn").instantiate() as Control
	root.add_child(submode)
	await process_frame
	_check(int(submode.get("_selected")) == -1, "子模式入场不自动选中", str(submode.get("_selected")))
	_check(submode.get("ENTRY_DURATION") != null and float(submode.get("ENTRY_DURATION")) >= 1.19,
		"子模式保留原版 1200ms 入场动效")
	var submode_constants := (submode.get_script() as Script).get_script_constant_map()
	_check(int(submode_constants.get("PAGE_SIZE", 0)) == 18, "子模式每页容量与原版 6×3 一致",
		str(submode_constants.get("PAGE_SIZE", null)))
	_check(submode.has_method("_change_page"), "子模式提供可操作的跨页导航")
	_check(submode.has_method("_caption_text") and str(submode.call("_caption_text", "一二三四五六七八九")) == "一二三四五六七…",
		"DIY 长名称按原版 7 字加省略号")
	var paging_items: Array = []
	for i in 19:
		paging_items.append("QA曲包%02d" % i)
	submode.set("_items", paging_items)
	submode.set("_page", 0)
	submode.call("_build_page")
	_check((submode.call("_page_items") as Array).size() == 18, "DIY 首屏可达 18 个曲包")
	var page_changed := bool(submode.call("_change_page", 1, true))
	_check(page_changed and int(submode.get("_page")) == 1
		and (submode.call("_page_items") as Array).size() == 1
		and int(submode.get("_selected")) == 0, "DIY 第 19 个曲包可通过下一页到达")
	submode.free()

	var song := load("res://scenes/song_select/song_select.tscn").instantiate() as Control
	root.add_child(song)
	await process_frame
	var card := song.get_node_or_null("SongCard0") as Control
	var frame := card.get_node_or_null("Frame") as Control if card else null
	var cover := card.get_node_or_null("CoverClip/Cover") as Control if card else null
	_check(frame != null and absf(frame.size.x / frame.size.y - 4.0 / 3.0) < 0.03,
		"选歌框使用原版 4:3 宽框", str(frame.size) if frame else "null")
	_check(cover != null and cover.position.x >= 0.0 and cover.position.y >= 0.0 \
		and cover.position.x + cover.size.x <= cover.get_parent().size.x + 0.5 \
		and cover.position.y + cover.size.y <= cover.get_parent().size.y + 0.5,
		"选歌封面被裁切容器完整包裹")
	_check(song.get_node_or_null("TopBar/ModeBadge") != null
		and song.get_node_or_null("TopBar/SubmodeBadge") != null,
		"选歌 Top 左上显示当前大模式与子模式")
	song.set("songs", [])
	song.call("_build_page")
	_check(song.get_node_or_null("SongEmptyState") != null
		and song.get_node_or_null("SongEmptyState/ResetFilters") != null,
		"选歌无结果时显示可恢复的空状态")
	song.free()

	var esc: CanvasLayer = load("res://ui/esc_menu.gd").new()
	root.add_child(esc)
	await process_frame
	_check(esc.get_node_or_null("ModernMenu/NavPanel") != null, "设置页使用原版现代双栏菜单")
	_check(esc.get_node_or_null("ModernMenu/ContentPanel") != null, "设置页具有独立内容面板")
	esc.call("_set_tab", 3)
	await process_frame
	_check(esc.get_node_or_null("ModernMenu/ContentPanel/ContentBody/Binding_p1_lane0") != null,
		"键位页提供可选中的重绑按钮")
	_check(esc.has_method("_try_rebind_key"), "键位页提供按键捕获与冲突检测")
	if esc.has_method("_try_rebind_key"):
		var original_binding: Array = root.get_node("SettingsStore").key_bindings["p1_lane0"].duplicate()
		var rebound := bool(esc.call("_try_rebind_key", "p1_lane0", KEY_V))
		_check(rebound and root.get_node("SettingsStore").key_bindings["p1_lane0"] == [KEY_V],
			"捕获新按键后即时应用到 InputMap")
		var conflict := bool(esc.call("_try_rebind_key", "p1_lane0", KEY_Z))
		_check(not conflict, "占用中的按键不会静默覆盖其他轨道")
		root.get_node("SettingsStore").key_bindings["p1_lane0"] = original_binding
		root.get_node("SettingsStore").apply_input_map()
	esc.free()

	root.get_node("SceneRouter").payload = {"name": "加载测试", "mode": "竞速", "submode": "club",
		"star": 4, "cover": "", "sm_key": "qa/loading.sm"}
	var loading := load("res://scenes/loading/loading.tscn").instantiate() as Control
	root.add_child(loading)
	await process_frame
	_check(loading.get_node_or_null("PlayerSummary/PlayerName") != null
		and loading.get_node_or_null("PlayerSummary/StoreName") != null,
		"加载页显示原版记录保持者与玩家店铺摘要")
	loading.free()

	root.get_node("SceneRouter").payload = {}
	var settings_store = root.get_node("SettingsStore")
	var original_background_mode := str(settings_store.background_mode)
	settings_store.background_mode = "视频"
	var gameplay := load("res://scenes/gameplay/gameplay.tscn").instantiate() as Control
	root.add_child(gameplay)
	await process_frame
	_check(gameplay.get_node_or_null("LegacyTopHud/HpFrame") != null,
		"游戏场景使用原版长血条 HUD")
	_check(gameplay.get_node_or_null("LegacyTopHud/AvatarFrame") != null,
		"游戏 HUD 包含原版头像框")
	_check(gameplay.get_node_or_null("LegacyTopHud/StageBoard") != null,
		"游戏 HUD 包含原版关卡板")
	_check(gameplay.has_method("_find_gameplay_video_path"), "谱面场景提供视频背景选择与回退")
	var gameplay_video := gameplay.get_node_or_null("GameplayVideo") as VideoStreamPlayer
	_check(gameplay_video != null and gameplay_video.stream != null,
		"显式选择视频模式且有原版视频时创建静音循环背景")
	gameplay.free()
	settings_store.background_mode = original_background_mode

	var field: Node2D = load("res://scenes/gameplay/note_field.gd").new()
	root.add_child(field)
	field.setup(5, 1.0)
	var hold := JudgeSystem.JudgeNote.new(2, "hold", 1.0, 2.0, [1.5])
	field.load_notes([hold])
	field.update_field(0.5, 0.016)
	var hold_item: Dictionary = field.get("_render_notes")[0]
	var body := hold_item.get("body") as Sprite2D
	_check(body != null and body.texture != null and body.visible and body.z_index > 0,
		"HOLD 身体纹理可见且位于背景上方", str(body.z_index) if body else "null")
	field.call("on_report", JudgeSystem.JudgeReport.new("tap", 0, "cool", 120.0, 4000, 1, 1.0, 1.0))
	var timing_hint := field.get_node_or_null("TimingHintP1") as Label
	_check(timing_hint != null and timing_hint.text == "+120 ms",
		"提前命中只显示有符号毫秒差", timing_hint.text if timing_hint else "null")
	field.call("on_report", JudgeSystem.JudgeReport.new("tap", 0, "cool", -120.0, 4000, 1, 1.0, 1.0))
	_check(timing_hint != null and timing_hint.text == "-120 ms",
		"延后命中只显示有符号毫秒差", timing_hint.text if timing_hint else "null")
	field.free()

	root.get_node("SceneRouter").payload = {
		"曲目名": "失败重试测试", "sm_key": "qa/fail.sm", "mode": "竞速", "submode": "club",
		"cover": "", "star": 4, "本局最高分": 0, "本局最大combo": 0, "歌曲时长秒": 60.0,
		"百分比": "0.00%", "百分比数值": 0.0, "评级": "F", "失败": true,
		"当前关卡": 1, "结算后S数": 0, "三把S赠送": false, "是否赠送第四把": false,
		"perfect数": 0, "cool数": 0, "good数": 0, "miss数": 10,
		"是否全perfect": false, "是否全连": false,
	}
	var settlement := load("res://scenes/settlement/settlement.tscn").instantiate() as Control
	root.add_child(settlement)
	await process_frame
	root.get_node("GameState").credits = 3
	settlement.call("_enter_phase3")
	var retry_action: Dictionary = settlement.get("_p3_action")
	_check(int(retry_action.get("next_round", -1)) == 1 and not bool(retry_action.get("new_match", true)),
		"第 1 局失败后继续会重试第 1 局", str(retry_action))
	var yes_button := settlement.get("_p3_yes") as TextureButton
	_check(yes_button.visible and yes_button.modulate != Color.WHITE,
		"继续挑战默认高亮“是”", str(yes_button.modulate))
	_check(settlement.has_method("_show_three_s_effect"), "三把 S 提供专属评价动画")
	if settlement.has_method("_show_three_s_effect"):
		settlement.call("_show_three_s_effect")
		_check(settlement.get_node_or_null("ThreeSGradeEffect") != null,
			"三把 S 动画使用专属评价素材")
	settlement.set("_exp_result", {
		"显示奖励窗": true, "正式局总经验": 90,
		"正式局歌曲": [{"评级": "S", "基础经验": 15, "连续S倍率": 1, "奖励倍率": 2.0, "最终经验": 30}],
		"经验结算": {"原等级": 1, "等级": 2, "原经验": 0.0, "经验": 20.0,
			"等级所需经验": 100, "是否升级": true, "升级次数": 1},
	})
	settlement.call("_enter_phase2")
	var exp_panel := settlement.get_node_or_null("ExperienceRewardPanel")
	_check(exp_panel != null and exp_panel.get_node_or_null("RewardWindow") != null,
		"结算经验阶段使用原版奖励窗素材")
	_check(exp_panel != null
		and exp_panel.get_node_or_null("RewardWindow/StyleExperienceBarFrame") != null
		and exp_panel.get_node_or_null("RewardWindow/SpeedExperienceBarFrame") != null
		and exp_panel.get_node_or_null("RewardWindow/ExpDigits") != null,
		"经验阶段包含花式/竞速贴图经验条与经验数字图集")
	settlement.free()

	# SceneTree.quit() 前先释放音频后端引用并等混音线程回收 playback，
	# 否则退出与 AudioServer 竞争会偶发 ObjectDB AudioStreamMP3 泄漏。
	# headless dummy 驱动一个 mix 周期约 93ms，0.1s 仍在竞争边缘，留足余量。
	root.get_node("AudioDirector").release_for_shutdown()
	await process_frame
	await create_timer(0.3).timeout

	if _failures == 0:
		print("ALL REFERENCE PARITY TESTS PASSED")
	else:
		print("%d REFERENCE PARITY TEST(S) FAILED" % _failures)
	quit(_failures)
