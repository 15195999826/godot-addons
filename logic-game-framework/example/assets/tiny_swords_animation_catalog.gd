class_name TinySwordsAnimationCatalog


const ROOT: String = "res://addons/logic-game-framework/example/assets/tiny_swords"
const MANIFEST_PATH: String = ROOT + "/frame_manifest.json"
const LIBRARY_PATH: String = ROOT + "/animation_library.json"

const KEY_ASSET: String = "asset"
const KEY_SEQUENCE: String = "sequence"
const KEY_PATH: String = "path"
const KEY_SOURCE_PATH: String = "source_path"
const KEY_FRAME_SIZE: String = "frame_size"
const KEY_ROW: String = "row"
const KEY_COUNT: String = "count"
const KEY_FPS: String = "fps"
const KEY_LOOP: String = "loop"
const KEY_FRAMES: String = "frames"
const KEY_REGION: String = "region"
const KEY_STATUS: String = "status"
const KEY_CATEGORY: String = "category"
const KEY_LABEL: String = "label"
const KEY_DIRECTION: String = "direction"
const KEY_ANIMATION: String = "animation"
const KEY_FLIP_H: String = "flip_h"
const _DEFAULT_FPS: float = 8.0


static func scan() -> Dictionary:
	var manifest_entries := _load_manifest_entries()
	var entries := _apply_library(manifest_entries)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var asset_a: String = a[KEY_ASSET] as String
		var asset_b: String = b[KEY_ASSET] as String
		if asset_a == asset_b:
			return (a[KEY_SEQUENCE] as String) < (b[KEY_SEQUENCE] as String)
		return asset_a < asset_b
	)

	var by_asset: Dictionary = {}
	for entry in entries:
		var asset_name: String = entry[KEY_ASSET] as String
		if not by_asset.has(asset_name):
			by_asset[asset_name] = []
		var list: Array = by_asset[asset_name] as Array
		list.append(entry)
	return by_asset


static func get_asset_names(catalog: Dictionary) -> Array[String]:
	var names: Array[String] = []
	for key in catalog.keys():
		names.append(str(key))
	names.sort()
	return names


static func get_sequences(catalog: Dictionary, asset_name: String) -> Array[Dictionary]:
	if not catalog.has(asset_name):
		return []
	var source: Array = catalog[asset_name] as Array
	var sequences: Array[Dictionary] = []
	for entry in source:
		sequences.append(entry as Dictionary)
	return sequences


static func get_asset_status(catalog: Dictionary, asset_name: String) -> String:
	var sequences := get_sequences(catalog, asset_name)
	if sequences.is_empty():
		return "pending"
	var first_sequence: Dictionary = sequences[0]
	return first_sequence.get(KEY_STATUS, "pending") as String


static func create_frames(sequence: Dictionary) -> SpriteFrames:
	var path: String = sequence[KEY_PATH] as String
	var texture: Texture2D = load(path) as Texture2D
	Log.assert_crash(texture != null, "TinySwordsAnimationCatalog", "Failed to load texture: %s" % path)

	var frames := SpriteFrames.new()
	if frames.has_animation("default"):
		frames.remove_animation("default")
	frames.add_animation("preview")
	frames.set_animation_speed("preview", sequence[KEY_FPS] as float)
	frames.set_animation_loop("preview", sequence[KEY_LOOP] as bool)

	var frame_entries: Array = sequence[KEY_FRAMES] as Array
	for raw_frame in frame_entries:
		var frame: Dictionary = raw_frame as Dictionary
		var region_values: Array = frame[KEY_REGION] as Array
		var region_width: float = region_values[2] as float
		var region_height: float = region_values[3] as float
		if region_width <= 0.0 or region_height <= 0.0:
			region_width = texture.get_width()
			region_height = texture.get_height()
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(
			region_values[0] as float,
			region_values[1] as float,
			region_width,
			region_height
		)
		frames.add_frame("preview", atlas)
	return frames


static func _load_manifest_entries() -> Array[Dictionary]:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	Log.assert_crash(file != null, "TinySwordsAnimationCatalog", "Failed to open manifest: %s" % MANIFEST_PATH)
	var content := file.get_as_text()
	var parsed: Variant = JSON.parse_string(content)
	Log.assert_crash(parsed is Dictionary, "TinySwordsAnimationCatalog", "Invalid manifest JSON")
	var manifest: Dictionary = parsed as Dictionary
	var source_entries: Array = manifest.get("entries", []) as Array

	var entries: Array[Dictionary] = []
	for raw_entry in source_entries:
		var entry: Dictionary = raw_entry as Dictionary
		entries.append_array(_manifest_entry_to_sequences(entry))
	return entries


