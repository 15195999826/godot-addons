class_name DemoSceneAgentOps
extends "res://addons/lomolib/dev_agent/dev_agent_scene_ops.gd"

## Scene-local semantic operations for the DevAgent demo.


func get_supported_ops() -> PackedStringArray:
	return PackedStringArray([
		"select_demo_object",
		"dump_demo_state",
	])


func run_scene_op(op_name: StringName, args: Dictionary) -> Dictionary:
	var demo := get_parent()
	if demo == null or not demo.has_method("select_demo_object") or not demo.has_method("get_dev_agent_state"):
		return {
			"ok": false,
			"message": "DemoSceneAgentOps must be a child of DevAgentDemo",
		}

	match String(op_name):
		"select_demo_object":
			return demo.select_demo_object(str(args.get("id", "alpha")))
		"dump_demo_state":
			return {
				"ok": true,
				"message": "demo state dumped",
				"data": demo.get_dev_agent_state(),
			}
		_:
			return super.run_scene_op(op_name, args)
