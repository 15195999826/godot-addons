class_name DevAgentBridge
extends Node

## JSONL command bridge for development-time Godot scene debugging.

const DevAgentInputDriverScript := preload("res://addons/lomolib/dev_agent/dev_agent_input_driver.gd")
const DevAgentInspectorScript := preload("res://addons/lomolib/dev_agent/dev_agent_inspector.gd")
const DevAgentScreenshotScript := preload("res://addons/lomolib/dev_agent/dev_agent_screenshot.gd")

@export var enabled := false
@export var session_id := ""
@export var poll_interval_sec := 0.1
@export var scene_ops_path: NodePath

var _scene_ops = null
var _session_dir := ""
var _inbox_path := ""
var _outbox_path := ""
var _screenshots_dir := ""
var _node_dumps_dir := ""
var _state_dumps_dir := ""
var _inbox_offset := 0
var _poll_elapsed := 0.0
var _is_polling := false


func _ready() -> void:
	if not _should_enable():
		set_process(false)
		return

	_setup_session()
	_resolve_scene_ops()
	set_process(true)

	print("[DevAgent] enabled")
	print("[DevAgent] session: %s" % session_id)
	print("[DevAgent] inbox: %s" % ProjectSettings.globalize_path(_inbox_path))
	print("[DevAgent] outbox: %s" % ProjectSettings.globalize_path(_outbox_path))


func _process(delta: float) -> void:
	if _is_polling:
		return

	_poll_elapsed += delta
	if _poll_elapsed < poll_interval_sec:
		return

	_poll_elapsed = 0.0
	_poll_inbox_async()


func get_session_dir() -> String:
	return _session_dir


func get_inbox_path() -> String:
	return _inbox_path


func get_outbox_path() -> String:
	return _outbox_path


func get_session_info() -> Dictionary:
	return {
		"session_id": session_id,
		"session_dir": _session_dir,
		"session_dir_global": ProjectSettings.globalize_path(_session_dir),
		"inbox": _inbox_path,
		"inbox_global": ProjectSettings.globalize_path(_inbox_path),
		"outbox": _outbox_path,
		"outbox_global": ProjectSettings.globalize_path(_outbox_path),
	}


func _should_enable() -> bool:
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	var has_dev_agent_arg := false
	for arg in args:
		if arg == "--dev-agent":
			has_dev_agent_arg = true
		if arg.begins_with("--dev-agent-session="):
			session_id = arg.trim_prefix("--dev-agent-session=")

	if has_dev_agent_arg:
		return true

	if enabled:
		return true

	if ProjectSettings.get_setting("debug/dev_agent/enabled", false) == true:
		return true

	for arg in args:
		if arg.begins_with("--dev-agent-session="):
			return true

	return false


func _setup_session() -> void:
	if session_id.strip_edges().is_empty():
		session_id = _make_session_id()

	_session_dir = "user://dev-agent/sessions/%s" % _safe_file_fragment(session_id)
	_inbox_path = "%s/inbox.jsonl" % _session_dir
	_outbox_path = "%s/outbox.jsonl" % _session_dir
	_screenshots_dir = "%s/screenshots" % _session_dir
	_node_dumps_dir = "%s/node-dumps" % _session_dir
	_state_dumps_dir = "%s/state-dumps" % _session_dir

	_ensure_dir(_screenshots_dir)
	_ensure_dir(_node_dumps_dir)
	_ensure_dir(_state_dumps_dir)
	_touch_file(_inbox_path)
	_touch_file(_outbox_path)
	_inbox_offset = _file_length(_inbox_path)


func _resolve_scene_ops() -> void:
	if scene_ops_path == NodePath():
		return

	var node := get_node_or_null(scene_ops_path)
	if node != null and node.has_method("get_supported_ops") and node.has_method("run_scene_op"):
		_scene_ops = node
	else:
		_write_outbox({
			"id": "",
			"op": "setup",
			"ok": false,
			"message": "scene_ops_path does not point to a DevAgent scene ops adapter: %s" % str(scene_ops_path),
		})


func _poll_inbox_async() -> void:
	_is_polling = true

	var file := FileAccess.open(_inbox_path, FileAccess.READ)
	if file == null:
		_write_outbox({
			"id": "",
			"op": "poll",
			"ok": false,
			"message": "failed to open inbox: %s" % _inbox_path,
		})
		_is_polling = false
		return

	file.seek(_inbox_offset)
	while not file.eof_reached():
		var line := file.get_line()
		_inbox_offset = file.get_position()
		if line.strip_edges().is_empty():
			continue
		var result := await _handle_line(line)
		_write_outbox(result)

	file.close()
	_is_polling = false


