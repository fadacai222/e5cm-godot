extends SceneTree
## 最新人工复测中的个人资料固定数据、文字与经验条契约。

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

const SONG_NAME := "As_If_lts_Your_Last_mv_1706"
const ORIGINAL_WELCOME := "e舞成名重构版（测试）为非盈利性的游戏；\n本游戏软件为交流、学习、测试使用，如有侵权，请率先联系我们。\n如果你有意参与我们的开发项目；\n请进人QQ群：1084318862\n进群后联系Emma_H。"
const ORIGINAL_SOFTWARE_LINES := [
	"游戏版本：e舞成名重构版4.12.1",
	"开发团队：程序工程师/策划/游戏制作人：良    UE/UI设计/策划：Emma_H（林曦）",
	"特别鸣谢（排名不分先后）：",
	"Cyan（音效提供）|  飞翔e舞模拟器（曲谱资源提供）",
	"LifeErrOr（美术提供）|  小鱼（美术提供）",
	"“e舞时刻”官方粉丝1群参与讨论的群友（反馈提供）",
	"玩家交流QQ群：1084318862",
]

var _failures := 0
var _created: Array[Node] = []


func _check(condition: bool, message: String, detail := "") -> void:
	if condition:
		print("  PASS  %s" % message)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [message, detail])


func _fixture_profile() -> Dictionary:
	return {
		"昵称": "像素校准员",
		"头像文件": "",
		"统计": {
			"游玩时长分钟": 56,
			"累计评价S数": 15,
			"最大Combo": 387,
			"最大Combo曲目": SONG_NAME,
			"最高分": 1350000,
			"最高分曲目": SONG_NAME,
		},
		"进度": {
			"最大等级": 70,
			"经验版本": 2,
			"段位": "",
			"花式": {"等级": 8, "经验": 2.5, "累计歌曲": 18, "累计首数": 6},
			"竞速": {"等级": 12, "经验": 4.5, "累计歌曲": 36, "累计首数": 12},
			"diy": {"等级": 3, "经验": 4.0, "累计歌曲": 6, "累计首数": 2},
		},
	}


func _segment_text(row: Label, name_text: String) -> String:
	var segment := row.get_node_or_null(name_text) as Label
	return segment.text if segment != null else ""


