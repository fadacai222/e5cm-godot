extends SceneTree
## 动态舞台五阶段觉醒系统回归。
## 运行：Godot_v4.6.2-stable_win64_console.exe --headless --path . --script res://tests/test_stage_awakening_fx_20260722.gd

var _failures := 0


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _initialize() -> void:
	var script := load("res://fx/stage_awakening_fx.gd")
	_check(script != null, "舞台觉醒控制器脚本可加载")
	if script == null:
		quit(1)
		return

	var fx = script.new()
	root.add_child(fx)
	await process_frame

	_check(fx.has_method("stage_for_combo") and fx.has_method("set_combo") \
		and fx.has_method("start_decay") and fx.has_method("reset_immediate"),
		"控制器提供阶段映射、升级、降档和立即清理接口")
	_check(int(fx.call("stage_for_combo", 0)) == 0 \
		and int(fx.call("stage_for_combo", 49)) == 0 \
		and int(fx.call("stage_for_combo", 50)) == 1 \
		and int(fx.call("stage_for_combo", 99)) == 1 \
		and int(fx.call("stage_for_combo", 100)) == 2 \
		and int(fx.call("stage_for_combo", 199)) == 2 \
		and int(fx.call("stage_for_combo", 200)) == 3 \
		and int(fx.call("stage_for_combo", 299)) == 3 \
		and int(fx.call("stage_for_combo", 300)) == 4 \
		and int(fx.call("stage_for_combo", 9999)) == 4,
		"Combo 映射严格为冷场/升温/爆发/暴走/神域五档")

	var overlay := fx.get_node_or_null("StageAwakeningOverlay") as ColorRect
	_check(overlay != null and overlay.material is ShaderMaterial,
		"舞台演出使用单层 Shader，而不是堆叠大量粒子节点")
	_check(fx.z_index == -150,
		"舞台层位于背景之上、READY 黑幕之下，不破坏纯黑开场")
	_check(overlay != null and not overlay.visible and not fx.is_processing(),
		"0 Combo 时舞台层完全休眠，不执行全屏 Shader 或逐帧逻辑")
	var shader_code := FileAccess.get_file_as_string("res://fx/stage_awakening.gdshader")
	_check(not shader_code.contains("pow(") and not shader_code.contains("exp(") \
		and not shader_code.contains("hash21"),
		"舞台 Shader 禁止每像素高代价 pow/exp/hash 组合")

	fx.call("set_combo", 50, false)
	_check(overlay != null and overlay.visible and fx.is_processing(),
		"达到 50 Combo 后才唤醒舞台渲染")
	_check(int(fx.call("current_stage_for_test")) == 1 \
		and float(fx.call("current_strength_for_test")) > 0.15,
		"50 Combo 进入升温档并出现可见环境流光")
	fx.call("set_combo", 100, false)
	_check(int(fx.call("current_stage_for_test")) == 2 \
		and float(fx.call("background_zoom_for_test")) > 1.0,
		"100 Combo 进入爆发档并开始背景推进")
	fx.call("set_combo", 200, false)
	_check(int(fx.call("current_stage_for_test")) == 3,
		"200 Combo 进入暴走档")
	fx.call("set_combo", 300, false)
	_check(int(fx.call("current_stage_for_test")) == 4 \
		and float(fx.call("background_zoom_for_test")) <= 1.03,
		"300 Combo 进入神域档且镜头推进保持克制")

	fx.call("set_music_energy", 0.82)
	fx.call("_process", 0.05)
	_check(float(fx.call("music_energy_for_test")) > 0.5,
		"真实音乐低频能量可驱动舞台脉冲")

	fx.call("set_combo", 0, false)
	_check(bool(fx.call("is_decaying")) \
		and int(fx.call("current_stage_for_test")) == 4,
		"断连后不会瞬间熄灭，而是从当前档开始降级")
	var step := float(fx.call("decay_step_seconds_for_test"))
	fx.call("_process", step + 0.01)
	_check(int(fx.call("current_stage_for_test")) == 3,
		"断连后第一步从神域降到暴走")
	fx.call("_process", step + 0.01)
	_check(int(fx.call("current_stage_for_test")) == 2,
		"断连后继续逐档降到爆发")
	fx.call("_process", step + 0.01)
	_check(int(fx.call("current_stage_for_test")) == 1,
		"断连后继续逐档降到升温")
	var fade := float(fx.call("final_fade_seconds_for_test"))
	fx.call("_process", step + fade + 0.05)
	_check(int(fx.call("current_stage_for_test")) == 0 \
		and not bool(fx.call("is_decaying")),
		"最后一档平滑淡出后恢复冷场")

	fx.call("set_combo", 300, false)
	fx.call("set_combo", 0, false)
	fx.call("_process", step * 0.52)
	for combo in [1, 2, 3, 4]:
		fx.call("set_combo", combo, false)
	fx.call("_process", step * 0.52)
	_check(int(fx.call("current_stage_for_test")) == 3,
		"断连后的低 Combo 连击不会反复重置降档计时")
	fx.call("set_combo", 100, false)
	fx.call("_process", step + 0.01)
	_check(int(fx.call("current_stage_for_test")) == 2 \
		and not bool(fx.call("is_decaying")),
		"重新打回 100 Combo 时在爆发档接住降级，不继续熄灭")

	fx.call("set_combo", 300, true)
	_check(float(fx.call("background_zoom_for_test")) <= 1.008 \
		and bool(fx.call("reduced_motion_for_test")) \
		and bool(fx.call("low_cost_mode_for_test")),
		"性能模式降低动态幅度并强制使用低成本舞台路径")
	fx.call("set_combo", 300, false)
	fx.call("update_performance_budget", 32.0, 0.9)
	_check(bool(fx.call("low_cost_mode_for_test")),
		"持续低于 52 FPS 时自动切到低成本 Shader 路径")
	fx.call("update_performance_budget", 32.0, 0.9)
	_check(bool(fx.call("overlay_disabled_by_budget_for_test")) \
		and overlay != null and not overlay.visible,
		"持续严重掉帧时本局停用全屏层，保留背景推进和原有百连反馈")
	fx.call("reset_immediate")
	_check(int(fx.call("current_stage_for_test")) == 0 \
		and is_equal_approx(float(fx.call("background_zoom_for_test")), 1.0) \
		and overlay != null and not overlay.visible and not fx.is_processing(),
		"重开或退出时可立即清理并休眠全部舞台状态")

	root.remove_child(fx)
	fx.free()
	await process_frame
	print("ALL STAGE AWAKENING TESTS PASSED" if _failures == 0 else
		"%d STAGE AWAKENING TEST(S) FAILED" % _failures)
	quit(_failures)
