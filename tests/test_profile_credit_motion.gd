extends SceneTree
## 个人资料编辑、信用持久化、子模式柔和动效回归测试。

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


func _has_property(node: Object, property_name: String) -> bool:
	for item in node.get_property_list():
		if str(item.get("name", "")) == property_name:
			return true
	return false


func _initialize() -> void:
	for entry in AUTOLOADS:
		if root.get_node_or_null(entry[0]) == null:
			var node: Node = load(entry[1]).new()
			node.name = entry[0]
			root.add_child(node)
	await process_frame

	var profile_path := "user://test_profile_edit.json"
	var absolute_profile_path := ProjectSettings.globalize_path(profile_path)
	if FileAccess.file_exists(profile_path):
		DirAccess.remove_absolute(absolute_profile_path)
	var profile_store: Node = load("res://autoload/profile_store.gd").new()
	var supports_profile_store := _has_property(profile_store, "profile_path") \
		and profile_store.has_method("set_nickname")
	_check(supports_profile_store, "个人资料提供昵称保存接口")
	if supports_profile_store:
		profile_store.set("profile_path", profile_path)
		root.add_child(profile_store)
		await process_frame
		var saved := bool(profile_store.call("set_nickname", "  新玩家  "))
		_check(saved and str(profile_store.get("profile").get("昵称", "")) == "新玩家",
			"昵称会去除首尾空格并立即写入资料")
		var avatar_path := "user://test_profile_avatar.png"
		var avatar_image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		avatar_image.fill(Color(0.2, 0.6, 1.0, 1.0))
		avatar_image.save_png(avatar_path)
		var avatar_saved := profile_store.has_method("set_avatar_file") \
			and bool(profile_store.call("set_avatar_file", avatar_path))
		_check(avatar_saved and str(profile_store.get("profile").get("头像文件", "")) == avatar_path,
			"头像文件校验后立即写入资料")
		profile_store.free()
		var reloaded_store: Node = load("res://autoload/profile_store.gd").new()
		reloaded_store.set("profile_path", profile_path)
		root.add_child(reloaded_store)
		await process_frame
		_check(str(reloaded_store.get("profile").get("昵称", "")) == "新玩家",
			"昵称重新启动后仍能读取")
		_check(str(reloaded_store.get("profile").get("头像文件", "")) == avatar_path,
			"头像重新启动后仍能读取")
		reloaded_store.free()
		if FileAccess.file_exists(avatar_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(avatar_path))
	if FileAccess.file_exists(profile_path):
		DirAccess.remove_absolute(absolute_profile_path)

	var profile := load("res://scenes/profile/profile.tscn").instantiate() as Control
	root.add_child(profile)
	await process_frame
	_check(profile.get_node_or_null("AvatarEditButton") != null, "头像区域可以点击修改")
	_check(profile.get_node_or_null("NicknameEditButton") != null, "昵称区域可以点击修改")
	profile.free()

	var credit_path := "user://test_credit_persistence.cfg"
	var absolute_credit_path := ProjectSettings.globalize_path(credit_path)
	if FileAccess.file_exists(credit_path):
		DirAccess.remove_absolute(absolute_credit_path)
	var state_script := load("res://autoload/game_state.gd")
	var first: Node = state_script.new()
	var supports_credit_store := _has_property(first, "credit_store_path") and first.has_method("reload_credits")
	_check(supports_credit_store, "信用状态提供磁盘读取能力")
	if supports_credit_store:
		first.set("credit_store_path", credit_path)
		root.add_child(first)
		await process_frame
		first.call("insert_coin", 4)
		first.free()

		var second: Node = state_script.new()
		second.set("credit_store_path", credit_path)
		root.add_child(second)
		await process_frame
		_check(int(second.get("credits")) == 4, "重新创建状态后读取已保存 CREDIT", str(second.get("credits")))
		second.call("consume_credits", 3)
		second.free()

		var third: Node = state_script.new()
		third.set("credit_store_path", credit_path)
		root.add_child(third)
		await process_frame
		_check(int(third.get("credits")) == 1, "扣除 CREDIT 后立即更新磁盘", str(third.get("credits")))
		third.free()
	if FileAccess.file_exists(credit_path):
		DirAccess.remove_absolute(absolute_credit_path)

	root.get_node("GameState").big_mode = "花式"
	var submode := load("res://scenes/submode_select/submode_select.tscn").instantiate() as Control
	root.add_child(submode)
	await process_frame
	var motion_constants: Dictionary = (submode.get_script() as Script).get_script_constant_map()
	var has_motion_constants := motion_constants.has("ENTRY_TRANSITION") \
		and motion_constants.has("ENTRY_OFFSET") and motion_constants.has("IDLE_AMPLITUDE") \
		and motion_constants.has("IDLE_PERIOD_MS")
	_check(has_motion_constants, "子模式动效参数可回归验证")
	if has_motion_constants:
		_check(motion_constants["ENTRY_TRANSITION"] == Tween.TRANS_QUINT,
			"子模式入场使用柔和减速而非硬弹跳")
		_check(float(motion_constants["ENTRY_OFFSET"]) <= 220.0,
			"子模式入场位移缩短", str(motion_constants["ENTRY_OFFSET"]))
		_check(is_equal_approx(float(motion_constants["IDLE_AMPLITUDE"]), 6.0) \
			and is_equal_approx(float(motion_constants["IDLE_PERIOD_MS"]), 1100.0),
			"待机浮动使用原版 6px / 1100ms 参数")
	submode.free()

	if _failures == 0:
		print("ALL PROFILE CREDIT MOTION TESTS PASSED")
	else:
		print("%d PROFILE CREDIT MOTION TEST(S) FAILED" % _failures)
	quit(_failures)
