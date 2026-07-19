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
	settings.persist_enabled = false
	profile_store.persist_enabled = false
	var original_name := str(profile_store.profile.get("昵称", "玩家"))
	var menu: Node = load("res://ui/esc_menu.gd").new(true)
	root.add_child(menu)
	await process_frame

	var tabs: Array = menu.call("_tab_defs")
	_check(tabs.size() == 9 and str(tabs[4][0]) == "用户信息",
		"Gameplay ESC 导航包含用户信息页且动作页索引未错位", str(tabs))
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
	_check(identity != null and progress != null and nickname != null,
		"用户信息页真实构建头像/昵称和成长信息双卡片")
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

	settings.max_fps = 0
	settings.apply_performance()
	_check(settings.max_fps == 240 and Engine.max_fps == 240,
		"旧版不限帧设置自动迁移到 240 FPS，菜单不再空跑上千帧")
	var status_hud = load("res://autoload/status_hud.gd").new()
	root.add_child(status_hud)
	await process_frame
	_check(absf(float(status_hud.call("fps_for_display", 2288.0)) - 240.0) < 0.01,
		"右下角 FPS 对瞬时异常采样按当前帧率上限显示")
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
