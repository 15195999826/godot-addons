## RtsMoveUnitsCommand - 玩家移动多单位命令 (P3.2)
##
## 走 RtsPlayerCommandQueue → procedure step 1.5 apply_due 链路。apply 流程:
##   1. 过滤 unit_ids: 取 alive + team_id == self.team_id 的 RtsUnitActor (rejected_ids 收
##      不合法的 — 已死 / 不存在 / team_id 不匹配)
##   2. 若 accepted 单位 0 → return success=false reason="no_valid_units"
##   3. 调 RtsGroupFormation.assign_offsets(N) 拿 N 个相对 target_pos 的 offset
##   4. 对 unit i: 取 controller via procedure.get_unit_runtime(unit_id);
##      controller.set_activity_chain(RtsMoveToActivity.new(target_pos + offset[i]),
##                                    override_strategy=true)
##   5. return success=true + accepted_ids + rejected_ids + offsets (debug 用)
##
## 不变量:
##   - apply 是幂等的 (调方应用一次后将命令出队, 不重复 apply)
##   - 失败的 unit 不影响 accepted 单位执行 — 部分成功也算 success=true (rejected_ids 提示)
##   - override_strategy=true 让 strategy.decide 不在 player command active 期间替换链
##
## 决策来源: phase-3-advanced.md §P3.2 + plan `spicy-enchanting-map.md` Step 3
class_name RtsMoveUnitsCommand
extends RtsPlayerCommand


# ========== 字段 ==========

## 选中的 unit_ids 数组 (调方按选中顺序传入; formation offset 按此顺序展开)。
var unit_ids: Array[String] = []

## 移动目标世界坐标 (像素)。
var target_pos: Vector2 = Vector2.ZERO

## Formation 间距 (px). 默认 30 — 与 RtsGroupFormation.assign_offsets 默认对齐。
var spacing: float = 30.0


# ========== 初始化 ==========

func _init(
	p_tick_stamp: int,
	p_team_id: int,
	p_unit_ids: Array[String],
	p_target_pos: Vector2,
	p_spacing: float = 30.0,
) -> void:
	tick_stamp = p_tick_stamp
	team_id = p_team_id
	unit_ids = p_unit_ids.duplicate()
	target_pos = p_target_pos
	spacing = p_spacing


# ========== 钩子 ==========

func apply(procedure, world) -> Dictionary:
	var rejected_ids: Array[String] = []
	var accepted_ids: Array[String] = []
	var accepted_units: Array[RtsUnitActor] = []
	for uid in unit_ids:
		var actor := world.get_actor(uid) as RtsUnitActor
		if actor == null or actor.is_dead() or actor.get_team_id() != team_id:
			rejected_ids.append(uid)
			continue
		accepted_ids.append(uid)
		accepted_units.append(actor)
	if accepted_units.is_empty():
		return {
			"success": false,
			"reason": "no_valid_units",
			"accepted_ids": accepted_ids,
			"rejected_ids": rejected_ids,
		}

	var offsets: Array[Vector2] = RtsGroupFormation.assign_offsets(accepted_units.size(), spacing)
	for i in accepted_units.size():
		var unit := accepted_units[i]
		var controller := procedure.get_unit_runtime(unit.get_id()) as RtsUnitController
		if controller == null:
			# 单位有 actor 但没 controller (smoke 没注册 runtime) — 视为 rejected, 但不阻断别的 unit
			rejected_ids.append(unit.get_id())
			accepted_ids.erase(unit.get_id())
			continue
		var unit_target: Vector2 = target_pos + offsets[i]
		var move_activity := RtsMoveToActivity.new(unit_target)
		controller.set_activity_chain(move_activity, true)

	if accepted_ids.is_empty():
		return {
			"success": false,
			"reason": "no_runtime_for_units",
			"accepted_ids": accepted_ids,
			"rejected_ids": rejected_ids,
		}

	return {
		"success": true,
		"reason": "",
		"accepted_ids": accepted_ids,
		"rejected_ids": rejected_ids,
		"target_pos": target_pos,
		"offsets_count": offsets.size(),
	}


func command_type() -> String:
	return "rts_move_units_command"


func serialize() -> Dictionary:
	var base := super.serialize()
	base["unit_ids"] = unit_ids.duplicate()
	base["target_pos_x"] = target_pos.x
	base["target_pos_y"] = target_pos.y
	base["spacing"] = spacing
	return base
