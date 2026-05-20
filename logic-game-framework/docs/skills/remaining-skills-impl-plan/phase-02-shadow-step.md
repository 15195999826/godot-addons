# 2 · Shadow Step #12

> 开发入口：[`../remaining-skills-impl-plan.md`](../remaining-skills-impl-plan.md)
> 上一阶段：[phase-01-chain-lightning.md](phase-01-chain-lightning.md)
> 下一阶段：[phase-03-stance.md](phase-03-stance.md)


**设计卡**：瞬移到目标"身后"，+50% 一击。

## 2.1 评审结论 + 调研结论

| 既有原语 | 现状 | 够用 |
|---|---|---|
| `battle.grid.move_occupant(from,to)` + `actor.hex_position=` | push_action:138 落地 | ✅ |
| `BattleEvents.ActorDisplacedEvent.create(...)` | push_action:141 落地 | ✅ 复用(kind=teleport) |
| `HexCoord.neighbor(direction)` / `direction_to_neighbor` | HexCoord 已有 0..5 方向体系 | ✅ |
| `CharacterActor.facing_direction` | 当前不存在 | ⚠️ 前置基础设施 |
| `ActorFacingChangedEvent` | 当前不存在 | ⚠️ 前置基础设施 |
| `HexBattleDamageAction` | strike/knockback | ✅(resolver ×1.5) |
| `ExecutionContext.execution_state` | 前置基础设施新增 | ✅ 记录本次 execution 的瞬移是否成功 |
| `FlowAction.if_` | 前置基础设施新增 | ✅ 根据 `teleport_success` 决定 HIT 是否结算 |
| `DamageAction` dead target no-op | 前置基础设施优化 | ✅ HIT 时目标已死则通用跳过 |

**已推翻旧方案**：不再用“target 六邻格里离 caster 最远的空格”近似身后。Shadow Step 作为 `logic-facing V0` 的第一个消费者，使用明确 facing：

```text
behind(target) = target.hex_position.neighbor(opposite(target.facing_direction))
```

边界：
- target 必须是 `CharacterActor`；EnvironmentActor 默认没有 facing，不作为 Shadow Step 合法目标。
- 落点选择不是“只认唯一背侧格”：先尝试背侧格，再尝试背侧左右，继续向两侧类推，最后才尝试正面格；目标周身 1 格内都被占用、被预订或出界时才 teleport 失败，caster 留在原地。
- 正面格作为最后 fallback 是 V1 刻意接受的宽松语义：技能描述仍是“优先背后”，但玩法上更倾向“尽量闪到目标身边”，不因为背侧少数格子被占就完全失败。
- HIT 阶段只检查 `shadow_step.teleport_success`，不再检查 HIT 当下 caster 是否仍在目标背后；目标后续转身 / 位移不会取消伤害。
- teleport 失败也消耗冷却：ActiveUse cost 在激活时支付，后续落点不可用属于技能 whiff，不做 refund。
- caster / target 死亡或失效不在 Shadow Step 本地 predicate 里重复处理；§0.5 会先补齐 `DamageAction` 通用 no-op 合同。
- caster 成功落地后 face target；target facing 不变。
- forced displacement 不改变 facing。

## 2.2 文件清单

| 文件 | 新建/改 |
|---|---|
| `logic/skills/shadow_step.gd` | 新建：含 `_ShadowStepTeleportAction` SkillLocalAction |
| `logic/skills/all_skills.gd` | 改(+1) |
| `tests/battle/skill_scenarios/shadow_step_scenario.gd` | 新建 |
| `docs/skills/skill-implementation-progress.md` | 改 |

依赖 §0.3 的 facing 基础设施和 §0.4 的 execution-local state；本技能不再单独引入 facing 字段 / facing event。

## 2.3 数值常量表

| 常量 | 值 | 理由 |
|---|---|---|
| CONFIG_ID | `skill_shadow_step` | |
| TIMELINE_ID | `skill_shadow_step` | |
| DAMAGE_MULT | `1.5`（caster.atk×1.5） | 设计卡 +50%；resolver 系数（非强制 crit） |
| COOLDOWN_MS | `6000.0` | gap closer + 高单发，长 CD |
| RANGE meta | `4` | gap closer 突进距离 |
| Timeline | total 500，CAST:150 HIT:300 END:500 | 先瞬移后斩；HIT 由 FlowAction 判断本次 execution 是否已成功瞬移 |

