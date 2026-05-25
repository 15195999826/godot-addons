class_name SkillPreviewDevAgentOps
extends "res://addons/lomolib/dev_agent/dev_agent_scene_ops.gd"

## Scene adapter exposing skill_preview operations to DevAgent JSONL workflow.
##
## Scene classification (per dev-agent-scene-debug-mode SKILL Step 0):
##   **Business logic / presentation** —— "验证新技能流程与表演"。AI 关心战斗
##   结果、伤害、动画/VFX, 不关心 SpinBox/Button 本身的 UX。因此所有动作 op 都
##   直调对应 SkillPreview 方法, 不走 Viewport.push_input。
##
## 实现分类:
## - **action ops (start_battle / reset_battle / replay_battle / add_enemy /
##   add_ally / ...)**: 直调 SkillPreview._on_*_pressed / _add_actor_at_next_free,
##   函数自带 _is_playing / disabled guard, 失败状态通过 setup_error / status 暴露。
## - **setup ops**: 走 SkillPreview.dev_agent_* 公共 API 做数据模型 mutation。
## - **observation ops**: 只读, 返回简单 Dictionary / Array。
## - **raw input (click_at / click_control / drag_at / tap_key)**: 来自 generic
##   bridge, 保留作为未来 UI-loop validation 的逃生口。当前业务 op 用不到。


func get_supported_ops() -> PackedStringArray:
	return PackedStringArray([
		# Action ops (直调函数, 业务/表演验证目标)
		"start_battle", "reset_battle", "replay_battle",
		"add_enemy", "add_ally",
		"enter_setup_mode",
		"wait_for_idle",
		# Deterministic replay control (定格瞬时 VFX:暂停 + 精确步进 + 截图)
		"pause_playback", "step_playback", "playback_state",
		# Setup mutation (直调 dev_agent_* API)
		"load_preset", "save_preset",
		"set_map", "set_controls",
		"add_actor", "remove_actor",
		"set_actor_pos", "set_actor_hp", "set_actor_atk", "set_actor_passives",
		"select_actor",
		"add_stone_wall", "remove_environment",
		"add_keyframe", "remove_keyframe", "set_keyframe",
		"reset_world_to_model", "show_inventory",
		# Observation
		"scene_state", "world_state", "timeline", "console_log",
		"setup_error", "list_presets", "list_skills", "control_rect",
		"inventory_state", "inventory_layout_state", "selected_actor_equipment_state",
		# Raw real-input escape hatch (留给未来 UI-loop validation)
		"click_control",
	])


