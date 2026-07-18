# E5CM

E5CM 是一个使用 Godot 4.6.2 重制的 Windows 舞蹈节奏游戏项目。

## 当前版本

- 版本：`0.9.0`
- 平台：Windows x64
- 便携版：`release/E5CM/E5CM.exe`
- 安装包：`release/E5CM-Setup-0.9.0.exe`
- 默认安装位置：`%USERPROFILE%\Documents\E5CM`
- 安装后自动创建当前用户桌面快捷方式

## 精选曲库

发行版没有打包完整 51GB 曲库，而是使用固定随机种子从每个真实可玩子模式中保留最多 4 首歌：

- 真实可玩子模式：11 个
- 精选歌曲文件夹：44 个
- 精选曲库大小：约 221MB
- `竞速/情侣`、`花式/情侣` 的源目录只有空谱面占位且没有音频，因此发行版不显示这两个无效模式

完整曲库和历史开发资料只保存在本机归档目录，不进入 Git 仓库或安装包。

## 基本操作

| 操作 | 按键 |
|---|---|
| 投币 | `F` |
| 确认 / 进入 | `Enter` 或界面确认键 |
| 暂停 / 继续 | `Space` |
| 返回 / 菜单 | `Esc` |
| 自动播放 | `F6` |
| 击中音效 | `F7` |

完整流程：投币 → 选择玩家 → 登录 → 选择大模式 → 选择子模式 → 选歌 → 游戏 → 结算。

## 从源码导出

需要：

- Godot `4.6.2`
- 对应版本的 Windows 导出模板
- Inno Setup 6
- ImageMagick
- Python 3

```powershell
python tools/release/build_release.py prepare
Godot_v4.6.2-stable_win64_console.exe --headless --path . --export-release "Windows Desktop" "release/E5CM/E5CM.exe"
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" packaging/E5CM.iss
powershell -ExecutionPolicy Bypass -File tools/release/smoke_installer.ps1
```

`release/`、`.godot/`、完整歌曲内容和本机归档不会进入 Git。大型核心媒体使用 Git LFS 管理。

## 发布验证

本次发布已通过：

- Godot 编辑器无界面解析
- 10 个主场景加载冒烟
- 精选曲库索引与 44 个歌曲文件夹真实性检查
- 便携版 EXE 无界面启动
- 安装包静默安装
- 默认文件完整性检查
- 桌面快捷方式检查
- 已安装 EXE 启动
- 静默卸载与测试痕迹清理

## 注意

当前 EXE 和安装包未使用商业代码签名证书。Windows SmartScreen 可能显示“未知发布者”，这不代表安装包损坏；正式公开分发前建议购买代码签名证书并重新签名。
