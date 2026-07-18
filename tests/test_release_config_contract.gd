extends SceneTree

var _failures := 0


func _check(condition: bool, label: String, detail := "") -> void:
	if condition:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _initialize() -> void:
	var project_text := FileAccess.get_file_as_string("res://project.godot")
	var export_text := FileAccess.get_file_as_string("res://export_presets.cfg")
	var installer_text := FileAccess.get_file_as_string("res://packaging/E5CM.iss")

	_check(project_text.contains('config/name="E5CM"'), "项目发布名称为 E5CM")
	_check(project_text.contains('config/icon="res://assets/branding/e5cm_icon.png"'),
		"项目图标使用游戏 Logo")
	_check(export_text.contains('export_path="release/E5CM/E5CM.exe"'),
		"Windows 导出路径指向干净便携版目录")
	_check(export_text.contains("songs/**") and export_text.contains("assets/e5cm_runtime/songs/**"),
		"PCK 明确排除完整曲库")
	_check(export_text.contains('application/icon="res://assets/branding/e5cm.ico"'),
		"EXE 图标使用游戏 Logo ICO")
	_check(installer_text.contains("DefaultDirName={userdocs}\\E5CM"),
		"安装包默认安装到当前用户文档目录")
	_check(installer_text.contains("{autodesktop}\\E5CM"),
		"安装包创建当前用户桌面快捷方式")
	_check(installer_text.contains("PrivilegesRequired=lowest"),
		"安装包按当前用户安装，不要求管理员权限")

	print("ALL RELEASE CONFIG CONTRACT TESTS PASSED" if _failures == 0 else
		"%d RELEASE CONFIG CONTRACT TEST(S) FAILED" % _failures)
	quit(_failures)
