extends SceneTree
## VIP 个人中心溢出、ESC 等级总进度与选歌右上玩家资料卡回归。

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


func _profile_fixture() -> Dictionary:
	return {
		"昵称": "良总",
		"头像文件": "",
		"统计": {
			"游玩时长分钟": 1531,
			"累计评价S数": 11,
			"最大Combo": 1413,
			"最大Combo曲目": "IMissYou",
			"最高分": 4490000,
			"最高分曲目": "SugarFree(슈가프리)(BigRoomver.)",
		},
		"进度": {
			"最大等级": 70,
			"经验版本": 2,
			"段位": "2",
			"花式": {"等级": 1, "经验": 0.0, "累计歌曲": 0, "累计首数": 0},
			"竞速": {"等级": 1, "经验": 0.0, "累计歌曲": 0, "累计首数": 0},
			"diy": {"等级": 19, "经验": 0.0, "累计歌曲": 0, "累计首数": 0},
		},
	}


func _rect_inside(inner: Control, outer: Control, margin := 0.5) -> bool:
	if inner == null or outer == null:
		return false
	var a := inner.get_rect()
	var b := outer.get_rect().grow(margin)
	return b.has_point(a.position) and b.has_point(a.end)


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

	var profile := (load("res://scenes/profile/profile.tscn") as PackedScene).instantiate() as Control
	root.add_child(profile)
	await process_frame
	await process_frame
	var top_panel := profile.get_node_or_null("ProfileTopPanel") as Control
	var bottom_panel := profile.get_node_or_null("ProfileBottomPanel") as Control
	var diy_bar := profile.get_node_or_null("DiyExperienceProgress") as Control
	var diy_label := profile.get_node_or_null("DiyLevelLabel") as Control
	var diy_value := profile.get_node_or_null("DiyExpValue") as Control
	var welcome := profile.get_node_or_null("WelcomeText") as Label
	_check(_rect_inside(diy_bar, top_panel) and _rect_inside(diy_label, top_panel)
		and _rect_inside(diy_value, top_panel),
		"VIP 个人中心三项 DIY 经验组件完整收进上面板",
		"top=%s bar=%s label=%s value=%s" % [
			top_panel.get_rect() if top_panel else Rect2(),
			diy_bar.get_rect() if diy_bar else Rect2(),
			diy_label.get_rect() if diy_label else Rect2(),
			diy_value.get_rect() if diy_value else Rect2(),
		])
	_check(welcome != null and _rect_inside(welcome, top_panel)
		and welcome.autowrap_mode != TextServer.AUTOWRAP_OFF and welcome.clip_text,
		"VIP 个人中心右侧说明在上面板内自动换行并裁切保护",
		"welcome=%s top=%s wrap=%s clip=%s" % [
			welcome.get_rect() if welcome else Rect2(),
			top_panel.get_rect() if top_panel else Rect2(),
			welcome.autowrap_mode if welcome else -1,
			welcome.clip_text if welcome else false,
		])
	_check(top_panel != null and bottom_panel != null
		and top_panel.get_rect().end.y < bottom_panel.get_rect().position.y,
		"VIP 个人中心上下两块面板保持明确间距")

	var menu: Node = load("res://ui/esc_menu.gd").new(true)
	root.add_child(menu)
	await process_frame
	menu.call("open_menu")
	menu.call("_set_tab", 4)
	await process_frame
	var content := menu.get_node_or_null("ModernMenu/ContentPanel/ContentBody") as Control
	var esc_diy := content.get_node_or_null(
		"ProfileProgressCard/diyProgress/diyExperienceProgress") as ProgressBar if content else null
	var esc_diy_value := content.get_node_or_null(
		"ProfileProgressCard/diyProgress/ProgressValue") as Label if content else null
	_check(esc_diy != null and esc_diy.value > 0.24 and esc_diy.value < 0.28,
		"ESC 的 Lv.19 / 0 EXP 仍显示约 26% 等级总进度",
		str(esc_diy.value) if esc_diy else "missing")
	_check(esc_diy_value != null and esc_diy_value.text.contains("总进度")
		and esc_diy_value.text.contains("26%"),
		"ESC 进度文字明确区分等级总进度与本级经验",
		esc_diy_value.text if esc_diy_value else "missing")

	var song_select := (load("res://scenes/song_select/song_select.tscn") as PackedScene).instantiate() as Control
	var top_bar := song_select.get_node_or_null("TopBar") as Control
	_check(song_select.has_method("_build_top_profile_badge"),
		"选歌场景提供右上玩家资料卡构建接口")
	if song_select.has_method("_build_top_profile_badge") and top_bar != null:
		song_select.call("_build_top_profile_badge", top_bar)
	var badge := top_bar.get_node_or_null("SongSelectProfileBadge") as Control if top_bar else null
	var avatar := badge.get_node_or_null("Avatar") as TextureRect if badge else null
	var nickname := badge.get_node_or_null("Nickname") as Label if badge else null
	var rank := badge.get_node_or_null("Rank") as Label if badge else null
	var title := top_bar.get_node_or_null("TopBarTitle") as Control if top_bar else null
	var avatar_material := avatar.material as ShaderMaterial if avatar else null
	_check(badge != null and badge.get_rect().end.x <= 1890.0
		and badge.get_rect().position.x >= 1500.0
		and title != null and not badge.get_rect().intersects(title.get_rect()),
		"选歌右上玩家资料卡位于安全空区且不压住歌曲选择标题",
		"badge=%s title=%s" % [badge.get_rect() if badge else Rect2(), title.get_rect() if title else Rect2()])
	_check(avatar != null and avatar.texture != null and avatar_material != null
		and avatar_material.shader != null
		and avatar_material.shader.resource_path == "res://fx/circular_avatar_mask.gdshader"
		and nickname != null and nickname.text == "良总"
		and rank != null and rank.text == "2段",
		"选歌右上角同步显示圆形头像、昵称和当前段位",
		"name=%s rank=%s" % [nickname.text if nickname else "missing", rank.text if rank else "missing"])

	for node in [song_select, menu, profile]:
		if is_instance_valid(node):
			if node.get_parent() == root:
				root.remove_child(node)
			node.free()
	if root.get_node("AudioDirector").has_method("release_for_shutdown"):
		root.get_node("AudioDirector").release_for_shutdown()
	await create_timer(0.15).timeout
	for i in range(_created.size() - 1, -1, -1):
		var node := _created[i]
		if is_instance_valid(node) and node.get_parent() == root:
			root.remove_child(node)
			node.free()
	await process_frame
	print("ALL PROFILE OVERFLOW/SONG HEADER TESTS PASSED" if _failures == 0 else
		"%d PROFILE OVERFLOW/SONG HEADER TEST(S) FAILED" % _failures)
	quit(_failures)
