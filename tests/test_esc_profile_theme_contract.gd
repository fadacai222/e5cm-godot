extends SceneTree
## ESC 用户资料、原版谱面选项、独占全屏与主题重构契约。

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


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
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
	var profile_store = root.get_node("ProfileStore")
	var reward_service = root.get_node("RewardService")
	settings.persist_enabled = false
	profile_store.persist_enabled = false
	reward_service.persist_enabled = false
	reward_service.reset_for_test()
	reward_service.grant("title_daily_rookie", "esc-contract")
	var original_name := str(profile_store.profile.get("昵称", "玩家"))
	var menu: Node = load("res://ui/esc_menu.gd").new(true)
	root.add_child(menu)
	await process_frame

	var tabs: Array = menu.call("_tab_defs")
	_check(tabs.size() == 7 and str(tabs[4][0]) == "用户信息" \
		and str(tabs[5][0]) == "今日挑战" and str(tabs[6][0]) == "特效控制",
		"Gameplay ESC 侧栏只保留七个设置页，不再被四个动作页塞满", str(tabs))
	var nav := menu.get_node_or_null("ModernMenu/NavPanel") as Control
	var resume_action := nav.get_node_or_null("ActionResume") as Button if nav else null
	var reload_action := nav.get_node_or_null("ActionReload") as Button if nav else null
	var return_action := nav.get_node_or_null("ActionReturn") as Button if nav else null
	var desktop_action := nav.get_node_or_null("ActionDesktop") as Button if nav else null
	_check(resume_action != null and reload_action != null and return_action != null \
		and desktop_action != null and resume_action.size == Vector2(128, 104) \
		and reload_action.position.y == resume_action.position.y \
		and return_action.position.y == desktop_action.position.y \
		and resume_action.position.x > 24.0 \
		and desktop_action.position.x + desktop_action.size.x < nav.size.x - 24.0,
		"继续、重载、退出本局和大退缩小为留白充足的侧栏底部 2×2 动作区")
	_check(menu.get_node_or_null("MenuGlowCyan") != null \
		and menu.get_node_or_null("MenuGlowPink") != null \
		and menu.get_node_or_null("GameplayPauseMenu") != null,
		"ESC 使用青蓝/洋红舞台光并保持全屏输入隔离")
	menu.call("_set_tab", 4)
	await process_frame
	var content_body := menu.get_node_or_null("ModernMenu/ContentPanel/ContentBody") as Control
	var identity := content_body.get_node_or_null("ProfileIdentityCard") as Control if content_body else null
	var progress := content_body.get_node_or_null("ProfileProgressCard") as Control if content_body else null
	var nickname := identity.get_node_or_null("NicknameInput") as LineEdit if identity else null
	var profile_avatar := identity.get_node_or_null("ProfileAvatar") as TextureRect if identity else null
	var title_badge := identity.get_node_or_null("EquippedTitleBadge") as Control if identity else null
	var avatar_button := identity.get_node_or_null("ChangeAvatarButton") as Button if identity else null
	_check(identity != null and progress != null and nickname != null,
		"用户信息页真实构建头像/昵称和成长信息双卡片")
	_check(profile_avatar != null and title_badge != null and avatar_button != null \
		and title_badge.size.x <= 200.0 \
		and title_badge.position.y < profile_avatar.position.y + profile_avatar.size.y \
		and title_badge.position.y + title_badge.size.y > profile_avatar.position.y + profile_avatar.size.y \
		and avatar_button.position.y >= title_badge.position.y + title_badge.size.y + 20.0 \
		and avatar_button.size.x <= 150.0 and avatar_button.size.y <= 42.0,
		"称号缩短并贴齐头像框底缘，更换头像按钮下移且不再拥挤")
	var profile_avatar_material := profile_avatar.material as ShaderMaterial \
		if profile_avatar != null else null
	_check(profile_avatar_material != null and profile_avatar_material.shader != null
		and profile_avatar_material.shader.resource_path == "res://fx/circular_avatar_mask.gdshader"
		and profile_avatar.modulate == Color.WHITE
		and profile_avatar.self_modulate == Color.WHITE,
		"ESC 用户信息头像使用统一原色遮罩，不再二次乘色发暗",
		profile_avatar_material.shader.resource_path \
			if profile_avatar_material != null and profile_avatar_material.shader != null else "null")
	_check(progress != null and progress.get_node_or_null("ProfileRankIcon") != null \
		and progress.get_node_or_null("花式Progress/花式ExperienceProgress") != null \
		and progress.get_node_or_null("竞速Progress/竞速ExperienceProgress") != null \
		and progress.get_node_or_null("diyProgress/diyExperienceProgress") != null,
		"用户信息页显示段位与花式/竞速/DIY 三条经验进度")
	var rank_icon := progress.get_node_or_null("ProfileRankIcon") as Control if progress else null
	var rank_label := progress.get_node_or_null("ProfileRankLabel") as Label if progress else null
	_check(rank_icon != null and rank_label != null
		and rank_icon.position.x + rank_icon.size.x + 20.0 <= rank_label.position.x,
		"段位数字与舞者标志保持独立安全间距，不再重叠",
		"icon=%s label=%s" % [rank_icon.get_rect(), rank_label.get_rect()] \
			if rank_icon != null and rank_label != null else "missing")
	var backpack := progress.get_node_or_null("MyBackpackButton") as Button if progress else null
	var backpack_icon := backpack.get_node_or_null("BackpackIcon") as Control if backpack else null
	var backpack_title := backpack.get_node_or_null("BackpackTitle") as Label if backpack else null
	var backpack_count := backpack.get_node_or_null("BackpackCount") as Label if backpack else null
	_check(backpack != null and backpack.size.x <= 330.0 and backpack.text.is_empty() \
		and backpack_icon != null and backpack_icon.get_node_or_null("BagBody") != null \
		and backpack_title != null and backpack_count != null \
		and backpack_icon.position.x + backpack_icon.size.x + 8.0 <= backpack_title.position.x \
		and progress.get_node_or_null("ProfileRewardCard") == null,
		"背包按钮使用独立图标和文字布局，图文互不遮挡")
	if nickname != null:
		nickname.text = "ESC\n测试\t用户"
		menu.call("_save_profile_name")
		_check(str(profile_store.profile.get("昵称", "")) == "ESC测试用户",
			"ESC 用户信息页可保存昵称并清理控制字符")
		profile_store.profile["昵称"] = original_name

	settings.hidden_mode = "关闭"
	menu.call("_step_hidden", 1)
	_check(settings.hidden_mode == "半隐", "隐藏选项按原版关闭→半隐循环")
	menu.call("_step_hidden", 1)
	_check(settings.hidden_mode == "全隐", "隐藏选项按原版半隐→全隐循环")
	settings.track_mode = "正常"
	menu.call("_step_track", 1)
	_check(settings.track_mode == "摇摆", "轨迹选项按原版正常→摇摆循环")
	settings.direction_mode = "关闭"
	menu.call("_step_direction", 1)
	_check(settings.direction_mode == "反向", "方向选项只在关闭/反向之间切换")

	settings.display_mode = "窗口"
	menu.call("_step_display_mode", 1)
	_check(settings.display_mode == "独占全屏",
		"显示模式使用 Windows 独占全屏而非普通无边框铺满")
	settings.window_resolution = Vector2i(1920, 1080)
	settings.call("apply_configured_resolution_for_test")
	menu.call("_step_resolution", 1)
	_check(settings.window_resolution == Vector2i(2560, 1440) \
		and settings.call("runtime_resolution_for_test") == Vector2i(1920, 1080) \
		and settings.call("has_pending_resolution_restart") \
		and menu.get_node_or_null("ResolutionRestartDialog") != null,
		"切换分辨率只保存待应用值，并弹出重启/取消确认")
	menu.call("_cancel_resolution_restart")
	await process_frame
	_check(settings.window_resolution == Vector2i(1920, 1080) \
		and not settings.call("has_pending_resolution_restart") \
		and menu.get_node_or_null("ResolutionRestartDialog") == null,
		"取消分辨率切换会恢复原值且不影响当前运行窗口")
	var compact_window: Vector2i = settings.call("window_size_for_usable_for_test", Vector2i(1366, 728))
	_check(compact_window.x <= 1366 and compact_window.y <= 728 \
			and absf(float(compact_window.x) / float(compact_window.y) - 16.0 / 9.0) < 0.01,
		"窗口模式会在 1366×768 级工作区内保持 16:9 完整可见")
	var project_config := FileAccess.get_file_as_string("res://project.godot")
	var fresh_settings = load("res://autoload/settings_store.gd").new()
	_check(project_config.contains("run/max_fps=144") and bool(fresh_settings.vsync),
		"首次启动默认 144 FPS 并由 SettingsStore 默认开启垂直同步")
	fresh_settings.free()

	settings.max_fps = 0
	settings.apply_performance()
	_check(settings.max_fps == 0 and Engine.max_fps == 0 \
		and str(menu.call("_get_fps")) == "无限制",
		"FPS 上限最后一档为明确的无限制模式")
	var status_hud = load("res://autoload/status_hud.gd").new()
	root.add_child(status_hud)
	await process_frame
	_check(absf(float(status_hud.call("fps_for_display", 2288.0)) - 2288.0) < 0.01,
		"无限制模式下右下角 HUD 显示真实 FPS 采样")
	root.remove_child(status_hud)
	status_hud.free()

	menu.free()
	root.get_node("AudioDirector").release_for_shutdown()
	await create_timer(0.15).timeout
	for i in range(_created.size() - 1, -1, -1):
		var node := _created[i]
		if is_instance_valid(node) and node.get_parent() == root:
			root.remove_child(node)
			node.free()
	await process_frame
	print("ALL ESC PROFILE/THEME CONTRACT TESTS PASSED" if _failures == 0 else
		"%d ESC PROFILE/THEME CONTRACT TEST(S) FAILED" % _failures)
	quit(_failures)