static func _manifest_entry_to_sequences(entry: Dictionary) -> Array[Dictionary]:
	var frames: Array = entry.get(KEY_FRAMES, []) as Array
	if frames.is_empty():
		return []

	var explicit_sequences: Array = entry.get("sequences", []) as Array
	if not explicit_sequences.is_empty():
		return _manifest_entry_to_explicit_sequences(entry, frames, explicit_sequences)

	var rows: Dictionary = {}
	for raw_frame in frames:
		var frame: Dictionary = raw_frame as Dictionary
		var row: int = frame[KEY_ROW] as int
		if not rows.has(row):
			rows[row] = []
		var row_frames: Array = rows[row] as Array
		row_frames.append(frame)

	var sequences: Array[Dictionary] = []
	var row_keys := rows.keys()
	row_keys.sort()
	for row_key in row_keys:
		var row_index: int = row_key as int
		var row_frames: Array = rows[row_index] as Array
		row_frames.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a["col"] as int) < (b["col"] as int)
		)
		if row_frames.size() <= 1:
			continue
		sequences.append({
			KEY_ASSET: _asset_name_for_entry(entry),
			KEY_SEQUENCE: _sequence_name_for_entry(entry, row_index),
			KEY_PATH: "%s/%s" % [ROOT, entry[KEY_PATH] as String],
			KEY_SOURCE_PATH: entry[KEY_PATH] as String,
			KEY_FRAME_SIZE: _array_to_vector2i(entry[KEY_FRAME_SIZE] as Array),
			KEY_ROW: row_index,
			KEY_COUNT: row_frames.size(),
			KEY_FPS: _DEFAULT_FPS,
			KEY_LOOP: true,
			KEY_FRAMES: row_frames,
		})
	return sequences


static func _manifest_entry_to_explicit_sequences(
	entry: Dictionary,
	frames: Array,
	explicit_sequences: Array
) -> Array[Dictionary]:
	var frames_by_index: Dictionary = {}
	for raw_frame in frames:
		var frame: Dictionary = raw_frame as Dictionary
		frames_by_index[frame["index"] as int] = frame

	var sequences: Array[Dictionary] = []
	for raw_sequence in explicit_sequences:
		var sequence_def: Dictionary = raw_sequence as Dictionary
		var sequence_frames: Array = []
		var indices: Array = sequence_def.get("indices", []) as Array
		for raw_index in indices:
			var frame_index: int = raw_index as int
			if frames_by_index.has(frame_index):
				sequence_frames.append(frames_by_index[frame_index])
		if sequence_frames.is_empty():
			continue
		sequences.append({
			KEY_ASSET: _asset_name_for_entry(entry),
			KEY_SEQUENCE: sequence_def.get("name", "sequence") as String,
			KEY_PATH: "%s/%s" % [ROOT, entry[KEY_PATH] as String],
			KEY_SOURCE_PATH: entry[KEY_PATH] as String,
			KEY_FRAME_SIZE: _array_to_vector2i(entry[KEY_FRAME_SIZE] as Array),
			KEY_ROW: -1,
			KEY_COUNT: sequence_frames.size(),
			KEY_FPS: _DEFAULT_FPS,
			KEY_LOOP: sequence_def.get(KEY_LOOP, true) as bool,
			KEY_FRAMES: sequence_frames,
		})
	return sequences


static func _apply_library(manifest_entries: Array[Dictionary]) -> Array[Dictionary]:
	var library := _load_library()
	if library.is_empty():
		for entry in manifest_entries:
			entry[KEY_STATUS] = "pending"
		return manifest_entries

	var manifest_by_key: Dictionary = {}
	for entry in manifest_entries:
		manifest_by_key[_entry_key(entry)] = entry

	var used_keys: Dictionary = {}
	var entries: Array[Dictionary] = []
	var accepted_assets: Array = library.get("accepted", []) as Array
	for raw_asset in accepted_assets:
		var asset_def: Dictionary = raw_asset as Dictionary
		var raw_sequences: Array = asset_def.get("sequences", []) as Array
		for raw_sequence in raw_sequences:
			var sequence_def: Dictionary = raw_sequence as Dictionary
			var sequence := _library_sequence_to_entry(asset_def, sequence_def, manifest_by_key)
			entries.append(sequence)
			var source_key := _library_sequence_key(sequence_def)
			if not source_key.is_empty():
				used_keys[source_key] = true

	if (library.get("include_pending", true) as bool):
		for entry in manifest_entries:
			var key := _entry_key(entry)
			if used_keys.has(key):
				continue
			var pending := entry.duplicate(true)
			pending[KEY_STATUS] = "pending"
			pending[KEY_CATEGORY] = _infer_category(pending.get(KEY_SOURCE_PATH, "") as String)
			pending[KEY_LABEL] = "Pending / %s" % (pending[KEY_ASSET] as String)
			pending[KEY_ASSET] = "pending/%s" % (pending[KEY_ASSET] as String)
			entries.append(pending)
	return entries