func run_scene_op(op_name: StringName, args: Dictionary) -> Dictionary:
	var preview := get_parent()
	if preview == null or not preview.has_method("dev_agent_state"):
		return {
			"ok": false,
			"message": "SkillPreviewDevAgentOps must be a child of SkillPreview (the scene root node)",
		}

	var op := String(op_name)
	match op:
		# ----- Action ops (direct call, business/presentation goal) -----
		"start_battle":
			return preview.dev_agent_start_battle()
		"reset_battle":
			return preview.dev_agent_reset_battle()
		"replay_battle":
			return preview.dev_agent_replay_battle()
		"add_enemy":
			return preview.dev_agent_add_actor_team("B")
		"add_ally":
			return preview.dev_agent_add_actor_team("A")
		"enter_setup_mode":
			return preview.dev_agent_enter_setup_mode()
		"wait_for_idle":
			return await _op_wait_for_idle(preview, args)
		# ----- Deterministic replay control -----
		"pause_playback":
			return preview.dev_agent_pause_playback()
		"step_playback":
			var frames := int(args.get("frames", 0))
			var dms := float(args.get("delta_ms", 0.0))
			if frames > 0:
				dms = float(frames) * 100.0  # LOGIC_TICK_MS
			if dms <= 0.0:
				dms = 100.0  # 默认 1 逻辑帧
			return preview.dev_agent_step_playback(dms)
		"playback_state":
			return preview.dev_agent_playback_state()
		# ----- Raw real-input escape hatch -----
		"click_control":
			return await _click_unique_control(preview, str(args.get("name", "")))

		# ----- Setup mutation ops -----
		"load_preset":
			return _op_load_preset(preview, args)
		"save_preset":
			return preview.dev_agent_save_preset(str(args.get("name", "")))
		"set_map":
			return preview.dev_agent_set_map(
				int(args.get("radius", 0)),
				str(args.get("orientation", "")),
				float(args.get("hex_size", 0.0)),
			)
		"set_controls":
			return preview.dev_agent_set_controls(
				int(args.get("max_ticks", 0)),
				float(args.get("speed", 0.0)),
			)
		"add_actor":
			return preview.dev_agent_add_actor_team(str(args.get("team", "B")))
		"remove_actor":
			return preview.dev_agent_remove_actor(int(args.get("idx", -1)))
		"set_actor_pos":
			return preview.dev_agent_set_actor_pos(
				int(args.get("idx", -1)),
				int(args.get("q", 0)),
				int(args.get("r", 0)),
			)
		"set_actor_hp":
			return preview.dev_agent_set_actor_hp(
				int(args.get("idx", -1)),
				float(args.get("hp", 0.0)),
			)
		"set_actor_atk":
			return preview.dev_agent_set_actor_atk(
				int(args.get("idx", -1)),
				float(args.get("atk", 0.0)),
			)
		"set_actor_passives":
			var ids_v: Variant = args.get("ids", [])
			var ids_arr: Array = (ids_v as Array) if ids_v is Array else []
			return preview.dev_agent_set_actor_passives(int(args.get("idx", -1)), ids_arr)
		"select_actor":
			return preview.dev_agent_select_actor(int(args.get("idx", -1)))
		"add_stone_wall":
			return preview.dev_agent_add_stone_wall(
				int(args.get("q", 0)),
				int(args.get("r", 0)),
			)
		"remove_environment":
			return preview.dev_agent_remove_environment(int(args.get("idx", -1)))
		"add_keyframe":
			var target_v: Variant = args.get("target", {})
			var target_dict: Dictionary = (target_v as Dictionary) if target_v is Dictionary else {}
			return preview.dev_agent_add_keyframe(
				int(args.get("actor_idx", -1)),
				int(args.get("time_ms", 0)),
				str(args.get("skill", "")),
				target_dict,
			)
		"remove_keyframe":
			return preview.dev_agent_remove_keyframe(
				int(args.get("actor_idx", -1)),
				int(args.get("kf_idx", -1)),
			)
		"set_keyframe":
			var fields_v: Variant = args.get("fields", {})
			var fields_dict: Dictionary = (fields_v as Dictionary) if fields_v is Dictionary else {}
			return preview.dev_agent_set_keyframe(
				int(args.get("actor_idx", -1)),
				int(args.get("kf_idx", -1)),
				fields_dict,
			)
		"reset_world_to_model":
			return preview.dev_agent_reset_world_to_model()
		"show_inventory":
			return preview.dev_agent_show_inventory()

		# ----- Observation ops -----
		"scene_state":
			return {
				"ok": true,
				"message": "scene state captured",
				"data": preview.dev_agent_state(),
			}
		"world_state":
			return {
				"ok": true,
				"message": "world actors dumped",
				"data": {"actors": preview.dev_agent_world_state()},
			}
		"timeline":
			return {
				"ok": true,
				"message": "timeline summary",
				"data": preview.dev_agent_timeline_summary(int(args.get("max_events", 60))),
			}
		"console_log":
			return {
				"ok": true,
				"message": "console log captured",
				"data": {"text": preview.dev_agent_console_text(int(args.get("max_chars", 8000)))},
			}
		"setup_error":
			var err: String = preview.dev_agent_setup_error()
			return {
				"ok": err.is_empty(),
				"message": "setup_error: %s" % ("(none)" if err.is_empty() else err),
				"data": {"error": err},
			}
		"list_presets":
			return {
				"ok": true,
				"message": "preset list",
				"data": {"presets": preview.dev_agent_preset_options()},
			}
		"list_skills":
			return {
				"ok": true,
				"message": "skill ids",
				"data": preview.dev_agent_skill_ids(),
			}
		"control_rect":
			var name := str(args.get("name", ""))
			var rect: Rect2 = preview.dev_agent_named_control_rect(name)
			var has := rect.size.x > 0.0 or rect.size.y > 0.0
			return {
				"ok": has,
				"message": "rect for %s" % name if has else "control not found: %s" % name,
				"data": {
					"name": name,
					"rect": _rect_to_dict(rect),
				},
			}
		"inventory_state":
			return {
				"ok": true,
				"message": "inventory state captured",
				"data": preview.dev_agent_inventory_state(),
			}
		"inventory_layout_state":
			return {
				"ok": true,
				"message": "inventory layout captured",
				"data": preview.dev_agent_inventory_layout_state(),
			}
		"selected_actor_equipment_state":
			return {
				"ok": true,
				"message": "selected actor equipment captured",
				"data": preview.dev_agent_selected_actor_equipment_state(),
			}

		_:
			return super.run_scene_op(op_name, args)


