extends SceneTree

const IdentityScript := preload("res://ui/player_identity_view.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String, detail := "") -> void:
	if ok:
		print("[PASS] ", message)
	else:
		failures += 1
		push_error("[FAIL] %s%s" % [message, " :: " + detail if not detail.is_empty() else ""])

func _run() -> void:
	var rewards = root.get_node("RewardService")
	rewards.persist_enabled = false
	rewards.reset_for_test()
	rewards.unlock("title_rhythm_worker", "identity-title", "test")
	rewards.unlock("frame_neon_magenta", "identity-frame", "test")
	rewards.unlock("card_grid_blue", "identity-card", "test")
	rewards.equip("title", "title_rhythm_worker")
	rewards.equip("avatar_frame", "frame_neon_magenta")
	rewards.equip("profile_card", "card_grid_blue")

	var view: PlayerIdentityView = IdentityScript.new()
	view.name = "IdentityContract"
	view.configure("compact", {"show_status": true})
	root.add_child(view)
	await process_frame
	var avatar := view.get_node_or_null("Avatar") as TextureRect
	var title_badge := view.get_node_or_null("TitleBadge") as Control
	var reward_frame := view.get_node_or_null("RewardAvatarFrame") as Control
	var card_frame := view.get_node_or_null("PlayerHudFrame") as E5HudFrame
	var card_art := view.get_node_or_null("ProfileCardArt") as TextureRect
	var card_fx := view.get_node_or_null("RewardProfileCard") as Control
	_check(view.size == Vector2(382, 112) and avatar != null and title_badge != null,
		"compact 身份组件保持选歌玩家卡尺寸与节点契约")
	var title_art := (title_badge.get_node("TitleBadgeArt") as TextureRect).texture
	var title_code := title_badge.get_node("TitleCode") as Label
	_check(title_badge.visible and (title_badge.get_node("TitleText") as Label).text == "节奏打卡员"
		and title_art == null and title_code != null
		and str(title_badge.call("theme_for_test")) == "cyber",
		"已装备称号由纯代码赛博主题绘制，不再依赖通用 PNG/SVG 底板")
	var reward_hole: Rect2 = reward_frame.call("avatar_hole_rect_for_test")
	var frame_phase_before := float(reward_frame.call("flow_phase_for_test"))
	reward_frame.call("_process", 0.5)
	var frame_phase_after := float(reward_frame.call("flow_phase_for_test"))
	_check(reward_frame.visible and reward_frame.size.x > avatar.size.x + 35.0
		and reward_hole.get_center().distance_to(avatar.get_rect().get_center()) < 1.0
		and absf(reward_hole.size.x - (avatar.size.x - 4.0)) < 2.0
		and (reward_frame.get_node("AvatarFrameArt") as TextureRect).texture == null
		and not bool(reward_frame.call("uses_texture_for_test"))
		and str(reward_frame.call("resolved_theme_for_test")) == "cyber"
		and frame_phase_after > frame_phase_before,
		"已装备头像框由纯代码赛博环包住头像，并具有环绕流光",
		"avatar=%s frame=%s hole=%s phase=%f->%f" % [
			avatar.get_rect(), reward_frame.get_rect(), reward_hole, frame_phase_before, frame_phase_after])
	_check(avatar.modulate == Color.WHITE and avatar.self_modulate == Color.WHITE,
		"奖励外观不会二次乘色导致头像发暗")
	var card_phase_before := float(card_fx.call("flow_phase_for_test"))
	card_fx.call("_process", 0.5)
	var card_phase_after := float(card_fx.call("flow_phase_for_test"))
	_check(card_frame != null and card_art != null and card_art.texture == null and not card_art.visible
		and card_fx != null and card_fx.visible
		and not bool(card_fx.call("uses_texture_for_test"))
		and str(card_fx.call("resolved_theme_for_test")) == "blueprint"
		and card_phase_after > card_phase_before
		and card_frame.fill_color.a == 0.0 and card_frame.border_color.a == 0.0,
		"玩家卡由纯代码蓝图主题绘制，并启用沿边框流光与斜向扫光",
		"phase=%f->%f frame_fill=%s" % [card_phase_before, card_phase_after, card_frame.fill_color])
	var level := view.get_node_or_null("Level") as Control
	var rank := view.get_node_or_null("Rank") as Control
	var status0 := view.get_node_or_null("StatusLight0") as Control
	_check(view.get_node_or_null("StatusLight4") != null and rank != null,
		"统一身份组件保留段位和五格状态装饰")
	_check(title_badge.position.y + title_badge.size.y <= level.position.y
		and level.position.y + level.size.y <= status0.position.y
		and rank.position.y + rank.size.y <= status0.position.y,
		"compact 称号、等级、段位与状态灯纵向分层，不再互相重叠",
		"title=%s level=%s rank=%s status=%s" % [title_badge.get_rect(), level.get_rect(), rank.get_rect(), status0.get_rect()])

	view.configure("full", {"show_progress": true, "show_status": false})
	await process_frame
	_check(view.size == Vector2(820, 400)
		and view.get_node("花式ProgressSummary").visible,
		"full 身份组件显示三模式成长摘要")

	rewards.reset_slot("title")
	await process_frame
	_check(not title_badge.visible, "取消称号后不保留空标签框")

	root.remove_child(view)
	view.free()
	rewards.reset_for_test()
	await process_frame
	quit(1 if failures > 0 else 0)
