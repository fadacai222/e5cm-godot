# E5CM Windows 发行打包任务清单

- [x] 打开并审计项目工作区
- [x] 确认完整曲库位置与规模（项目 `songs/`，约 51GB）
- [x] 确认 Godot、Python、Inno Setup 基础工具存在
- [x] 校验 Godot Windows 导出模板与 ImageMagick
- [x] 修复发行脚本：完整 songs 只读，不归档、不替换
- [x] 增加安全恢复逻辑：失败时恢复完整 song_index
- [x] 编写根目录 UTF-8 BOM 一键打包脚本
- [x] 生成独立打包专用 songs（每模式最多 4 首）
- [x] 导出 Windows EXE/PCK
- [x] 验证便携版完整性与运行探针
- [x] 编译 Inno Setup 安装包
- [x] 执行静默安装/运行/卸载烟雾测试
- [x] 确认原始 51GB songs 未移动、未替换
- [x] 检查 Git 忽略与暂存内容
- [x] 提交除 songs 和构建产物外的全部变更
- [x] 推送 `origin/main`
- [x] 记录产物、统计、提交哈希与验证结果

## 完成记录

- 实现提交：`d668dc5 feat: polish gameplay systems and automate Windows release`
- 远端分支：`origin/main`，推送成功
- 便携版：`release/E5CM/E5CM.exe` + `release/E5CM/E5CM.pck`
- 安装包：`release/E5CM-Setup-0.9.1.exe`
- 精选曲库：11 个可玩子模式、44 首、约 221MB；每模式最多 4 首
- 完整曲库：项目 `songs/` 保持约 51GB、10505 个歌曲目录，构建前后数量一致
- 验证：Windows 导出、发行资产探针、Inno Setup 编译、静默安装/启动/卸载烟测、一键脚本全流程通过
- Git 安全审计：未提交歌曲内容、`release/` 产物、构建暂存、凭据或异常大文件