# ----- Raw real-input dispatch (escape hatch for UI-loop validation) -----
##
## click_control 走 Viewport.push_input + 预检, 给将来需要"验证按钮点击 → UI
## 更新链路"的场景留口子。当前 skill_preview 业务 op 都走直调, 不依赖这条路径。
##
## 预检策略: push 一个 motion event 让 Godot 自己跑 gui hit-test, 等一帧, 然后
## 读 Viewport.gui_get_hovered_control() 对比是否为目标 Control。若被其它 Control
## 遮挡, 直接 ok=false 报告实际命中节点, 不再硬点 (避免静默错触发, 这是上一轮
## click_add_enemy 命中 StartButton 的根因)。
func _click_unique_control(preview: Node, unique_name: String) -> Dictionary:
	if unique_name.is_empty():
		return {"ok": false, "message": "click_control requires 'name'"}
	var target_control: Control = preview.dev_agent_resolve_unique_control(unique_name)
	if target_control == null:
		return {
			"ok": false,
			"message": "control not found: %s" % unique_name,
			"data": {"name": unique_name},
		}
	var rect := target_control.get_global_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return {
			"ok": false,
			"message": "control zero-sized: %s" % unique_name,
			"data": {"name": unique_name, "rect": _rect_to_dict(rect)},
		}
	var viewport := get_viewport()
	if viewport == null:
		return {"ok": false, "message": "no viewport for click"}
	var pos := rect.position + rect.size * 0.5

	# 预检: 推 motion, 等一帧, 读 hovered。
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	viewport.push_input(motion)
	await get_tree().process_frame
	var hovered := viewport.gui_get_hovered_control()
	if hovered != null and hovered != target_control and not target_control.is_ancestor_of(hovered):
		return {
			"ok": false,
			"message": "click target %s is blocked by another Control" % unique_name,
			"data": {
				"name": unique_name,
				"target_path": str(target_control.get_path()),
				"actually_hovered": str(hovered.get_path()),
				"click_pos": {"x": pos.x, "y": pos.y},
				"rect": _rect_to_dict(rect),
			},
		}

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = pos
	press.global_position = pos
	viewport.push_input(press)
	await get_tree().process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = pos
	release.global_position = pos
	viewport.push_input(release)
	await get_tree().process_frame
	return {
		"ok": true,
		"message": "real click on %s at (%.0f, %.0f)" % [unique_name, pos.x, pos.y],
		"data": {
			"name": unique_name,
			"rect": _rect_to_dict(rect),
			"click_pos": {"x": pos.x, "y": pos.y},
		},
	}


# ----- wait_for_idle -----
##
## 轮询 _is_playing, 等战斗 / animator 跑完。比 wait_frames 可靠 (帧速不稳时
## 不需要硬猜帧数)。timeout_frames 默认 1800 (~30s @60fps)。
func _op_wait_for_idle(preview: Node, args: Dictionary) -> Dictionary:
	var timeout_frames := maxi(1, int(args.get("timeout_frames", 1800)))
	if not preview.dev_agent_is_playing():
		return {
			"ok": true,
			"message": "already idle",
			"data": {"waited_frames": 0, "is_playing": false},
		}
	var waited := 0
	while waited < timeout_frames:
		await get_tree().process_frame
		waited += 1
		if not preview.dev_agent_is_playing():
			return {
				"ok": true,
				"message": "idle after %d frames" % waited,
				"data": {"waited_frames": waited, "is_playing": false},
			}
	return {
		"ok": false,
		"message": "timeout after %d frames; still playing" % timeout_frames,
		"data": {"waited_frames": timeout_frames, "is_playing": true},
	}


func _op_load_preset(preview: Node, args: Dictionary) -> Dictionary:
	if args.has("name") and not str(args["name"]).is_empty():
		return preview.dev_agent_load_preset_by_name(str(args["name"]))
	if args.has("index"):
		return preview.dev_agent_load_preset_by_index(int(args["index"]))
	return {"ok": false, "message": "load_preset requires 'name' or 'index'"}


func _rect_to_dict(rect: Rect2) -> Dictionary:
	return {
		"x": rect.position.x,
		"y": rect.position.y,
		"width": rect.size.x,
		"height": rect.size.y,
	}
