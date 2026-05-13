class_name DevAgentSceneOps
extends Node

## Base class for scene-specific DevAgent operations.
## Keep this layer free of game policy; adapters translate optional semantic ops.


func get_supported_ops() -> PackedStringArray:
	return PackedStringArray()


func run_scene_op(op_name: StringName, args: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"message": "unsupported scene op: %s" % String(op_name),
		"data": {
			"args": args,
			"supported_ops": Array(get_supported_ops()),
		},
	}
