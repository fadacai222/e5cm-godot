extends SceneTree
## 游客/VIP 登录界面旧版坐标与内部资源回归测试。

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
const LOGIN_KEYS := [
	"登陆_场景1_游客", "登陆_场景1_vip", "登陆_场景2_游客", "登陆_请刷卡背景",
	"登陆_请刷卡内容", "登陆_请刷卡内容白色", "登陆_磁卡", "登陆_贵宾装饰",
]

var _failures := 0
var _created_autoloads: Array[Node] = []


func _check(cond: bool, name: String, detail := "") -> void:
	if cond:
		print("  PASS  %s" % name)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [name, detail])


func _near_rect(node: Control, expected: Rect2, tolerance := 1.0) -> bool:
	return node != null and node.position.distance_to(expected.position) <= tolerance \
		and node.size.distance_to(expected.size) <= tolerance


func _initialize() -> void:
	for entry in AUTOLOADS:
		if root.get_node_or_null(entry[0]) == null:
			var node: Node = load(entry[1]).new()
			node.name = entry[0]
			root.add_child(node)
			_created_autoloads.append(node)
	await process_frame

	var loader := root.get_node("AssetLoader")
	for key in LOGIN_KEYS:
		var path := str(loader.call("res_path", key))
		_check(path.begins_with("res://") and FileAccess.file_exists(path),
			"%s 使用项目内资源" % key, path)

	var login := load("res://scenes/login/login.tscn").instantiate() as Control
	root.add_child(login)
	await process_frame
	var guest := login.get_node_or_null("Stage1Guest") as Control
	var vip := login.get_node_or_null("Stage1Vip") as Control
	_check(_near_rect(guest, Rect2(105.5625, 142.125, 934.5, 803.25)),
		"游客入口按旧版 1.4 倍视觉框布局", str(Rect2(guest.position, guest.size)) if guest else "null")
	_check(_near_rect(vip, Rect2(1013.4375, 330.9375, 417.1875, 418.125)),
		"VIP 入口按旧版基准框布局", str(Rect2(vip.position, vip.size)) if vip else "null")

	login.call("_set_stage", "刷卡")
	await process_frame
	var swipe_bg := login.get_node_or_null("SwipeBackground") as Control
	var card := login.get_node_or_null("VipCard") as Control
	_check(_near_rect(swipe_bg, Rect2(510.890625, 320.625, 898.21875, 438.75)),
		"请刷卡框按素材 1.3 倍居中", str(Rect2(swipe_bg.position, swipe_bg.size)) if swipe_bg else "null")
	_check(_near_rect(card, Rect2(1277.34375, 807.1875, 310.3125, 181.875), 70.0),
		"VIP 卡片落在旧版右下目标位", str(Rect2(card.position, card.size)) if card else "null")
	_check(login.get_node_or_null("SwipeHintWhite") != null, "请刷卡提示包含白色闪烁帧")
	_check(login.get_node_or_null("VipDecoration") != null, "请刷卡框包含旧版贵宾装饰")
	login.set("_auto_swiping", true)
	login.call("_set_stage", "选择")
	_check(login.get("_auto_swiping") == false, "取消刷卡会停止自动刷卡状态")

	var constants := (login.get_script() as Script).get_script_constant_map()
	_check(constants.has("BUTTON_DISAPPEAR_SEC") and
		is_equal_approx(float(constants.get("BUTTON_DISAPPEAR_SEC", -1.0)), 0.2),
		"VIP 选择按钮使用原版 0.2 秒消失动画")
	login.call("_pick", "VIP")
	await create_timer(0.07).timeout
	_check(login.get("_transitioning") == true, "VIP 点击后锁定重复输入")
	_check(str(login.get("_stage")) == "选择", "消失动画完成前仍停留选择阶段", str(login.get("_stage")))
	_check(guest.scale.x < 1.0 and vip.scale.x < 1.0
		and absf(guest.scale.x - vip.scale.x) <= 0.01,
		"VIP 点击后游客与 VIP 两个入口同步缩小", "%s / %s" % [guest.scale, vip.scale])
	await create_timer(0.20).timeout
	_check(str(login.get("_stage")) == "刷卡", "消失动画完成后进入刷卡阶段", str(login.get("_stage")))
	_check(login.get("_transitioning") == false, "进入刷卡阶段后解除输入锁")
	_check(guest.scale.is_equal_approx(Vector2.ONE) and vip.scale.is_equal_approx(Vector2.ONE),
		"隐藏入口恢复基础缩放，返回时不会保持缩成零", "%s / %s" % [guest.scale, vip.scale])

	root.remove_child(login)
	login.free()
	if root.has_node("AudioDirector"):
		root.get_node("AudioDirector").release_for_shutdown()
	await create_timer(0.3).timeout
	for i in range(_created_autoloads.size() - 1, -1, -1):
		var node := _created_autoloads[i]
		if is_instance_valid(node) and node.get_parent() == root:
			root.remove_child(node)
			node.free()
	await process_frame
	if _failures == 0:
		print("ALL LOGIN LAYOUT TESTS PASSED")
	else:
		print("%d LOGIN LAYOUT TEST(S) FAILED" % _failures)
	quit(_failures)
