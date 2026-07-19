extends SceneTree
## 准备流程关键帧：黑场 → 背景出现 → 底层黑幕到 70% → 判定区/HUD → READY → GO → 右退。

var _failures := 0
var _created: Array[Node] = []


func _check(condition: bool, label: String, detail := "") -> void:
	if condition:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _sample(ready: Control, seconds: float) -> void:
	ready.call("seek_for_test", seconds)


func _initialize() -> void:
	if root.get_node_or_null("AssetLoader") == null:
		var loader: Node = load("res://autoload/asset_loader.gd").new()
		loader.name = "AssetLoader"
		root.add_child(loader)
		_created.append(loader)
	await process_frame

	var ready := load("res://fx/ready_anim.gd").new() as Control
	root.add_child(ready)
	await process_frame

	var guide := ready.get_node("Guide") as Control
	var banner_glow := ready.get_node("Guide/BannerGlow") as TextureRect
	var banner := ready.get_node("Guide/Banner") as TextureRect
	var decor_a := ready.get_node("Guide/MovingDecorA") as TextureRect
	var decor_b := ready.get_node("Guide/MovingDecorB") as TextureRect
	var ready_front := ready.get_node("Guide/ReadyFront") as TextureRect
	var go_front := ready.get_node("Guide/GoFront") as TextureRect

	_check(ready.get_node_or_null("SceneDim") == null,
		"READY 根层不再持有覆盖全屏 UI 的黑幕")
	_check(banner_glow.material is CanvasItemMaterial
		and (banner_glow.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_ADD,
		"引导底板使用克制的加法柔光层")
	var banner_material := banner.material as ShaderMaterial
	_check(banner_material != null and banner_material.shader != null
		and banner_material.shader.resource_path == "res://fx/ready_banner_opaque.gdshader",
		"横幅底板使用忽略源贴图 60% Alpha 的实心材质")
	var banner_top := banner_material.get_shader_parameter("top_color") as Color
	var banner_bottom := banner_material.get_shader_parameter("bottom_color") as Color
	_check(banner_top.get_luminance() > 0.30 and banner_bottom.get_luminance() > 0.20
		and banner_top.b > banner_top.g and banner_bottom.b > banner_bottom.g,
		"实心横幅重建为中亮紫色而不是把深紫源 RGB 直接拉满",
		"top=%s bottom=%s" % [banner_top, banner_bottom])
	var decor_material_a := decor_a.material as ShaderMaterial
	var decor_material_b := decor_b.material as ShaderMaterial
	_check(decor_material_a != null and decor_material_b != null
		and decor_material_a.shader.resource_path == "res://fx/ready_banner_arrows.gdshader"
		and decor_material_b.shader.resource_path == "res://fx/ready_banner_arrows.gdshader",
		"两层移动箭头使用低 Alpha 归一化的淡紫色材质")

	_sample(ready, 0.0)
	_check(absf(float(ready.call("intro_mask_alpha")) - 1.0) <= 0.001,
		"进入游戏先保持完整黑场")
	_check(float(ready.call("receptor_progress")) == 0.0,
		"黑场阶段不显示按键判定区")
	_check(float(ready.call("hud_progress")) == 0.0,
		"黑场阶段顶部血条仍在屏幕外")

	_sample(ready, 0.95)
	var reveal_alpha := float(ready.call("intro_mask_alpha"))
	_check(reveal_alpha > 0.0 and reveal_alpha < 1.0,
		"背景以慢速从全黑中完整显现", str(reveal_alpha))

	_sample(ready, 1.45)
	_check(absf(float(ready.call("intro_mask_alpha"))) <= 0.001,
		"背景出现后保留短暂满亮度停顿")

	_sample(ready, 2.45)
	_check(absf(float(ready.call("intro_mask_alpha")) - 0.70) <= 0.01,
		"底层黑幕随后缓慢加深到 70%")

	_sample(ready, 2.54)
	var receptor_before := float(ready.call("receptor_progress"))
	_sample(ready, 2.55)
	var receptor_after := float(ready.call("receptor_progress"))
	_check(receptor_before == 0.0 and receptor_after == 1.0,
		"按键判定区到点直接满亮度显示",
		"before=%.3f after=%.3f" % [receptor_before, receptor_after])

	_sample(ready, 2.75)
	var hud_before := float(ready.call("hud_progress"))
	_sample(ready, 3.25)
	var hud_mid := float(ready.call("hud_progress"))
	_sample(ready, 3.80)
	var hud_end := float(ready.call("hud_progress"))
	_check(hud_before == 0.0 and hud_mid > 0.0 and absf(hud_end - 1.0) <= 0.001,
		"顶部血条以更慢速度从屏幕外落入",
		"before=%.3f mid=%.3f end=%.3f" % [hud_before, hud_mid, hud_end])

	_sample(ready, 4.05)
	_check(guide.position.x <= -1910.0,
		"ARE YOU READY 动画组从屏幕左侧外开始", str(guide.position.x))
	_sample(ready, 4.85)
	_check(absf(guide.position.x) <= 1.0,
		"动画组平稳进入屏幕中央", str(guide.position.x))

	_sample(ready, 5.40)
	_check(banner.visible and banner.modulate.a >= 0.999,
		"横幅完整进场后节点 Alpha 为 100%，不再半透明", str(banner.modulate.a))
	_check(ready_front.visible and ready_front.modulate.a > 0.75 and not go_front.visible,
		"ARE YOU READY 清晰出现并单独停留")
	_sample(ready, 6.00)
	_check(ready_front.visible and ready_front.modulate.a > 0.75 and not go_front.visible,
		"ARE YOU READY 保留足够阅读停顿")

	_sample(ready, 6.80)
	_check(not ready_front.visible and go_front.visible and go_front.modulate.a > 0.75,
		"停顿后再切换 GAME START")
	_sample(ready, 7.65)
	_check(guide.position.x > 0.0 and go_front.visible,
		"GAME START 随整组向右侧退场", str(guide.position.x))

	_sample(ready, 8.15)
	_check(not ready.visible and absf(float(ready.call("total_duration")) - 8.15) <= 0.001,
		"慢速右退完成后才允许游戏开始")

	root.remove_child(ready)
	ready.free()
	for node in _created:
		if is_instance_valid(node) and node.get_parent() != null:
			node.get_parent().remove_child(node)
			node.free()

	print("ALL READY SEQUENCE RESTORE TESTS PASSED" if _failures == 0 else
		"%d READY SEQUENCE RESTORE TEST(S) FAILED" % _failures)
	quit(_failures)