static func _library_sequence_to_entry(
	asset_def: Dictionary,
	sequence_def: Dictionary,
	manifest_by_key: Dictionary
) -> Dictionary:
	var sequence_type: String = sequence_def.get("type", "manifest") as String
	var sequence: Dictionary
	if sequence_type == "image":
		sequence = _image_library_sequence(sequence_def)
	else:
		var source_key := _library_sequence_key(sequence_def)
		Log.assert_crash(
			manifest_by_key.has(source_key),
			"TinySwordsAnimationCatalog",
			"Missing manifest sequence: %s" % source_key
		)
		var manifest_sequence: Dictionary = manifest_by_key[source_key] as Dictionary
		sequence = manifest_sequence.duplicate(true)

	sequence[KEY_ASSET] = asset_def["id"] as String
	sequence[KEY_SEQUENCE] = sequence_def["name"] as String
	sequence[KEY_STATUS] = "accepted"
	sequence[KEY_CATEGORY] = asset_def.get("category", "") as String
	sequence[KEY_LABEL] = asset_def.get("label", asset_def["id"]) as String
	sequence[KEY_FPS] = sequence_def.get(KEY_FPS, sequence.get(KEY_FPS, _DEFAULT_FPS)) as float
	sequence[KEY_LOOP] = sequence_def.get(KEY_LOOP, sequence.get(KEY_LOOP, true)) as bool
	sequence[KEY_DIRECTION] = sequence_def.get(KEY_DIRECTION, "") as String
	sequence[KEY_ANIMATION] = sequence_def.get(KEY_ANIMATION, "") as String
	sequence[KEY_FLIP_H] = sequence_def.get(KEY_FLIP_H, false) as bool
	if sequence_def.has("source_direction"):
		sequence["source_direction"] = sequence_def["source_direction"] as String
	if sequence_def.has("direction_mode"):
		sequence["direction_mode"] = sequence_def["direction_mode"] as String
	return sequence


static func _image_library_sequence(sequence_def: Dictionary) -> Dictionary:
	var source_path: String = sequence_def["path"] as String
	return {
		KEY_PATH: "%s/%s" % [ROOT, source_path],
		KEY_SOURCE_PATH: source_path,
		KEY_FRAME_SIZE: Vector2i.ZERO,
		KEY_ROW: -1,
		KEY_COUNT: 1,
		KEY_FRAMES: [{
			KEY_REGION: [0, 0, 0, 0],
		}],
	}


static func _load_library() -> Dictionary:
	if not FileAccess.file_exists(LIBRARY_PATH):
		return {}
	var file := FileAccess.open(LIBRARY_PATH, FileAccess.READ)
	Log.assert_crash(file != null, "TinySwordsAnimationCatalog", "Failed to open library: %s" % LIBRARY_PATH)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	Log.assert_crash(parsed is Dictionary, "TinySwordsAnimationCatalog", "Invalid animation library JSON")
	return parsed as Dictionary


static func _entry_key(entry: Dictionary) -> String:
	return "%s::%s" % [entry.get(KEY_SOURCE_PATH, "") as String, entry[KEY_SEQUENCE] as String]


static func _library_sequence_key(sequence_def: Dictionary) -> String:
	if (sequence_def.get("type", "manifest") as String) == "image":
		return ""
	return "%s::%s" % [
		sequence_def.get("path", "") as String,
		sequence_def.get("manifest_sequence", "") as String,
	]


static func _infer_category(source_path: String) -> String:
	if source_path.begins_with("units/"):
		return "unit"
	if source_path.begins_with("scene_objects/buildings/"):
		return "building"
	if source_path.begins_with("scene_objects/resources/"):
		return "resource"
	if source_path.begins_with("effects/"):
		return "effect"
	return "misc"


static func _asset_name_for_entry(entry: Dictionary) -> String:
	var path: String = entry[KEY_PATH] as String
	var base_dir := path.get_base_dir()
	var rows: int = entry["rows"] as int
	if rows > 1:
		return "%s/%s" % [base_dir, path.get_file().get_basename()]
	return base_dir


static func _sequence_name_for_entry(entry: Dictionary, row_index: int) -> String:
	var rows: int = entry["rows"] as int
	if rows > 1:
		return "row_%02d" % row_index
	var path: String = entry[KEY_PATH] as String
	return path.get_file().get_basename()


static func _array_to_vector2i(values: Array) -> Vector2i:
	return Vector2i(values[0] as int, values[1] as int)