func _handle_line(line: String) -> Dictionary:
	var json := JSON.new()
	var parse_error := json.parse(line)
	if parse_error != OK:
		return {
			"id": "",
			"op": "parse",
			"ok": false,
			"message": "invalid JSONL command: %s" % json.get_error_message(),
			"data": {
				"line": line,
				"line_number": json.get_error_line(),
			},
		}

	if not json.data is Dictionary:
		return {
			"id": "",
			"op": "parse",
			"ok": false,
			"message": "command must be a JSON object",
		}

	var command := json.data as Dictionary
	return await _handle_command(command)


func _handle_command(command: Dictionary) -> Dictionary:
	var command_id := str(command.get("id", ""))
	var op := str(command.get("op", ""))
	var result: Dictionary

	match op:
		"wait_frames":
			result = await _op_wait_frames(command)
		"capture":
			result = await _op_capture(command)
		"click_at":
			result = await _op_click_at(command)
		"drag_at":
			result = await _op_drag_at(command)
		"tap_key":
			result = await _op_tap_key(command)
		"inspect_tree":
			result = _op_inspect_tree(command)
		"inspect_controls":
			result = _op_inspect_controls(command)
		"dump_node":
			result = _op_dump_node(command)
		"scene":
			result = await _op_scene(command)
		"session":
			result = {
				"ok": true,
				"message": "session info",
				"data": get_session_info(),
			}
		_:
			result = {
				"ok": false,
				"message": "unsupported op: %s" % op,
			}

	result["id"] = command_id
	result["op"] = op
	if not result.has("artifacts"):
		result["artifacts"] = []
	return result


func _op_wait_frames(command: Dictionary) -> Dictionary:
	var frames := int(command.get("frames", 1))
	var safe_frames := maxi(0, frames)
	for _i in range(safe_frames):
		await get_tree().process_frame
	return {
		"ok": true,
		"message": "waited %d frame(s)" % safe_frames,
		"data": { "frames": safe_frames },
	}


func _op_capture(command: Dictionary) -> Dictionary:
	var label := str(command.get("label", "capture"))
	var command_id := str(command.get("id", "capture"))
	var file_stem := "%s-%s" % [_safe_file_fragment(command_id), _safe_file_fragment(label)]
	var options: Dictionary = {}
	for key in ["width", "format", "quality"]:
		if command.has(key):
			options[key] = command[key]
	return await DevAgentScreenshotScript.capture_viewport(self, _screenshots_dir, file_stem, options)


func _op_click_at(command: Dictionary) -> Dictionary:
	var pos := Vector2(float(command.get("x", 0.0)), float(command.get("y", 0.0)))
	var button := DevAgentInputDriverScript.mouse_button_from_value(command.get("button", MOUSE_BUTTON_LEFT))
	return await DevAgentInputDriverScript.click_at(self, pos, button)


func _op_drag_at(command: Dictionary) -> Dictionary:
	var from_pos := Vector2(float(command.get("from_x", 0.0)), float(command.get("from_y", 0.0)))
	var to_pos := Vector2(float(command.get("to_x", 0.0)), float(command.get("to_y", 0.0)))
	var button := DevAgentInputDriverScript.mouse_button_from_value(command.get("button", MOUSE_BUTTON_LEFT))
	var steps := int(command.get("steps", 8))
	return await DevAgentInputDriverScript.drag_at(self, from_pos, to_pos, button, steps)


func _op_tap_key(command: Dictionary) -> Dictionary:
	return await DevAgentInputDriverScript.tap_key(self, str(command.get("key", "")))


func _op_inspect_tree(command: Dictionary) -> Dictionary:
	var root := _resolve_root(command)
	if root == null:
		return _root_not_found(command)

	var max_depth := int(command.get("max_depth", 8))
	var dump := DevAgentInspectorScript.inspect_tree(root, max_depth)
	var artifact := _write_json_artifact(_node_dumps_dir, _artifact_stem(command, "inspect-tree"), dump)
	return {
		"ok": artifact.get("ok", false),
		"message": "tree inspected",
		"artifacts": [artifact],
		"data": {
			"root": str(root.get_path()),
		},
	}


func _op_inspect_controls(command: Dictionary) -> Dictionary:
	var root := _resolve_root(command)
	if root == null:
		return _root_not_found(command)

	var include_hidden: bool = command.get("include_hidden", false) == true
	var dump := DevAgentInspectorScript.inspect_controls(root, include_hidden)
	var artifact := _write_json_artifact(_node_dumps_dir, _artifact_stem(command, "inspect-controls"), dump)
	return {
		"ok": artifact.get("ok", false),
		"message": "controls inspected",
		"artifacts": [artifact],
		"data": {
			"root": str(root.get_path()),
			"count": int(dump.get("count", 0)),
		},
	}


