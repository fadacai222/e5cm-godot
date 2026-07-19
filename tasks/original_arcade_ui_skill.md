# 原版街机 UI Skill

项目内可执行设计 Skill 已固化到：

`skills/original-arcade-ui/SKILL.md`

该 Skill 是后续 ESC、选歌、玩家 HUD、搜索、筛选、加载、资料页和确认弹层的唯一视觉规范。运行时实现由以下共享组件承载：

- `ui/e5_hud_frame.gd`
- `ui/e5_original_theme.gd`
- `ui/ui_kit.gd`

禁止在新页面中重新引入 Godot 默认控件皮肤、大圆角玻璃卡片或随意的紫蓝渐变。
