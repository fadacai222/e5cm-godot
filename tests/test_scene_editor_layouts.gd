extends SceneTree
## 所有用户可见场景都必须把主要布局保存进 PackedScene，确保能在 2D 编辑器拖拽。

const REQUIRED_NODES := {
	"login": [
		"EditorPreview", "Stage1Guest", "Stage1Vip", "SwipeBackground", "VipCard",
		"TopBar", "BottomCreditCenter",
	],
	"profile": [
		"EditorPreview", "ProfileAvatar", "ProfileNickname", "FancyExpFrame",
		"SpeedExpFrame", "LeaveButton", "TopBar", "BottomCreditCenter",
	],
	"mode_select": [
		"EditorPreview", "ModeBanner", "DescriptionBar", "ModePrompt", "ModeButton0",
		"ModeButton1", "ModeButton2", "ModeButton3", "ModeButton4", "TopBar",
		"BottomCreditCenter",
	],
	"submode_select": [
		"EditorPreview", "SubmodeLargeIcon", "SubmodeGrid", "PreviousPage", "NextPage",
		"PageIndicator", "TopBar", "BottomCreditCenter",
	],
	"song_select": [
		"EditorPreview", "SongGrid", "FavoriteButton", "SettingsButton", "FilterButton",
		"AllButton", "PageLabel", "FilterLabel", "RoundLabel", "TopBar",
		"BottomCreditCenter",
	],
	"loading": [
		"EditorPreview", "Cover", "Stars", "SongName", "SongMeta", "PlayerSummary",
		"LoadingLabel", "BottomCreditCenter",
	],
	"gameplay": [
		"EditorPreview", "GameplayBackground", "NoteFieldRegion", "LegacyTopHud",
		"LegacyTopHud/Score", "LegacyTopHud/Percent", "LegacyTopHud/Combo",
		"LegacyTopHud/SongTitle", "LegacyTopHud/Countdown", "LegacyTopHud/HpFill",
	],
	"settlement": [
		"EditorPreview", "SettlementPanel", "CoverClip", "SongTitle", "Miss", "Good",
		"Cool", "Perfect", "Combo", "Accuracy", "Score", "GradeSprite",
		"BottomCreditCenter",
	],
}

var _failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS  %s" % message)
	else:
		_failures += 1
		print("  FAIL  %s" % message)


func _initialize() -> void:
	for scene_name in REQUIRED_NODES:
		var scene_path := "res://scenes/%s/%s.tscn" % [scene_name, scene_name]
		var packed := load(scene_path) as PackedScene
		_check(packed != null, "%s 可加载" % scene_name)
		if packed == null:
			continue
		var instance := packed.instantiate()
		for node_path in REQUIRED_NODES[scene_name]:
			_check(instance.get_node_or_null(node_path) != null,
				"%s/%s 已保存为编辑器节点" % [scene_name, node_path])
		var preview := instance.get_node_or_null("EditorPreview") as TextureRect
		_check(preview != null and preview.texture != null,
			"%s 提供编辑器画面预览" % scene_name)
		instance.free()

	if _failures == 0:
		print("ALL SCENE EDITOR LAYOUT TESTS PASSED")
	else:
		print("%d SCENE EDITOR LAYOUT TEST(S) FAILED" % _failures)
	quit(_failures)