## 2.4 代码骨架

`shadow_step.gd` 内嵌 SkillLocalAction（只管瞬移；伤害交同 timeline 后续 DamageAction）：
```gdscript
class _ShadowStepTeleportAction:
	extends Action.SkillLocalAction

	func _init(target_selector: TargetSelector) -> void:
		super._init(target_selector, HexBattleShadowStep.CONFIG_ID)
		type = "shadow_step_teleport"

	func _execute_local(ctx: ExecutionContext) -> ActionResult:
		var battle: HexWorldGameplayInstance = ctx.game_state_provider
		var caster_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
		var targets := get_targets(ctx)
		ctx.set_execution_state("shadow_step.teleport_success", false)
		if battle == null or caster_id == "" or targets.is_empty():
			return ActionResult.create_success_result([], { "skipped": true })
		var caster := battle.get_character_actor(caster_id)
		var target := battle.get_character_actor(targets[0])
		if caster == null or target == null or target.is_dead():
			return ActionResult.create_success_result([], { "skipped": true })

		var from_pos := caster.hex_position
		var land := _landing_slot(target, battle)
		if land == null:
			# 目标周身 1 格内无可用落点：caster 留在原地；HIT 阶段会因 teleport_success=false 跳过伤害。
			return ActionResult.create_success_result([], { "teleported": false })

		if not battle.grid.move_occupant(from_pos, land):
			return ActionResult.create_success_result([], { "teleported": false })
		caster.hex_position = land
		ctx.set_execution_state("shadow_step.teleport_success", true)
		var dist := from_pos.distance_to(land)
		var events: Array[Dictionary] = []
		var displaced := BattleEvents.ActorDisplacedEvent.create(
			caster_id, from_pos.to_dict(), land.to_dict(),
			"teleport", caster_id, dist, 0.0, 0.0)        # 自位移：无 stagger
		events.append(ctx.event_collector.push(displaced.to_dict()))
		events.append_array(HexFacing.face_actor_toward(
			caster, target.hex_position, "shadow_step", ctx.event_collector))
		return ActionResult.create_success_result(events, { "teleported": true })

	# 目标周身 1 格内选择落点：背侧优先，再背侧左右，继续类推；无合法落点则 null。
	func _landing_slot(target: CharacterActor, battle: HexWorldGameplayInstance) -> HexCoord:
		var behind_dir := HexFacing.opposite(target.get_facing_direction())
		for dir in _landing_priority_dirs(behind_dir):
			var land := target.hex_position.neighbor(dir)
			if battle.grid.has_tile(land) and not battle.grid.is_occupied(land) and not battle.grid.is_reserved(land):
				return land
		return null

	static func _landing_priority_dirs(behind_dir: int) -> Array[int]:
		return [
			posmod(behind_dir, 6),      # 正背侧
			posmod(behind_dir - 1, 6),  # 背侧左
			posmod(behind_dir + 1, 6),  # 背侧右
			posmod(behind_dir - 2, 6),  # 侧后左
			posmod(behind_dir + 2, 6),  # 侧后右
			posmod(behind_dir + 3, 6),  # 正面，最后 fallback
		]
```

`shadow_step.gd`：
```gdscript
class_name HexBattleShadowStep
const CONFIG_ID := "skill_shadow_step"
const TIMELINE_ID := "skill_shadow_step"
const DAMAGE_MULT := 1.5
const COOLDOWN_MS := 6000.0

static var _ATK_X15: FloatResolver = Resolvers.float_fn(func(ctx: ExecutionContext) -> float:
	var oid := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
	var a := GameWorld.get_actor(oid)
	if a == null or not (a is CharacterActor):
		return 0.0
	return (a as CharacterActor).attribute_set.atk * DAMAGE_MULT)

static func _shadow_step_teleport_succeeded(ctx: ExecutionContext) -> bool:
	return bool(ctx.get_execution_state("shadow_step.teleport_success", false))

static var SHADOW_STEP_TIMELINE := TimelineData.new(TIMELINE_ID, 500.0, {
	TimelineTags.CAST: 150.0, TimelineTags.HIT: 300.0, TimelineTags.END: 500.0,
})

static var ABILITY := (AbilityConfig.builder()
	.config_id(CONFIG_ID).display_name("影袭")
	.description("瞬移到目标背侧并造成 150% 攻击力的一击")
	.ability_tags(["skill", "active", "melee", "enemy"])
	.meta(HexBattleSkillMetaKeys.RANGE, 4)
	.meta(HexBattleSkillMetaKeys.ALLOWED_TARGET_KINDS, ["Character"])
	.active_use(ActiveUseConfig.builder()
		.timeline_id(TIMELINE_ID)
		.on_tag(TimelineTags.CAST, [_ShadowStepTeleportAction.new(
			HexBattleTargetSelectors.current_target())])
		.on_tag(TimelineTags.HIT, [FlowAction.if_(
			_shadow_step_teleport_succeeded,
			[HexBattleDamageAction.new(
				HexBattleTargetSelectors.current_target(),
				_ATK_X15, BattleEvents.DamageType.PHYSICAL)]
		)])
		.condition(Condition.NoTagCondition.new(HexBattleActionLockStatus.TAG_CANT_ACT))
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(COOLDOWN_MS))
		.build())
	.build())
```
> 不新增 `TimelineTags.TELEPORT`。`CAST` tag 表示逻辑瞬移点；`HIT` tag 表示动画间隔后的伤害点。

