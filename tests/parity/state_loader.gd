extends RefCounted
## 共享状态清单读取器；拒绝缺失、重复 ID 和非 1920x1080 状态。

const EXPECTED_RESOLUTION := [1920, 1080]


func _has_expected_resolution(value: Variant) -> bool:
	return value is Array and value.size() == 2 \
		and int(value[0]) == EXPECTED_RESOLUTION[0] \
		and int(value[1]) == EXPECTED_RESOLUTION[1]


func load_manifest(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("parity manifest missing: %s" % path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("parity manifest is not an object: %s" % path)
		return {}
	var manifest: Dictionary = parsed
	if not _has_expected_resolution(manifest.get("resolution", [])):
		push_error("parity manifest must use 1920x1080")
		return {}
	var states = manifest.get("states", [])
	if not states is Array or states.is_empty():
		push_error("parity manifest states are empty")
		return {}
	var seen := {}
	for item in states:
		if not item is Dictionary:
			push_error("parity state is not an object")
			return {}
		var state: Dictionary = item
		var state_id := str(state.get("id", ""))
		if state_id.is_empty() or seen.has(state_id):
			push_error("invalid or duplicate parity state id: %s" % state_id)
			return {}
		if not _has_expected_resolution(state.get("resolution", [])):
			push_error("parity state has invalid resolution: %s" % state_id)
			return {}
		seen[state_id] = true
	return manifest


func find_state(manifest: Dictionary, state_id: String) -> Dictionary:
	for item in manifest.get("states", []):
		if item is Dictionary and str(item.get("id", "")) == state_id:
			return (item as Dictionary).duplicate(true)
	return {}


func value_at_path(value: Variant, path: String) -> Variant:
	var current: Variant = value
	for part in path.split(".", false):
		if current is Dictionary and (current as Dictionary).has(part):
			current = (current as Dictionary)[part]
		else:
			return null
	return current