func _segment_color(row: Label, name_text: String) -> Color:
	var segment := row.get_node_or_null(name_text) as Label
	return segment.get_theme_color("font_color") if segment != null else Color.TRANSPARENT


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
	root.get_node("ProfileStore").persist_enabled = false
	root.get_node("ProfileStore").profile = _fixture_profile()

	var profile := (load("res://scenes/profile/profile.tscn") as PackedScene).instantiate()
	root.add_child(profile)
	await process_frame
	await process_frame

	var expected_rows := [
		["游玩时长：", "56分钟", ""],
		["累计评价S：", "15", ""],
		["最大Combo：", "387", "（%s）" % SONG_NAME],
		["最高分：", "1350000", "（%s）" % SONG_NAME],
	]
	for i in expected_rows.size():
		var row := profile.get_node("Stat%d" % i) as Label
		var expected: Array = expected_rows[i]
		_check(_segment_text(row, "LabelPart") == expected[0] \
			and _segment_text(row, "ValuePart") == expected[1] \
			and _segment_text(row, "SongPart") == expected[2],
			"统计第 %d 行使用固定资料且标签/数值/曲目不串行" % (i + 1),
			"%s|%s|%s" % [
				_segment_text(row, "LabelPart"),
				_segment_text(row, "ValuePart"),
				_segment_text(row, "SongPart"),
			])
		var label_part := row.get_node_or_null("LabelPart") as Label
		var value_part := row.get_node_or_null("ValuePart") as Label
		var song_part := row.get_node_or_null("SongPart") as Label
		_check(label_part != null and value_part != null \
			and label_part.get_theme_font_size("font_size") == 21 \
			and value_part.get_theme_font_size("font_size") == 21 \
			and label_part.get_theme_constant("outline_size") == 0,
			"统计第 %d 行使用原版 22px 等比字号、非粗体无描边" % (i + 1),
			"label=%d value=%d song=%d" % [
				label_part.get_theme_font_size("font_size") if label_part != null else -1,
				value_part.get_theme_font_size("font_size") if value_part != null else -1,
				song_part.get_theme_font_size("font_size") if song_part != null else -1,
			])
		_check(_segment_color(row, "LabelPart").is_equal_approx(Color.WHITE) \
			and _segment_color(row, "ValuePart").is_equal_approx(Color(1.0, 220.0 / 255.0, 80.0 / 255.0)) \
			and (expected[2].is_empty() or
				_segment_color(row, "SongPart").is_equal_approx(Color(190.0 / 255.0, 140.0 / 255.0, 1.0))),
			"统计第 %d 行区分白色标签、黄色数值与紫色曲目" % (i + 1))
		var right_edge := 0.0
		for part in [label_part, value_part, song_part]:
			if part != null and not part.text.is_empty():
				right_edge = maxf(right_edge, part.position.x + part.size.x)
				_check(not part.clip_text and part.autowrap_mode == TextServer.AUTOWRAP_OFF,
					"统计第 %d 行禁止裁切或错误换行" % (i + 1))
		_check(right_edge <= row.size.x + 0.5,
			"统计第 %d 行长歌曲名完整位于统计区" % (i + 1),
			"right=%.1f width=%.1f" % [right_edge, row.size.x])

	var expected_bars := {
		"Fancy": Rect2(Vector2(593.4375, 362.8125), Vector2(908.4375, 32.8125)),
		"Speed": Rect2(Vector2(592.5, 409.6875), Vector2(908.4375, 32.8125)),
	}
	_check(profile.has_method("_apply_progress_ratio"),
		"个人资料提供真实填充矩形比例计算")
	for prefix in expected_bars:
		var frame := profile.get_node("%sExpFrame" % prefix) as TextureRect
		var fill := profile.get_node("%sExpFill" % prefix) as TextureRect
		_check(frame.get_rect().position.distance_to(expected_bars[prefix].position) < 0.6 \
			and frame.get_rect().size.distance_to(expected_bars[prefix].size) < 0.6,
			"%s 经验条使用原版 969×35 等比矩形" % prefix, str(frame.get_rect()))
		for ratio in [0.0, 0.5, 0.99, 1.0]:
			profile.call("_apply_progress_ratio", prefix, ratio)
			await process_frame
			_check(absf(fill.size.x - frame.size.x * ratio) <= 0.6 \
				and fill.position.x >= frame.position.x - 0.1 \
				and fill.position.x + fill.size.x <= frame.position.x + frame.size.x + 0.6 \
				and fill.position.y >= frame.position.y - 0.1 \
				and fill.position.y + fill.size.y <= frame.position.y + frame.size.y + 0.6,
				"%s 经验条 %.0f%% 填充不越界" % [prefix, ratio * 100.0],
				"fill=%s frame=%s" % [fill.get_rect(), frame.get_rect()])
		_check(fill.texture is AtlasTexture, "%s 经验条通过纹理区域裁切而非拉伸溢出" % prefix)
	var diy_bar := profile.get_node_or_null("DiyExperienceProgress") as ProgressBar
	var diy_overall_ratio := ExpSystem.overall_progress_ratio({"等级": 3, "经验": 4.0})
	_check(diy_bar != null \
		and diy_bar.get_rect().position.distance_to(Vector2(593.4375, 456.5625)) < 0.6 \
		and diy_bar.get_rect().size.distance_to(Vector2(908.4375, 32.8125)) < 0.6 \
		and absf(diy_bar.value - diy_overall_ratio) < 0.001,
		"DIY 第三经验条使用同宽矩形并显示等级总进度",
		str(diy_bar.get_rect()) if diy_bar else "missing")
	_check((profile.get_node("FancyLevelLabel") as Label).text == "花式经验值：" \
		and (profile.get_node("FancyExpValue") as Label).text == "Lv. 8" \
		and (profile.get_node("SpeedLevelLabel") as Label).text == "竞速经验值：" \
		and (profile.get_node("SpeedExpValue") as Label).text == "Lv. 12" \
		and (profile.get_node("DiyLevelLabel") as Label).text == "DIY经验值：" \
		and (profile.get_node("DiyExpValue") as Label).text == "Lv. 3",
		"三模式经验条标签与等级数字完整显示")

	var profile_store = root.get_node("ProfileStore")
	profile_store.set_mode_progress_preview("花式", {
		"等级": 9, "经验": 4.0, "累计歌曲": 18, "累计首数": 6,
	})
	await process_frame
	var fancy_frame := profile.get_node("FancyExpFrame") as TextureRect
	var fancy_fill := profile.get_node("FancyExpFill") as TextureRect
	var fancy_overall_ratio := ExpSystem.overall_progress_ratio({"等级": 9, "经验": 4.0})
	_check((profile.get_node("FancyExpValue") as Label).text == "Lv. 9" \
		and absf(fancy_fill.size.x - fancy_frame.size.x * fancy_overall_ratio) < 0.8,
		"缓存经验变化后个人中心无需重进场景即可实时刷新",
		"label=%s fill=%.1f frame=%.1f" % [
			(profile.get_node("FancyExpValue") as Label).text, fancy_fill.size.x, fancy_frame.size.x])
	_check(int(profile_store.get_mode_progress("花式").get("等级", 0)) == 8 \
		and int(profile_store.get_mode_progress_for_display("花式").get("等级", 0)) == 9,
		"缓存预览只影响显示进度，不提前篡改正式存档")
	profile_store.set_mode_progress("花式", {
		"等级": 10, "经验": 1.0, "累计歌曲": 19, "累计首数": 7,
	})
	await process_frame
	_check((profile.get_node("FancyExpValue") as Label).text == "Lv. 10" \
		and int(profile_store.get_mode_progress_for_display("花式").get("等级", 0)) == 10,
		"正式经验入账后立即替换缓存预览并刷新个人中心")

	var welcome := profile.get_node("WelcomeText") as Label
	_check(welcome.text == ORIGINAL_WELCOME, "右侧介绍区逐字使用当前原版文案", welcome.text)
	_check(welcome.get_theme_font_size("font_size") == 15 \
		and welcome.get_theme_constant("outline_size") == 0 \
		and welcome.get_theme_color("font_color").is_equal_approx(Color(160.0 / 255.0, 160.0 / 255.0, 160.0 / 255.0)),
		"右侧介绍区使用原版字号、灰色和无描边")

	var software = profile.get_node("SoftwareInfo")
	var software_plain: String = str(software.get_parsed_text()) \
		if software.has_method("get_parsed_text") else str(software.get("text"))
	for line in ORIGINAL_SOFTWARE_LINES:
		_check(software_plain.contains(line), "软件信息包含原版逐字文案：%s" % line, software_plain)
	_check(not software_plain.contains("Godot 重制版") and not software_plain.contains("StepMania SM"),
		"软件信息已移除自行概括的占位文案")
	var disclaimer := profile.get_node("Disclaimer") as Label
	_check(disclaimer.text == "本游戏设计初衷是为了让更多e舞玩家能在各地玩到e舞成名，本项目纯爱发电，没有任何盈利性质，如您发现有人倒卖本软件，请及时联系我们。",
		"软件说明逐字使用当前原版文案", disclaimer.text)

	root.remove_child(profile)
	profile.free()
	if root.get_node("AudioDirector").has_method("release_for_shutdown"):
		root.get_node("AudioDirector").release_for_shutdown()
	await create_timer(0.3).timeout
	for i in range(_created.size() - 1, -1, -1):
		var node := _created[i]
		if is_instance_valid(node) and node.get_parent() == root:
			root.remove_child(node)
			node.free()
	await process_frame
	print("ALL PROFILE VISUAL CONTRACT TESTS PASSED" if _failures == 0 else
		"%d PROFILE VISUAL CONTRACT TEST(S) FAILED" % _failures)
	quit(_failures)
