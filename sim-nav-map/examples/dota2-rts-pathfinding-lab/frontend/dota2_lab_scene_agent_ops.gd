class_name Dota2LabSceneAgentOps
extends "res://addons/lomolib/dev_agent/dev_agent_scene_ops.gd"

## Scene-local DevAgent operations for the Dota2 RTS Pathfinding Lab.


func get_supported_ops() -> PackedStringArray:
	return PackedStringArray([
		"dump_scene_state",
		"export_debug_log",
	])


func run_scene_op(op_name: StringName, args: Dictionary) -> Dictionary:
	var lab := get_parent()
	if lab == null or not lab.has_method("get_dev_agent_state") or not lab.has_method("export_debug_log"):
		return {
			"ok": false,
			"message": "Dota2LabSceneAgentOps must be a child of Dota2PathfindingLab",
		}

	match String(op_name):
		"dump_scene_state":
			return {
				"ok": true,
				"message": "dota2 lab scene state dumped",
				"data": lab.get_dev_agent_state(),
			}
		"export_debug_log":
			var file_path := str(args.get("path", ""))
			var global_path := str(lab.export_debug_log(file_path))
			if global_path.is_empty():
				return {
					"ok": false,
					"message": "failed to export dota2 lab debug log",
					"data": lab.get_dev_agent_state(),
				}
			return {
				"ok": true,
				"message": "dota2 lab debug log exported",
				"artifacts": [{
					"ok": true,
					"kind": "json",
					"global_path": global_path,
				}],
				"data": lab.get_dev_agent_state(),
			}
		_:
			return super.run_scene_op(op_name, args)
