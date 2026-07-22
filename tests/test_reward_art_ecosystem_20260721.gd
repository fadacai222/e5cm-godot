extends SceneTree
## 奖励视觉生态：称号、头像框、玩家卡全部纯代码主题化，并验证流光与背包预览。

const CatalogScript := preload("res://core/reward_catalog.gd")
const ArtLoaderScript := preload("res://ui/reward_art_loader.gd")
const ThumbnailScript := preload("res://ui/reward_thumbnail.gd")
const AvatarFrameScript := preload("res://ui/reward_avatar_frame.gd")
const ProfileCardScript := preload("res://ui/reward_profile_card.gd")
const TitleBadgeScript := preload("res://ui/reward_title_badge.gd")

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
	var catalog = CatalogScript.new()
	var ids := catalog.ids()
	_check(CatalogScript.CATALOG_VERSION == 5, "奖励视觉目录升级到全代码主题 v5")
	_check(ids.size() >= 50, "奖励目录保持 50 项以上", "count=%d" % ids.size())
	var type_counts := {"title": 0, "avatar_frame": 0, "profile_card": 0}
	var rarity_counts := {"common": 0, "rare": 0, "epic": 0, "legendary": 0}
	var missing_style: Array[String] = []
	var texture_backed: Array[String] = []
	for reward_id in ids:
		var item: Dictionary = catalog.get_item(reward_id)
		var reward_type := str(item.get("type", ""))
		if type_counts.has(reward_type):
			type_counts[reward_type] = int(type_counts[reward_type]) + 1
		var rarity := str(item.get("rarity", "common"))
		if rarity_counts.has(rarity):
			rarity_counts[rarity] = int(rarity_counts[rarity]) + 1
		if reward_type not in ["title", "avatar_frame", "profile_card"]:
			continue
		var visual: Dictionary = (item.get("visual", {}) as Dictionary).duplicate(true)
		if str(visual.get("style", "")).is_empty():
			missing_style.append(reward_id)
		visual["reward_type"] = reward_type
		visual["rarity"] = rarity
		if ArtLoaderScript.texture_from_visual(visual) != null:
			texture_backed.append(reward_id)

	_check(int(type_counts.title) >= 28, "称号内容达到 28 项以上", str(type_counts))
	_check(int(type_counts.avatar_frame) >= 10, "头像框内容达到 10 项以上", str(type_counts))
	_check(int(type_counts.profile_card) >= 8, "玩家卡内容达到 8 项以上", str(type_counts))
	_check(int(rarity_counts.common) > 0 and int(rarity_counts.rare) > 0
		and int(rarity_counts.epic) > 0 and int(rarity_counts.legendary) > 0,
		"普通/稀有/史诗/传说四档奖励均有内容", str(rarity_counts))
	_check(missing_style.is_empty(), "三类视觉奖励全部具备代码主题 style", ", ".join(missing_style))
	_check(texture_backed.is_empty(),
		"称号、头像框、玩家卡均不再依赖 PNG/SVG 图集",
		", ".join(texture_backed))

	var title_ids := [
		"title_cyber_ronin", "title_frost_core", "title_ember_crown", "title_matrix_ghost",
		"title_sakura_dream", "title_void_watcher", "title_prism_oracle", "title_midas_destiny",
	]
	var title_themes := {}
	for reward_id in title_ids:
		var badge: RewardTitleBadge = TitleBadgeScript.new()
		badge.size = Vector2(260, 42)
		root.add_child(badge)
		badge.set_appearance(catalog.get_item(reward_id), 16)
		await process_frame
		title_themes[badge.theme_for_test()] = true
		_check(badge.visible and (badge.get_node("TitleBadgeArt") as TextureRect).texture == null,
			"代码称号可渲染：%s" % reward_id)
		root.remove_child(badge)
		badge.free()
	_check(title_themes.size() == 8,
		"称号八类主题互不复用", str(title_themes.keys()))

	var frame_specs := {
		"frame_neon_magenta": "cyber",
		"frame_pulse": "pulse",
		"frame_data_grid": "matrix",
		"frame_aurora": "aurora",
		"frame_flame": "flame",
		"frame_ice": "ice",
		"frame_minimal_silver": "silver",
		"frame_vip_crown": "gold",
	}
	var frame_themes := {}
	for reward_id in frame_specs:
		var frame: RewardAvatarFrame = AvatarFrameScript.new()
		root.add_child(frame)
		frame.set_appearance(catalog.get_item(reward_id))
		frame.set_avatar_target(Rect2(196, 17, 137, 137), 3.0)
		await process_frame
		var expected_theme := str(frame_specs[reward_id])
		var phase_before := float(frame.flow_phase_for_test())
		frame.call("_process", 0.5)
		var phase_after := float(frame.flow_phase_for_test())
		var hole := frame.avatar_hole_rect_for_test()
		frame_themes[frame.resolved_theme_for_test()] = true
		_check(frame.visible and frame.resolved_theme_for_test() == expected_theme
			and not frame.uses_texture_for_test()
			and (frame.get_node("AvatarFrameArt") as TextureRect).texture == null
			and hole.get_center().distance_to(Vector2(264.5, 85.5)) < 0.6
			and absf(hole.size.x - 131.0) < 1.5
			and frame.size.x > 200.0 and phase_after > phase_before,
			"代码头像框主题与流光可用：%s" % reward_id,
			"theme=%s frame=%s hole=%s phase=%f->%f" % [
				frame.resolved_theme_for_test(), frame.get_rect(), hole, phase_before, phase_after])
		root.remove_child(frame)
		frame.free()
	_check(frame_themes.size() == 8,
		"头像框覆盖赛博/脉冲/矩阵/极光/烈焰/冰晶/银色/纯金八类主题",
		str(frame_themes.keys()))

	var card_specs := {
		"card_grid_blue": "blueprint",
		"card_neon_wave": "neon",
		"card_speed_lightning": "speed",
		"card_aurora_city": "aurora",
		"card_black_gold_vip": "gold",
		"card_prism_myth": "prism",
	}
	var card_themes := {}
	for reward_id in card_specs:
		var card: Control = ProfileCardScript.new()
		card.size = Vector2(600, 200)
		root.add_child(card)
		card.call("set_appearance", catalog.get_item(reward_id))
		await process_frame
		var expected_theme := str(card_specs[reward_id])
		var phase_before := float(card.call("flow_phase_for_test"))
		card.call("_process", 0.5)
		var phase_after := float(card.call("flow_phase_for_test"))
		var actual_theme := str(card.call("resolved_theme_for_test"))
		card_themes[actual_theme] = true
		_check(card.visible and actual_theme == expected_theme
			and not bool(card.call("uses_texture_for_test"))
			and phase_after > phase_before,
			"代码玩家卡主题与双流光可用：%s" % reward_id,
			"theme=%s phase=%f->%f" % [actual_theme, phase_before, phase_after])
		root.remove_child(card)
		card.free()
	_check(card_themes.size() == 6,
		"玩家卡覆盖蓝图/霓虹/竞速/极光/黑金/棱镜六类主题",
		str(card_themes.keys()))

	var frame_thumbnail: RewardThumbnail = ThumbnailScript.new()
	frame_thumbnail.size = Vector2(128, 112)
	root.add_child(frame_thumbnail)
	frame_thumbnail.set_reward_data(catalog.get_item("frame_vip_crown"), true)
	await process_frame
	var frame_preview := frame_thumbnail.get_node_or_null("RewardAvatarFramePreview") as Control
	_check(frame_preview != null and frame_preview.visible
		and str(frame_preview.call("resolved_theme_for_test")) == "gold"
		and not bool(frame_preview.call("uses_texture_for_test")),
		"背包锁定头像框直接显示灰化代码主题与流光结构")
	root.remove_child(frame_thumbnail)
	frame_thumbnail.free()

	var card_thumbnail: RewardThumbnail = ThumbnailScript.new()
	card_thumbnail.size = Vector2(180, 112)
	root.add_child(card_thumbnail)
	card_thumbnail.set_reward_data(catalog.get_item("card_prism_myth"), true)
	await process_frame
	var card_preview := card_thumbnail.get_node_or_null("RewardProfileCardPreview") as Control
	_check(card_preview != null and card_preview.visible
		and str(card_preview.call("resolved_theme_for_test")) == "prism"
		and not bool(card_preview.call("uses_texture_for_test")),
		"背包锁定玩家卡直接显示灰化棱镜代码主题")
	root.remove_child(card_thumbnail)
	card_thumbnail.free()

	var title_thumbnail: RewardThumbnail = ThumbnailScript.new()
	title_thumbnail.size = Vector2(180, 104)
	root.add_child(title_thumbnail)
	title_thumbnail.set_reward_data(catalog.get_item("title_midas_destiny"), true)
	await process_frame
	var title_preview := title_thumbnail.get_node_or_null("RewardTitlePreview") as RewardTitleBadge
	_check(title_preview != null and title_preview.visible and title_preview.theme_for_test() == "gold",
		"背包锁定称号继续显示对应代码主题")
	root.remove_child(title_thumbnail)
	title_thumbnail.free()

	ArtLoaderScript.clear_cache()
	await process_frame
	quit(1 if failures > 0 else 0)
