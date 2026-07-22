extends SceneTree
## ESC 菜单键位设置贴图与文字分栏回归测试。
## 运行：Godot_v4.6.2-stable_win64_console.exe --headless --path . --script res://tests/test_esc_binding_layout.gd

var _failures := 0


func _check(cond: bool, name: String, detail := "") -> void:
	if cond:
		print("  PASS  %s" % name)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [name, detail])


func _initialize() -> void:
	var menu = load("res://ui/esc_menu.gd").new(false)
	root.add_child(menu)
	await process_frame
	menu.open_menu()
	menu.call("_set_tab", 3)
	await process_frame

	var content_body := menu.get("_content_body") as Control
	var button := content_body.get_node_or_null("Binding_p1_lane1") as Button if content_body != null else null
	_check(button != null, "键位按钮存在")
	if button != null:
		var icon := button.get_node_or_null("PadIcon") as TextureRect
		_check(button.clip_contents, "键位贴图被限制在按钮框内")
		_check(button.alignment == HORIZONTAL_ALIGNMENT_LEFT,
			"键位文字使用左对齐独立文本区", str(button.alignment))
		_check(icon != null, "键位贴图节点存在")
		if icon != null:
			_check(icon.size.x <= 56.0 and icon.size.y <= 56.0,
				"键位贴图缩小到不遮挡文字", str(icon.size))
			_check(icon.position.x >= 0.0 and icon.position.y >= 0.0 \
				and icon.position.x + icon.size.x <= button.size.x \
				and icon.position.y + icon.size.y <= button.size.y,
				"键位贴图完整位于按钮框内",
				"icon=%s button=%s" % [icon.get_rect(), button.get_rect()])
			var font := button.get_theme_font("font")
			var font_size := button.get_theme_font_size("font_size")
			var normal_style := button.get_theme_stylebox("normal")
			var left_margin := normal_style.get_content_margin(SIDE_LEFT)
			var right_margin := normal_style.get_content_margin(SIDE_RIGHT)
			var indent_width := font.get_string_size("            ",
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			_check(left_margin + indent_width >= icon.position.x + icon.size.x + 6.0,
				"键位文字起点与贴图保持至少 6px 间隔",
				"text_x=%.1f icon_right=%.1f" % [left_margin + indent_width,
					icon.position.x + icon.size.x])
			var lines := button.text.split("\n")
			var widest_line := 0.0
			for line in lines:
				widest_line = maxf(widest_line, font.get_string_size(line,
					HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
			_check(left_margin + widest_line + right_margin <= button.size.x,
				"键位文字完整落在按钮框内",
				"needed=%.1f available=%.1f" % [left_margin + widest_line + right_margin,
					button.size.x])
		_check(button.text.begins_with("            "),
			"普通状态文字为左侧贴图预留固定空间", button.text)

		menu.call("_start_rebind", "p1_lane1")
		_check(button.text.begins_with("            "),
			"录入状态文字仍避开左侧贴图", button.text)

	menu.close_menu()
	root.remove_child(menu)
	menu.free()
	await process_frame
	print("ALL ESC BINDING LAYOUT TESTS PASSED" if _failures == 0 else
		"%d ESC BINDING LAYOUT TEST(S) FAILED" % _failures)
	quit(_failures)
