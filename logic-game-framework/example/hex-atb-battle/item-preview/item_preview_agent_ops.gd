## ItemPreviewAgentOps - DevAgent scene-specific adapter for item_preview.tscn
##
## Scene classification (per dev-agent-scene-debug-mode skill Step 0):
##   **UI operation -> UI update loop / UX correctness**
##
## 这个 scene 的核心验收 = 拖拽 / 点击 → ItemSystem.move_item → snapshot 更新。
## - 数据 setup / reset / seed → direct call (reset_sandbox / seed_items / select_actor)
## - bag / equipment slot drag/drop → real input (drag_at / click_at), 走完整
##   Control._get_drag_data → _drop_data → handle_drop 路径, 不绕过任何 UI bug
##
## Supported scene ops (与 DEV_AGENT.md 同步):
##
## Observation (read-only):
##   state                  — alias of inventory_state, 兼容 run-dev-scene skill 默认 op
##   inventory_state        — ItemPreview.get_inventory_state() dict (bag/actors/last_*)
##   layout_state           — rect / window 数据, 供 layout 验收 + drag 坐标计算
##   selected_actor_state   — 当前 selected actor 的 6 slot 详情
##
## Action / mutation:
##   reset_sandbox          — 清场 + 重新 init + 重 seed
##   seed_items             — 当前实现 alias of reset_sandbox
##   select_actor           — args: { idx: int }  (0..2)
##
## Raw real-input (走 DevAgentBridge 通用 op): click_at / drag_at / tap_key /
##   capture / inspect_controls / inspect_tree / dump_node 都在 DevAgentBridge 处理。
extends "res://addons/lomolib/dev_agent/dev_agent_scene_ops.gd"


func get_supported_ops() -> PackedStringArray:
	return PackedStringArray([
		"state",
		"inventory_state",
		"layout_state",
		"selected_actor_state",
		"reset_sandbox",
		"seed_items",
		"select_actor",
	])


func run_scene_op(op_name: StringName, args: Dictionary) -> Dictionary:
	var preview := get_parent()
	if preview == null:
		return _error("ItemPreviewAgentOps must be a child of ItemPreview")

	# 提前 sanity check: parent 必须暴露我们用到的方法。其中任何一个缺,就是
	# adapter / scene 接线 bug — fail fast 比 silent 跑下去更友好。
	for required_method in [
		"get_inventory_state", "get_layout_state", "get_selected_actor_state",
		"reset_sandbox", "seed_items", "select_actor_by_idx",
	]:
		if not preview.has_method(required_method):
			return _error("parent ItemPreview missing required method: %s" % required_method)

	match String(op_name):
		"state", "inventory_state":
			return _ok("inventory_state snapshot", preview.get_inventory_state())
		"layout_state":
			return _ok("layout_state snapshot", preview.get_layout_state())
		"selected_actor_state":
			return _ok("selected_actor_state snapshot", preview.get_selected_actor_state())
		"reset_sandbox":
			preview.reset_sandbox()
			return _ok("reset_sandbox done", preview.get_inventory_state())
		"seed_items":
			preview.seed_items()
			return _ok("seed_items done", preview.get_inventory_state())
		"select_actor":
			var idx := int(args.get("idx", -1))
			var ok := bool(preview.select_actor_by_idx(idx))
			if not ok:
				return _error("select_actor failed (invalid idx %d)" % idx, preview.get_inventory_state())
			return _ok("selected actor idx %d" % idx, preview.get_selected_actor_state())
		_:
			return super.run_scene_op(op_name, args)


# ----- helpers ---------------------------------------------------------------

func _ok(message: String, data: Variant = null) -> Dictionary:
	var result := {
		"ok": true,
		"message": message,
	}
	if data != null:
		result["data"] = data
	return result


func _error(message: String, data: Variant = null) -> Dictionary:
	var result := {
		"ok": false,
		"message": message,
	}
	if data != null:
		result["data"] = data
	return result