func _op_dump_node(command: Dictionary) -> Dictionary:
	var path := str(command.get("path", ""))
	var target := get_tree().root.get_node_or_null(path)
	if target == null:
		target = get_node_or_null(path)
	if target == null:
		return {
			"ok": false,
			"message": "node not found: %s" % path,
		}

	var dump := DevAgentInspectorScript.dump_node(target)
	var artifact := _write_json_artifact(_state_dumps_dir, _artifact_stem(command, "dump-node"), dump)
	return {
		"ok": artifact.get("ok", false),
		"message": "node dumped",
		"artifacts": [artifact],
		"data": {
			"path": str(target.get_path()),
		},
	}


func _op_scene(command: Dictionary) -> Dictionary:
	if _scene_ops == null:
		return {
			"ok": false,
			"message": "no DevAgentSceneOps adapter configured",
		}

	var op_name := StringName(str(command.get("name", "")))
	var args: Dictionary = {}
	if command.get("args", {}) is Dictionary:
		args = command.get("args", {}) as Dictionary

	# 等价于 sync return —— `await` 对非 coroutine 返回值是 no-op, 对 coroutine
	# 返回值则等到 yield 完成。这样 adapter 可以按 op 自由选择 sync / async
	# (例如 wait_for_idle 需要 await frame, scene_state 直接返回字典)。
	var raw: Variant = await _scene_ops.run_scene_op(op_name, args)
	var result: Dictionary = raw as Dictionary
	if not result.has("data"):
		result["data"] = {}
	result["data"]["scene_op"] = String(op_name)
	result["data"]["supported_ops"] = Array(_scene_ops.get_supported_ops())
	return result


func _resolve_root(command: Dictionary) -> Node:
	var root_path := str(command.get("root", ""))
	if root_path.is_empty():
		var current_scene := get_tree().current_scene
		if current_scene != null:
			return current_scene
		return get_tree().root

	var root := get_tree().root.get_node_or_null(root_path)
	if root != null:
		return root
	return get_node_or_null(root_path)


func _root_not_found(command: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"message": "root not found: %s" % str(command.get("root", "")),
	}


func _write_outbox(result: Dictionary) -> void:
	result["time_msec"] = Time.get_ticks_msec()
	result["session_id"] = session_id

	var file := FileAccess.open(_outbox_path, FileAccess.READ_WRITE)
	if file == null:
		printerr("[DevAgent] failed to open outbox: %s" % _outbox_path)
		return

	file.seek_end()
	file.store_line(JSON.stringify(result))
	file.flush()
	file.close()


func _write_json_artifact(user_dir: String, file_stem: String, data: Dictionary) -> Dictionary:
	_ensure_dir(user_dir)
	var user_path := "%s/%s.json" % [user_dir, _safe_file_fragment(file_stem)]
	var file := FileAccess.open(user_path, FileAccess.WRITE)
	if file == null:
		return {
			"ok": false,
			"kind": "json",
			"path": user_path,
			"global_path": ProjectSettings.globalize_path(user_path),
			"message": "failed to write JSON artifact",
		}

	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	file.close()

	var global_path := ProjectSettings.globalize_path(user_path)
	print("[DevAgent] artifact: %s" % global_path)
	return {
		"ok": true,
		"kind": "json",
		"path": user_path,
		"global_path": global_path,
	}


func _artifact_stem(command: Dictionary, fallback: String) -> String:
	var command_id := str(command.get("id", fallback))
	var label := str(command.get("label", fallback))
	return "%s-%s" % [_safe_file_fragment(command_id), _safe_file_fragment(label)]


func _ensure_dir(user_dir: String) -> void:
	var global_dir := ProjectSettings.globalize_path(user_dir)
	var error := DirAccess.make_dir_recursive_absolute(global_dir)
	if error != OK and error != ERR_ALREADY_EXISTS:
		printerr("[DevAgent] failed to create dir: %s error=%d" % [global_dir, error])


func _touch_file(user_path: String) -> void:
	if FileAccess.file_exists(user_path):
		return

	var file := FileAccess.open(user_path, FileAccess.WRITE)
	if file != null:
		file.close()


func _file_length(user_path: String) -> int:
	var file := FileAccess.open(user_path, FileAccess.READ)
	if file == null:
		return 0
	var length := file.get_length()
	file.close()
	return length


func _make_session_id() -> String:
	var now := Time.get_datetime_dict_from_system()
	return "%04d%02d%02d-%02d%02d%02d-%d" % [
		int(now.get("year", 0)),
		int(now.get("month", 0)),
		int(now.get("day", 0)),
		int(now.get("hour", 0)),
		int(now.get("minute", 0)),
		int(now.get("second", 0)),
		Time.get_ticks_msec(),
	]


func _safe_file_fragment(value: String) -> String:
	var result := value.strip_edges()
	if result.is_empty():
		result = "unnamed"

	for token in ["\\", "/", ":", "*", "?", "\"", "<", ">", "|", " "]:
		result = result.replace(token, "_")

	return result
