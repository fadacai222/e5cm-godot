class_name RewardAppearanceResolver
extends RefCounted
## 将 RewardService 的装备 ID 解析成场景可直接消费的统一 PlayerAppearance。

const CatalogScript := preload("res://core/reward_catalog.gd")
const CACHE_LIMIT := 16

var _catalog := CatalogScript.new()
var _cache := {}

func resolve_current() -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var reward_service := tree.root.get_node_or_null("RewardService") if tree != null else null
	var settings_store := tree.root.get_node_or_null("SettingsStore") if tree != null else null
	var loadout: Dictionary = reward_service.current_loadout() if reward_service != null else {}
	var performance_mode := bool(settings_store.performance_mode) if settings_store != null else false
	return resolve_loadout(loadout, performance_mode)

func resolve_loadout(loadout: Dictionary, performance_mode := false) -> Dictionary:
	var normalized := _normalize_loadout(loadout)
	var cache_key := "%s|%s|%d" % [JSON.stringify(normalized), str(performance_mode), CatalogScript.CATALOG_VERSION]
	if _cache.has(cache_key):
		return (_cache[cache_key] as Dictionary).duplicate(true)
	if _cache.size() >= CACHE_LIMIT:
		_cache.clear()
	var appearance := {
		"catalog_version": CatalogScript.CATALOG_VERSION,
		"performance_mode": performance_mode,
		"loadout": normalized.duplicate(true),
		"title": _resolve_slot("title", str(normalized.get("title", "")), performance_mode),
		"avatar_frame": _resolve_slot("avatar_frame", str(normalized.get("avatar_frame", "")), performance_mode),
		"profile_card": _resolve_slot("profile_card", str(normalized.get("profile_card", "")), performance_mode),
		"settlement_signature": _resolve_slot("settlement_signature",
			str(normalized.get("settlement_signature", "")), performance_mode),
		"coin_sfx": _resolve_slot("coin_sfx", str(normalized.get("coin_sfx", "")), performance_mode),
		"menu_sfx": _resolve_slot("menu_sfx", str(normalized.get("menu_sfx", "")), performance_mode),
		"combo_theme": _resolve_slot("combo_theme", str(normalized.get("combo_theme", "")), performance_mode),
	}
	_cache[cache_key] = appearance.duplicate(true)
	return appearance

func _normalize_loadout(loadout: Dictionary) -> Dictionary:
	var result := {}
	for slot in CatalogScript.VALID_SLOTS:
		result[slot] = ""
	for raw_slot in loadout.keys():
		var canonical := _catalog.canonical_slot(str(raw_slot))
		if canonical in CatalogScript.VALID_SLOTS:
			result[canonical] = str(loadout[raw_slot])
	return result

func _resolve_slot(slot: String, requested_id: String, performance_mode: bool) -> Dictionary:
	var canonical := _catalog.canonical_slot(slot)
	if requested_id.is_empty() or not _catalog.has(requested_id):
		return _default_appearance(canonical, requested_id)
	var item := _catalog.get_item(requested_id)
	if _catalog.canonical_slot(str(item.get("slot", ""))) != canonical:
		return _default_appearance(canonical, requested_id)
	var resolved_id := requested_id
	if performance_mode:
		var variant_id := str(item.get("performance_variant", ""))
		if not variant_id.is_empty() and _catalog.has(variant_id):
			var variant := _catalog.get_item(variant_id)
			if _catalog.canonical_slot(str(variant.get("slot", ""))) == canonical:
				item = variant
				resolved_id = variant_id
	var result := item.duplicate(true)
	result["id"] = resolved_id
	result["requested_id"] = requested_id
	result["is_default"] = false
	var visual := _decode_visual(item.get("visual", {}))
	visual["reward_type"] = str(item.get("type", canonical))
	visual["rarity"] = str(item.get("rarity", "common"))
	visual["reward_id"] = resolved_id
	result["visual"] = visual
	return result

func _default_appearance(slot: String, requested_id: String) -> Dictionary:
	var visual := _decode_visual(_catalog.get_default_visual(slot))
	visual["reward_type"] = slot
	visual["rarity"] = "common"
	return {
		"id": "",
		"requested_id": requested_id,
		"slot": slot,
		"type": slot,
		"name": "默认",
		"description": "当前稳定版默认外观",
		"unlock_hint": "",
		"rarity": "common",
		"surfaces": CatalogScript.VALID_SURFACES.duplicate(),
		"is_default": true,
		"visual": visual,
	}

func _decode_visual(raw: Variant) -> Dictionary:
	var visual: Dictionary = raw.duplicate(true) if raw is Dictionary else {}
	for key in visual.keys():
		if str(key).ends_with("_color") and visual[key] is String:
			visual[key] = Color.html(str(visual[key]))
	return visual

func invalidate() -> void:
	_cache.clear()

func cache_size_for_test() -> int:
	return _cache.size()
