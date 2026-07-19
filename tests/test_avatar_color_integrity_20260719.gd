extends SceneTree
## 圆形头像材质必须只裁 Alpha，不能重复乘纹理 RGB 导致头像发黑。
## Windows 无头模式无法稳定读回 SubViewport，因此这里锁定 Shader 色彩契约，
## Gameplay/ESC 场景实例绑定由各自视觉契约测试验证。

const AVATAR_SHADER_PATH := "res://fx/circular_avatar_mask.gdshader"

var _failures := 0


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _initialize() -> void:
	_check(ResourceLoader.exists(AVATAR_SHADER_PATH),
		"项目提供统一圆形头像遮罩 Shader")
	var code := FileAccess.get_file_as_string(AVATAR_SHADER_PATH)
	var compact := code.replace(" ", "").replace("\t", "").replace("\r", "").replace("\n", "")
	_check(not compact.contains("texture(TEXTURE,UV)")
		and not compact.contains("COLOR=")
		and not compact.contains("COLOR*"),
		"头像 Shader 不重采样、不改写 RGB，只让 Godot 原始 COLOR 通过",
		code)
	_check(code.contains("discard") and code.contains("dot(point, point) > 0.25"),
		"头像仍保持圆形 Alpha 裁切", code)
	# 用数值证明旧表达式会显著压暗中间色：0.52 会变成 0.2704。
	var source := Vector3(0.52, 0.27, 0.76)
	var old_double_sample := Vector3(source.x * source.x,
		source.y * source.y, source.z * source.z)
	_check(old_double_sample.distance_to(source) > 0.25,
		"回归样本能覆盖旧版二次乘色导致的发暗问题",
		"source=%s old=%s" % [source, old_double_sample])
	print("ALL AVATAR COLOR INTEGRITY TESTS PASSED" if _failures == 0 else
		"%d AVATAR COLOR INTEGRITY TEST(S) FAILED" % _failures)
	quit(_failures)
