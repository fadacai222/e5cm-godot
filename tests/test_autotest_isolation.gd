extends SceneTree
## 自动驾驶器必须隔离积分、设置与档案持久化，并在结束后恢复运行时状态。

const AUTOLOADS := [
	["SettingsStore", "res://autoload/settings_store.gd"],
	["GameState", "res://autoload/game_state.gd"],
	["ProfileStore", "res://autoload/profile_store.gd"],
]

var _created: Array[Node] = []


func _initialize() -> void:
	for entry in AUTOLOADS:
		if root.get_node_or_null(entry[0]) == null:
			var node: Node = load(entry[1]).new()
			node.name = entry[0]
			root.add_child(node)
			_created.append(node)
	await process_frame

	var game_state = root.get_node("GameState")
	var settings_store = root.get_node("SettingsStore")
	var profile_store = root.get_node("ProfileStore")
	var driver_script := load("res://tests/autotest_driver.gd")
	var driver: Node = driver_script.new()

	game_state.credits = 7
	game_state.persist_credits = true
	settings_store.autoplay = false
	profile_store.persist_enabled = true
	settings_store.persist_enabled = true

	driver._prepare_test_state()
	assert(game_state.credits == 0, "自动测必须从 0 币开始")
	assert(not game_state.persist_credits, "自动测期间禁止持久化积分")
	assert(settings_store.autoplay, "自动测期间应启用 autoplay")
	assert(not profile_store.persist_enabled, "自动测期间禁止持久化档案与成绩")
	assert(not settings_store.persist_enabled, "自动测期间禁止持久化设置")

	driver._restore_runtime_state()
	assert(game_state.credits == 7, "自动测结束必须恢复内存积分")
	assert(game_state.persist_credits, "自动测结束必须恢复积分持久化策略")
	assert(not settings_store.autoplay, "自动测结束必须恢复 autoplay")
	assert(profile_store.persist_enabled, "自动测结束必须恢复档案持久化策略")
	assert(settings_store.persist_enabled, "自动测结束必须恢复设置持久化策略")
	driver.free()

	for i in range(_created.size() - 1, -1, -1):
		var node := _created[i]
		if is_instance_valid(node) and node.get_parent() == root:
			root.remove_child(node)
			node.free()
	await process_frame
	print("AUTOTEST ISOLATION PASS")
	quit(0)
