class_name RewardArtLoader
extends RefCounted
## 奖励纹理兼容加载器。称号、头像框、玩家卡均已改为纯代码绘制；仅保留显式资源兼容能力。

static func texture_from_visual(visual: Dictionary) -> Texture2D:
	var resolved := _resolve_art_spec(visual)
	var asset_path := str(resolved.get("asset", "")).strip_edges()
	if asset_path.is_empty():
		return null
	var atlas := _load_texture(asset_path)
	if atlas == null:
		return null
	var region := _region_from_value(resolved.get("region", []))
	if region.size.x <= 0.0 or region.size.y <= 0.0:
		return atlas
	var texture := AtlasTexture.new()
	texture.atlas = atlas
	texture.region = region
	texture.filter_clip = true
	return texture


static func has_valid_art(visual: Dictionary) -> bool:
	return texture_from_visual(visual) != null


static func clear_cache() -> void:
	# ResourceLoader 自带资源缓存；保留接口供测试和未来热重载调用。
	pass


static func _resolve_art_spec(visual: Dictionary) -> Dictionary:
	var explicit_asset := str(visual.get("art_asset", visual.get("texture_asset", ""))).strip_edges()
	if not explicit_asset.is_empty():
		return {
			"asset": explicit_asset,
			"region": visual.get("art_region", visual.get("texture_region", [])),
		}
	var reward_type := str(visual.get("reward_type", ""))
	if reward_type in ["title", "avatar_frame", "profile_card"]:
		return {}
	return {}


static func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var loaded := ResourceLoader.load(path)
	return loaded as Texture2D if loaded is Texture2D else null


static func _region_from_value(value: Variant) -> Rect2:
	if value is Rect2:
		return value
	if value is Array and value.size() >= 4:
		return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	if value is Dictionary:
		return Rect2(
			float(value.get("x", 0.0)),
			float(value.get("y", 0.0)),
			float(value.get("w", value.get("width", 0.0))),
			float(value.get("h", value.get("height", 0.0)))
		)
	return Rect2()
