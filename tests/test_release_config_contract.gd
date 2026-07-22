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
	var launcher_text := FileAccess.get_file_as_string("res://打包发行版.ps1")
	var builder_text := FileAccess.get_file_as_string("res://tools/release/build_release.py")
	var smoke_text := FileAccess.get_file_as_string("res://tools/release/smoke_installer.ps1")
	var version_manager_text := FileAccess.get_file_as_string("res://tools/release/version_manager.py")
	var version_regex := RegEx.new()
	version_regex.compile('(?m)^config/version="([^"]+)"$')
	var version_match := version_regex.search(project_text)
	var display_version := str(version_match.get_string(1)) if version_match else ""
	var file_version := "%s.0" % display_version.trim_prefix("godot-")

	_check(project_text.contains('config/name="E5CM"'), "项目发布名称为 E5CM")
	_check(project_text.contains('config/icon="res://assets/branding/e5cm_icon.png"'),
		"项目图标使用游戏 Logo")
	_check(export_text.contains('export_path="release/E5CM/E5CM.exe"'),
		"Windows 导出路径指向干净便携版目录")
	_check(export_text.contains('custom_features="e5cm_release"'),
		"Windows 导出注入可靠的正式版运行标记")
	_check(export_text.contains("songs/**") and export_text.contains("assets/e5cm_runtime/songs/**"),
		"PCK 明确排除完整曲库")
	_check(export_text.contains("assets/e5cm_runtime/song_index.json"),
		"PCK 明确排除开发机完整曲库索引")
	_check(export_text.contains('application/icon="res://assets/branding/e5cm.ico"'),
		"EXE 图标使用游戏 Logo ICO")
	_check(installer_text.contains("DefaultDirName={userdocs}\\E5CM"),
		"安装包默认安装到当前用户文档目录")
	_check(installer_text.contains("{autodesktop}\\E5CM"),
		"安装包创建当前用户桌面快捷方式")
	_check(installer_text.contains("PrivilegesRequired=lowest"),
		"安装包按当前用户安装，不要求管理员权限")
	_check(not display_version.is_empty()
			and export_text.contains('application/file_version="%s"' % file_version)
			and export_text.contains('application/product_version="%s"' % file_version)
			and installer_text.contains('#define MyAppVersion "%s"' % display_version)
			and installer_text.contains('#define MyAppFileVersion "%s"' % file_version),
		"游戏内、EXE 和安装器版本元数据保持一致", "%s / %s" % [display_version, file_version])
	_check(launcher_text.contains("version_manager.py")
			and launcher_text.contains("确认继续请输入 Y")
			and launcher_text.contains("E5CM_GODOT_CONSOLE = $Godot")
			and launcher_text.contains("-Version $ReleaseVersion"),
		"打包入口支持人工确认版本并把 Godot 路径和版本传给子流程")
	_check(builder_text.contains('E5CM_RELEASE_VERSION')
			and not builder_text.contains('VERSION = "godot-'),
		"Python 发行工具从统一版本源读取，不再写死版本")
	_check(smoke_text.contains('$Version = $env:E5CM_RELEASE_VERSION')
			and not smoke_text.contains("$Version = 'godot-"),
		"安装烟雾测试使用本次发行版本，不再写死安装包名称")
	_check(version_manager_text.contains("TEXT_SYNC_ROOTS")
			and version_manager_text.contains("replace_runtime_literals"),
		"版本管理工具同步运行时场景与契约测试中的旧版本字面量")

	print("ALL RELEASE CONFIG CONTRACT TESTS PASSED" if _failures == 0 else
		"%d RELEASE CONFIG CONTRACT TEST(S) FAILED" % _failures)
	quit(_failures)