## 2.5 scenario

map 7×3，caster[0,0] enemy_0[4,0]（B 队默认 facing=WEST，背侧为 [5,0] 且为空）。default get_actions。max_ticks 60。

| 断言 | 期望 |
|---|---|
| `ActorDisplacedEvent` 出现且 `displacement_kind=="teleport"` source=caster | size≥1 |
| caster 落点 | `[5,0]`（target facing 反方向一格） |
| caster 终态相邻 enemy_0 | `final` 位置 distance==1 |
| caster final facing | WEST（落地后 face target） |
| target final facing | WEST（Shadow Step 不改变 target facing） |
| enemy_0 受击 = atk×1.5 | `assert_float_in([atk*1.5, atk*1.5*1.5])` |

补三个边界 case：
- fallback-side：enemy_0 背侧 [5,0] 放 wall / ally / reservation，但背侧左 / 右存在空格；caster 落到优先级最高的可用邻格，`shadow_step.teleport_success=true`，后续 HIT 正常造成 Shadow Step damage。
- blocked-all-around：enemy_0 周身 6 邻格都被占、被预订或出界时不产生 teleport，caster 留在原地，`shadow_step.teleport_success=false`，因此不产生 Shadow Step damage。
- post-teleport change：如果瞬移成功后、HIT 前目标 facing 或位置被其它效果改变，Shadow Step 仍然在 HIT 尝试造成伤害；伤害条件是“传送成功”，不是“HIT 当下仍在背后”。若目标已死亡/失效，由 §0.5 的通用 DamageAction no-op 保护跳过。

## 2.6 新机制清单

**技能自身无新机制**：依赖 §0 的 `FlowAction.if_` + execution-local state + DamageAction dead-target no-op + Character logic-facing V0；位移仍复用 `ActorDisplacedEvent`。不新增 `TimelineTags.TELEPORT`，瞬移动作放在 `TimelineTags.CAST`。

## 2.7 表演层

| 接入点 | 处理 |
|---|---|
| BUFF_REGISTRY | N/A |
| StageCue | 可选复用 `melee_combo`（瞬斩感）；或不接（瞬移本身无 cue 也不红） |
| facing arrow | 由 §0.3 基础设施提供；本技能只触发 caster facing 变化 |
| default_registry / projectile | 不动 / N/A |

前端瞬移动画走既有 ActorDisplaced 订阅（push 已铺）；伤害事件在后续 HIT tag 出现，给传送动画留出短间隔。朝向箭头由 `ActorFacingChangedEvent` 驱动 visual-facing lerp/tween。若目标周身 1 格内无可用落点，不产生 displacement / damage，技能表现为本次释放 whiff。

> **评审意见**：已批准。旧的“离 caster 最远格”近似方案撤回。当前方案要求先落 §0.3 logic-facing + §0.4 execution-local state + §0.5 DamageAction no-op：Shadow Step 以 `target.facing_direction` 反方向为优先落点，在目标周身 1 格内按 `[背侧, 背左, 背右, 侧后左, 侧后右, 正面]` 查找可用格；EnvironmentActor 默认没有 facing，不是合法目标；周身 6 邻格都不可用、被占用或被预订时失败留原地且仍吃冷却；HIT 阶段通过 `FlowAction.if_(_shadow_step_teleport_succeeded, [DamageAction])` 阻止无条件伤害。
