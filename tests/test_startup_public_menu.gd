extends SceneTree
## 人工差异清单回归：启动首屏、非游戏 ESC 系统菜单、玩家选择无多余提示。

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


func _check(condition: bool, message: String, detail := "") -> void:
	if condition:
		print("  PASS  %s" % message)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [message, detail])


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

	_check(str(ProjectSettings.get_setting("application/run/main_scene", "")) ==
		"res://scenes/boot/boot.tscn", "程序从原版启动首屏进入")
	var boot_packed := load("res://scenes/boot/boot.tscn") as PackedScene
	var boot := boot_packed.instantiate() if boot_packed else null
	_check(boot != null, "启动场景可加载")
	if boot != null:
		_check(boot.get_node_or_null("SplashImage") != null, "启动场景保存原版首屏图片节点")
		var constants := (boot.get_script() as Script).get_script_constant_map()
		_check(is_equal_approx(float(constants.get("FADE_IN_SEC", -1.0)), 2.0),
			"启动首屏渐显 2.0 秒")
		_check(is_equal_approx(float(constants.get("HOLD_SEC", -1.0)), 1.0),
			"启动首屏停留 1.0 秒")
		_check(is_equal_approx(float(constants.get("FADE_OUT_SEC", -1.0)), 1.5),
			"启动首屏渐隐 1.5 秒")
		boot.free()

	var menu_path := "res://autoload/public_system_menu.gd"
	_check(FileAccess.file_exists(menu_path), "公共非游戏 ESC 系统菜单实现存在")
	_check(str(ProjectSettings.get_setting("autoload/PublicSystemMenu", "")).contains(menu_path),
		"公共系统菜单注册为全局 Autoload")
	if FileAccess.file_exists(menu_path):
		var dummy_scene := Control.new()
		dummy_scene.name = "Coin"
		root.add_child(dummy_scene)
		current_scene = dummy_scene
		var menu: CanvasLayer = load(menu_path).new()
		menu.name = "PublicSystemMenuTest"
		root.add_child(menu)
		await process_frame
		menu.call("open_menu")
		await process_frame
		_check(menu.visible, "ESC 系统菜单可打开")
		_check(menu.get_node_or_null("Dim") != null and
			menu.get_node("Dim").mouse_filter == Control.MOUSE_FILTER_STOP,
			"系统菜单遮罩隔离底层鼠标输入")
		_check(menu.get_node_or_null("Panel/Title") != null and
			menu.get_node("Panel/Title").text == "系统菜单", "系统菜单标题与原版一致")
		_check(menu.get_node_or_null("Panel/Options") != null and
			menu.get_node("Panel/Options").get_child_count() == 4,
			"系统菜单包含原版四项")
		menu.call("close_menu")
		_check(not menu.visible, "ESC 系统菜单可关闭")
		root.remove_child(menu)
		menu.free()
		current_scene = null
		root.remove_child(dummy_scene)
		dummy_scene.free()

	root.get_node("GameState").credits = 0
	var coin := (load("res://scenes/coin/coin.tscn") as PackedScene).instantiate()
	root.add_child(coin)
	for i in 3:
		await process_frame
	root.get_node("GameState").insert_coin(root.get_node("GameState").CREDITS_PER_GAME)
	await process_frame
	var hint := coin.get_node("HintLabel") as Label
	_check(not hint.visible, "1P/2P 玩家选择阶段不显示多余提示文字", hint.text)
	_check(hint.text == "请投币！", "玩家选择不篡改投币提示文本", hint.text)
	root.remove_child(coin)
	coin.free()

	if root.has_node("AudioDirector"):
		root.get_node("AudioDirector").release_for_shutdown()
	# Godot 音频混音线程需要一个短等待才能释放 MP3/WAV playback 引用。
	await create_timer(0.3).timeout
	for i in range(_created.size() - 1, -1, -1):
		var node := _created[i]
		if is_instance_valid(node) and node.get_parent() == root:
			root.remove_child(node)
			node.free()
	await process_frame
	print("ALL STARTUP/PUBLIC MENU TESTS PASSED" if _failures == 0 else
		"%d STARTUP/PUBLIC MENU TEST(S) FAILED" % _failures)
	quit(_failures)
