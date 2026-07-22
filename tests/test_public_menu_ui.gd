extends SceneTree
## 公共 Top 栏与底部 CREDIT 布局回归测试。
## 运行：Godot_v4.6.2-stable_win64_console.exe --headless --path . --script res://tests/test_public_menu_ui.gd

const TOP_INTERNAL_KEYS := [
	"top栏背景",
	"top标题_个人中心",
	"top标题_模式选择",
	"top标题_玩法选择",
	"top标题_歌曲选择",
]

var _failures := 0


func _check(cond: bool, name: String, detail := "") -> void:
	if cond:
		print("  PASS  %s" % name)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [name, detail])


func _initialize() -> void:
	var asset_loader: Node = root.get_node_or_null("AssetLoader")
	var created_asset_loader := asset_loader == null
	if created_asset_loader:
		asset_loader = load("res://autoload/asset_loader.gd").new()
		asset_loader.name = "AssetLoader"
		root.add_child(asset_loader)
	var game_state: Node = root.get_node_or_null("GameState")
	var created_game_state := game_state == null
	if created_game_state:
		game_state = load("res://autoload/game_state.gd").new()
		game_state.name = "GameState"
		game_state.persist_credits = false
		root.add_child(game_state)
	await process_frame
	game_state.credits = 1

	for key in TOP_INTERNAL_KEYS:
		var path := str(asset_loader.call("res_path", key))
		_check(path.begins_with("res://") and FileAccess.file_exists(path),
			"%s 使用项目内资源" % key, path)

	var canvas := Control.new()
	canvas.size = Vector2(1920, 1080)
	root.add_child(canvas)
	var credit_connections_before: int = game_state.credits_changed.get_connections().size()
	var top_bar_script = load("res://ui/top_bar.gd")
	var holder: Control = top_bar_script.add(canvas, "个人中心")
	var credit: Label = top_bar_script.add_bottom_credit(canvas)
	for i in 3:
		await process_frame

	_check(is_equal_approx(holder.size.y, 150.0), "Top 栏逻辑高度为旧版 150", str(holder.size))
	_check(holder.z_index >= 80, "Top 栏保持在场景内容上方", str(holder.z_index))
	var bg := holder.get_node_or_null("TopBarBackground") as Control
	_check(bg != null and bg.size.is_equal_approx(Vector2(1920, 150)),
		"Top 栏背景完整覆盖 1920×150", str(bg.size) if bg != null else "null")
	var title := holder.get_node_or_null("TopBarTitle") as Control
	if title != null:
		var title_center := title.position + title.size * 0.5
		_check(absf(title_center.x - 960.0) < 1.0 and absf(title_center.y - 60.0) < 1.0,
			"Top 标题位于蓝色框中央并上移 15px", str(title_center))
		_check(absf(title.size.y - 75.0) < 1.0, "Top 标题最大高度为 75", str(title.size))
	else:
		_check(false, "Top 标题节点存在")
	_check(holder.get_child_count() == 2, "不再创建右上角独立 Logo", str(holder.get_child_count()))

	var final_top_y := holder.position.y
	var initial_alpha := holder.modulate.a
	var entry_tween: Tween = top_bar_script.play_entry(holder)
	_check(entry_tween != null, "公共 Top 栏提供统一入场动画")
	_check(holder.position.y <= final_top_y - 150.0,
		"公共 Top 栏从屏幕上方开始落下", str(holder.position.y))
	_check(top_bar_script.play_entry(holder) == null, "同一 Top 栏不会重复播放入场动画")
	await create_timer(0.32).timeout
	_check(absf(holder.position.y - final_top_y) < 0.5,
		"公共 Top 栏动画结束后准确回到布局位置", str(holder.position.y))
	_check(is_equal_approx(holder.modulate.a, initial_alpha),
		"公共 Top 栏滑入期间不修改透明度", str(holder.modulate.a))
	var router_source := FileAccess.get_file_as_string("res://autoload/scene_router.gd")
	var entry_call_pos := router_source.find("TopBar.play_scene_entry(get_tree().current_scene)")
	var fade_out_pos := router_source.find("tw2.tween_property(_fade_rect, \"color:a\", 0.0, FADE_FROM_BLACK_SECONDS)")
	_check(entry_call_pos >= 0 and fade_out_pos >= 0 and entry_call_pos < fade_out_pos,
		"Top 栏与黑屏淡出并行启动，不在淡出完成后追加等待")
	var router_constants := (load("res://autoload/scene_router.gd") as Script).get_script_constant_map()
	_check(float(router_constants.get("FADE_TO_BLACK_SECONDS", 1.0)) <= 0.06
			and float(router_constants.get("FADE_FROM_BLACK_SECONDS", 1.0)) <= 0.10,
		"公共场景黑屏转场总时长不超过 160ms", str(router_constants))
	_check(router_source.contains("PREWARM_SCENE_KEYS")
			and router_source.contains("load_threaded_request")
			and router_source.contains("change_scene_to_packed"),
		"公共菜单场景后台预热并优先使用 PackedScene")

	_check(credit.text == "CREDIT：1/3", "公共 CREDIT 显示当前信用/每局需求", credit.text)
	_check(credit.get_theme_color("font_color") == Color.WHITE, "公共 CREDIT 保持白色")
	var row := canvas.get_node_or_null("BottomCreditCenter/BottomCreditRow") as HBoxContainer
	if row != null:
		var row_center_x := row.global_position.x + row.size.x * 0.5
		_check(absf(row_center_x - 960.0) < 1.0, "联网图标与 CREDIT 组合居中", str(row_center_x))
	else:
		_check(false, "公共 CREDIT 组合节点存在")

	root.remove_child(canvas)
	canvas.free()
	await process_frame
	_check(game_state.credits_changed.get_connections().size() == credit_connections_before,
		"场景释放后 CREDIT 信号连接自动清理")
	if created_game_state:
		root.remove_child(game_state)
		game_state.free()
	if created_asset_loader:
		root.remove_child(asset_loader)
		asset_loader.free()
	if _failures == 0:
		print("ALL PUBLIC MENU UI TESTS PASSED")
	else:
		print("%d PUBLIC MENU UI TEST(S) FAILED" % _failures)
	quit(_failures)
