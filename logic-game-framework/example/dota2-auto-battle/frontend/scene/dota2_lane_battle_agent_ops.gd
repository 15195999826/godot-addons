extends "res://addons/lomolib/dev_agent/dev_agent_scene_ops.gd"

## DevAgent scene-ops adapter for dota2_lane_battle.tscn — development-only.
##
## Step 0 classification: this dev scene validates **presentation / business-logic
## data flow** (autonomous ARAM lane battle: sim-nav march, HP bars, attack/death
## visual feedback, rich debug panel). There is no UI-operation→UI-update loop and
## no UX-correctness target here, so every named op is a **direct function call**
## into the scene's dev hooks (the scene's private logic clock owns realtime
## ticking; step/run ops pause it then advance the procedure deterministically —
## the right style for data-flow validation, not faked input). Genuine visual
## targets are validated via the generic `capture` op; raw `click_at`/`tap_key`/
## `inspect_*` remain available as the escape hatch.
##
## Adapter is a child of the Dota2LaneBattle scene root; delegates to its
## `dev_agent_*` methods.


func get_supported_ops() -> PackedStringArray:
	return PackedStringArray([
		"state",        # observation: full read-only snapshot
		"set_paused",   # action: {value:bool} pause/resume realtime clock
		"step_ticks",   # action: {count:int} deterministic fast-forward N logic ticks
		"run_until",    # action: {event:str,max_ticks:int} step until event kind / cap
		"restart",      # action: restart the battle
	])


func run_scene_op(op_name: StringName, args: Dictionary) -> Dictionary:
	var scene := get_parent()
	if scene == null or not scene.has_method("dev_agent_state"):
		return {
			"ok": false,
			"message": "Dota2LaneBattleAgentOps must be a child of the Dota2LaneBattle scene root",
		}

	match String(op_name):
		"state":
			return {
				"ok": true,
				"message": "scene state",
				"data": scene.dev_agent_state(),
			}
		"set_paused":
			var value: bool = bool(args.get("value", true))
			scene.dev_agent_set_paused(value)
			return {
				"ok": true,
				"message": "paused=%s" % str(value),
				"data": scene.dev_agent_state(),
			}
		"step_ticks":
			var count := int(args.get("count", 1))
			var st: Dictionary = scene.dev_agent_step_ticks(count)
			return {
				"ok": true,
				"message": "stepped %d tick(s) → tick=%d" % [int(st.get("stepped", 0)), int(st.get("tick", 0))],
				"data": st,
			}
		"run_until":
			var event_kind := str(args.get("event", ""))
			var max_ticks := int(args.get("max_ticks", 600))
			if event_kind == "":
				return { "ok": false, "message": "run_until requires args.event (a dota2 event kind)" }
			var rst: Dictionary = scene.dev_agent_run_until(event_kind, max_ticks)
			return {
				"ok": bool(rst.get("reached", false)),
				"message": "run_until '%s' reached=%s after %d tick(s)" % [
					event_kind, str(rst.get("reached", false)), int(rst.get("stepped", 0))],
				"data": rst,
			}
		"restart":
			scene.dev_agent_restart()
			return {
				"ok": true,
				"message": "battle restarted",
				"data": scene.dev_agent_state(),
			}
		_:
			return super.run_scene_op(op_name, args)
