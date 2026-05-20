# 1 · Chain Lightning #9

> 开发入口：[`../remaining-skills-impl-plan.md`](../remaining-skills-impl-plan.md)
> 上一阶段：[phase-00-infrastructure.md](phase-00-infrastructure.md)
> 下一阶段：[phase-02-shadow-step.md](phase-02-shadow-step.md)


**设计卡**：首目标魔法伤害 → 跳最近未命中敌人，每跳 -20%，最多 3 跳。

## 1.1 评审结论 + 调研结论

**原方案否决**：把 3 跳都放进 `TimelineTags.HIT` 的 Action local loop，会让伤害事件按顺序产生，但逻辑时间仍是同一 tag / 同一帧，不满足“先弹 A 再弹 B 再弹 C”的过程感。

新方向：复用 Fireball 的 **`projectileHit` → static hit timeline** 模式，但心智模型按 **on-hit 链式发射** 理解：

```text
projectileHit
  → HexBattleDamageAction 结算本跳伤害
  → DamageAction.on_hit(FlowAction.if_(has_next_chain_target, [LaunchProjectileAction.new(...)]))
```

主技能 cast timeline 只发射第一段 lightning projectile；后续每段 projectile 自己携带链路数据（第几跳、当前伤害、已命中目标、chain_id）。命中后 `DamageAction.on_hit` 只负责进入 hook；是否继续弹跳由 `FlowAction.if_` 判断；真正发射下一段仍复用 `LaunchProjectileAction`。

| 既有原语 | 现状 | 够用 |
|---|---|---|
| `LaunchProjectileAction` + `ProjectileSystem` | fireball/precise_shot 已走 projectileHit 二段触发 | ✅ 复用链式发射 |
| `ActivateInstanceConfig.trigger(ProjectileEvents.PROJECTILE_HIT_EVENT, filter)` | fireball 命中后进入 hit timeline | ✅ 复用 |
| `HexBattleDamageAction.on_hit(...)` | apply_damage 之后、post damage 之前触发 | ✅ 用作“命中后发下一段” |
| `FlowAction.if_(predicate, actions)` | 现无通用 Action flow；聚合 tag 查询已有 `Condition.HasTagCondition`，但它不是 action 分支组合器 | ⚠️ 新增小型组合器 |
| `HexBattleDamageUtils.apply_damage` + `broadcast_post_damage` | poison_tick / DamageAction 验证 pre→apply→post | ✅ |
| `HexBattlePreEvents.PreDamageEvent` | expose/shield 拦截走同一路径 | ✅ |
| `BattleEvents.DamageType.MAGICAL` | fireball 用例 | ✅ 复用 |
| `battle.get_alive_actors()` + `HexCoord.distance_to` | HexWorldGI / HexCoord 已支持找最近活敌人 | ✅ |
| Projectile `customData` | `LaunchProjectileAction` 已写入 launch params，但 projectile launched / hit event 目前未统一透传到 event payload | ⚠️ 小补丁 |

不扩展 core Timeline。动态跳数由“是否继续发下一段 projectile”决定；timeline 仍是静态声明。

## 1.2 文件清单

| 文件 | 新建/改 |
|---|---|
| `core/actions/flow_action.gd` | 前置基础设施：通用 Action 条件组合器，提供 `FlowAction.if_` |
| `stdlib/systems/projectile_system.gd` | 改：`projectileLaunched` / `projectileHit` 都透传 launch `customData` |
| `logic/skills/chain_lightning.gd` | 新建 |
| `logic/skills/all_skills.gd` | 改(+1 行注册，带 cast/hit 两条 timeline) |
| `tests/battle/skill_scenarios/chain_lightning_scenario.gd` | 新建 |
| `docs/skills/skill-implementation-progress.md` | 改(回写) |

## 1.3 数值常量表

| 常量 | 值 | 理由 |
|---|---|---|
| CONFIG_ID | `skill_chain_lightning` | 对齐 `skill_*` |
| CAST_TIMELINE_ID | `skill_chain_lightning` | 施法/发射第一段 |
| HIT_TIMELINE_ID | `skill_chain_lightning_hit` | 每次 projectileHit 后结算一跳 |
| BASE_DAMAGE | `60.0` MAGICAL | 多目标，单跳 < fireball 80 |
| MAX_HITS | `3` | 沿用本文既定语义：总命中 3 段；若设计卡要“首目标+3跳”，评审时改 4 |
| FALLOFF | `0.2`（×0.8/跳） | 设计卡 -20% |
| COOLDOWN_MS | `5000.0` | 多目标 > fireball 4000 |
| RANGE meta | `5` | 同 fireball |
| Projectile visual | `lightning` | `projectile_visualizer.gd` 已有 lightning 分支 |
| Projectile speed | `200.0` | 先同 fireball，保证有 projectileHit 驱动过程 |
| Cast Timeline | total 600，CAST:200 LAUNCH:400 END:600 | 同 fireball cast 结构 |
| Hit Timeline | total 100，END:100，`on_timeline_start` 跑 `DamageAction.on_hit(FlowAction.if_(...))` | 命中事件已到，伤害立即结算；下一段 projectile 由 FlowAction 判定后交给 LaunchProjectileAction 发射 |
| 伤害序列 | 60 / 48 / 38.4 | 60×0.8ⁿ |

## 1.4 代码骨架

`projectile_system.gd` 小补丁（通用透传，不新增 event kind）：同一份 launch `customData` 要写进 `projectileLaunched` 和 `projectileHit`。这样 scenario / replay 可以直接用 `chain_id` 关联发射与命中，而不是只能从 hit 反推。
```gdscript
func _projectile_custom_data(projectile: ProjectileActor) -> Dictionary:
	var custom_data: Variant = projectile.get_launch_params().get("customData", {})
	if custom_data is Dictionary:
		return (custom_data as Dictionary).duplicate(true)
	return {}

func _emit_launch_event(projectile: ProjectileActor, source_actor_id: String) -> void:
	# ...
	var options := {}
	var custom_data := _projectile_custom_data(projectile)
	if not custom_data.is_empty():
		options["customData"] = custom_data
	# create projectileLaunched with options

func _emit_hit_event(projectile: ProjectileActor, target_actor_id: String, hit_position: Vector3) -> void:
	# ...
	var options := {
		"damage": projectile.config.get(ProjectileActor.CFG_DAMAGE),
		"damageType": projectile.config.get(ProjectileActor.CFG_DAMAGE_TYPE),
	}
	var custom_data := _projectile_custom_data(projectile)
	if not custom_data.is_empty():
		options["customData"] = custom_data
	var event := ProjectileEvents.create_projectile_hit_event(
		projectile.id, source_actor_id, target_actor_id, hit_position,
		projectile.get_fly_time(), projectile.get_fly_distance(),
		projectile.get_ability_config_id(), options)
	# ...
```

`flow_action.gd`（通用 Action flow 组合器；不做业务逻辑）：
```gdscript
class_name FlowAction
extends RefCounted

static func if_(
	predicate: Callable,
	then_actions: Array[Action.BaseAction],
	else_actions: Array[Action.BaseAction] = []
) -> Action.BaseAction:
	return IfAction.new(predicate, then_actions, else_actions)

class IfAction:
	extends Action.FlowActionBase

	var _predicate: Callable
	var _then_actions: Array[Action.BaseAction] = []
	var _else_actions: Array[Action.BaseAction] = []

	func _init(
		predicate: Callable,
		then_actions: Array[Action.BaseAction],
		else_actions: Array[Action.BaseAction] = []
	) -> void:
		super._init(TargetSelector.new())
		type = "flow_if"
		_predicate = predicate
		_then_actions.assign(then_actions)
		_else_actions.assign(else_actions)

	func get_child_actions() -> Array[Action.BaseAction]:
		var children: Array[Action.BaseAction] = []
		children.append_array(_then_actions)
		children.append_array(_else_actions)
		return children

	func execute(ctx: ExecutionContext) -> ActionResult:
		var predicate_result: Variant = _predicate.call(ctx)
		if not (predicate_result is bool):
			Log.assert_crash("FlowAction.if_ predicate must return bool, got %s" % typeof(predicate_result))
		var passed: bool = predicate_result
		var actions := _then_actions if passed else _else_actions
		var all_events: Array[Dictionary] = []
		for action in actions:
			var result := Action.execute_child(self, action, ctx)
			if result != null and result.event_dicts is Array:
				all_events.append_array(result.event_dicts)
			if result != null and not result.success:
				return ActionResult.create_failure_result(result.failure_reason, all_events)
		return ActionResult.create_success_result(all_events, { "branch": "then" if passed else "else" })
```

`chain_lightning.gd`（Fireball 同款触发；hit timeline 内用 `DamageAction.on_hit(FlowAction.if_(...))` 链式发下一段）：
```gdscript
class_name HexBattleChainLightning
const CONFIG_ID := "skill_chain_lightning"
const CAST_TIMELINE_ID := "skill_chain_lightning"
const HIT_TIMELINE_ID := "skill_chain_lightning_hit"
const BASE_DAMAGE := 60.0
const MAX_HITS := 3
const FALLOFF := 0.2
const COOLDOWN_MS := 5000.0

static var CHAIN_LIGHTNING_CAST_TIMELINE := TimelineData.new(CAST_TIMELINE_ID, 600.0, {
	TimelineTags.CAST: 200.0, TimelineTags.LAUNCH: 400.0, TimelineTags.END: 600.0,
})

static var CHAIN_LIGHTNING_HIT_TIMELINE := TimelineData.new(HIT_TIMELINE_ID, 100.0, {
	TimelineTags.END: 100.0,
})

static func _projectile_hit_filter(event: Dictionary, ctx: AbilityLifecycleContext) -> bool:
	var data: Dictionary = event.get("customData", {}) as Dictionary
	var caster := GameWorld.get_actor(ctx.owner_actor_id)
	return ProjectileEvents.is_projectile_hit_event(event) \
		and event.get("ability_config_id", "") == CONFIG_ID \
		and ctx.ability != null \
		and not ctx.ability.is_expired() \
		and caster is CharacterActor \
		and not (caster as CharacterActor).is_dead() \
		and event.get("source_actor_id", "") == ctx.owner_actor_id \
		and data.get("ability_instance_id", "") == ctx.ability.id

static func _chain_custom_data_resolver() -> DictResolver:
	return Resolvers.dict_fn(func(ctx: ExecutionContext) -> Dictionary:
		return {
			"ability_instance_id": ctx.ability_ref.id if ctx.ability_ref != null else "",
			"chain_id": ctx.execution_info.id if ctx.execution_info != null else IdGenerator.generate("chain_lightning"),
			"hit_index": 0,
			"damage": BASE_DAMAGE,
			"visited_actor_ids": [],
		})

static func _chain_damage_resolver() -> FloatResolver:
	return Resolvers.float_fn(func(ctx: ExecutionContext) -> float:
		var data: Dictionary = ctx.get_current_event().get("customData", {}) as Dictionary
		return float(data.get("damage", BASE_DAMAGE)))

class NextChainTarget extends TargetSelector:
	func select(ctx: ExecutionContext) -> Array[String]:
		var data := HexBattleChainLightning._next_chain_data(ctx)
		var target_id: String = data.get("target_actor_id", "")
		return [target_id] if target_id != "" else []

static func _next_chain_target_selector() -> TargetSelector:
	return NextChainTarget.new()

static func _has_next_chain_target(ctx: ExecutionContext) -> bool:
	return _next_chain_data(ctx).has("target_actor_id")

static func _next_chain_projectile_config_resolver() -> DictResolver:
	return Resolvers.dict_fn(func(ctx: ExecutionContext) -> Dictionary:
		var data := _next_chain_data(ctx)
		var damage := float(data.get("damage", BASE_DAMAGE * (1.0 - FALLOFF)))
		return {
			ProjectileActor.CFG_PROJECTILE_TYPE: ProjectileActor.PROJECTILE_TYPE_MOBA,
			ProjectileActor.CFG_VISUAL_TYPE: "lightning",
			ProjectileActor.CFG_SPEED: 200.0,
			ProjectileActor.CFG_MAX_LIFETIME: 5000.0,
			ProjectileActor.CFG_HIT_DISTANCE: 30.0,
			ProjectileActor.CFG_DAMAGE: damage,
			ProjectileActor.CFG_DAMAGE_TYPE: "magical",
		})

static func _next_chain_start_position_resolver() -> Vector3Resolver:
	return Resolvers.vec3_fn(func(ctx: ExecutionContext) -> Vector3:
		var data := _next_chain_data(ctx)
		return _actor_world_pos(data.get("start_actor_id", ""), ctx.game_state_provider))

static func _next_chain_target_position_resolver() -> Vector3Resolver:
	return Resolvers.vec3_fn(func(ctx: ExecutionContext) -> Vector3:
		var data := _next_chain_data(ctx)
		return _actor_world_pos(data.get("target_actor_id", ""), ctx.game_state_provider))

static func _next_chain_custom_data_resolver() -> DictResolver:
	return Resolvers.dict_fn(func(ctx: ExecutionContext) -> Dictionary:
		var data := _next_chain_data(ctx)
		return {
			"ability_instance_id": ctx.ability_ref.id if ctx.ability_ref != null else "",
			"chain_id": data.get("chain_id", ""),
			"hit_index": int(data.get("hit_index", 0)),
			"damage": float(data.get("damage", BASE_DAMAGE)),
			"visited_actor_ids": (data.get("visited_actor_ids", []) as Array).duplicate(),
		})

static func _next_chain_data(ctx: ExecutionContext) -> Dictionary:
	var battle: HexWorldGameplayInstance = ctx.game_state_provider
	var hit_event := ctx.get_original_event()
	var damage_event := BattleEvents.DamageEvent.from_dict(ctx.get_current_event())
	if battle == null or not ProjectileEvents.is_projectile_hit_event(hit_event):
		return {}
	if ctx.ability_ref == null:
		return {}
	var chain: Dictionary = hit_event.get("customData", {}) as Dictionary
	if chain.get("ability_instance_id", "") != ctx.ability_ref.id:
		return {}
	var current_id := damage_event.target_actor_id
	var current_actor := battle.get_actor(current_id)
	var caster := battle.get_character_actor(ctx.ability_ref.owner_actor_id)
	if current_actor == null or caster == null or caster.is_dead():
		return {}
	var hit_index := int(chain.get("hit_index", 0))
	if hit_index + 1 >= MAX_HITS:
		return {}
	var visited: Array[String] = []
	visited.assign(chain.get("visited_actor_ids", []))
	if not current_id in visited:
		visited.append(current_id)
	var next_id := _nearest_unvisited_enemy(caster.get_team_id(), current_actor.hex_position, visited, battle)
	if next_id == "":
		return {}
	return {
		"start_actor_id": current_id,
		"target_actor_id": next_id,
		"chain_id": chain.get("chain_id", ""),
		"hit_index": hit_index + 1,
		"damage": float(chain.get("damage", BASE_DAMAGE)) * (1.0 - FALLOFF),
		"visited_actor_ids": visited,
	}

static func _nearest_unvisited_enemy(team: int, from_pos: HexCoord,
		visited: Array[String], battle: HexWorldGameplayInstance) -> String:
	var best := ""
	var best_d := 1 << 30
	for actor in battle.get_alive_actors():
		if actor.get_team_id() == team or actor.get_id() in visited:
			continue
		var d := from_pos.distance_to(actor.hex_position)
		if d < best_d:
			best_d = d
			best = actor.get_id()
	return best

static func _actor_world_pos(actor_id: String, battle: HexWorldGameplayInstance) -> Vector3:
	var actor := battle.get_actor(actor_id) if battle != null else null
	if actor == null or not actor.hex_position.is_valid():
		return Vector3.ZERO
	return Vector3(actor.hex_position.q, actor.hex_position.r, 0)

static var ABILITY := (AbilityConfig.builder()
	.config_id(CONFIG_ID).display_name("连锁闪电")
	.description("对目标造成魔法伤害，弹跳至最近的其他敌人，每跳衰减 20%，最多 3 跳")
	.ability_tags(["skill", "active", "ranged", "magic", "enemy", "projectile"])
	.meta(HexBattleSkillMetaKeys.RANGE, 5)
	.active_use(ActiveUseConfig.builder()
		.timeline_id(CAST_TIMELINE_ID)
		.on_timeline_start([StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val("magic_fireball"))])
		.on_tag(TimelineTags.LAUNCH, [LaunchProjectileAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.dict_val({
				ProjectileActor.CFG_PROJECTILE_TYPE: ProjectileActor.PROJECTILE_TYPE_MOBA,
				ProjectileActor.CFG_VISUAL_TYPE: "lightning",
				ProjectileActor.CFG_SPEED: 200.0,
				ProjectileActor.CFG_MAX_LIFETIME: 5000.0,
				ProjectileActor.CFG_HIT_DISTANCE: 30.0,
				ProjectileActor.CFG_DAMAGE: BASE_DAMAGE,
				ProjectileActor.CFG_DAMAGE_TYPE: "magical",
			}),
			HexBattleSkillHelpers.owner_position_resolver(),
			HexBattleSkillHelpers.target_position_resolver(),
			null,
			_chain_custom_data_resolver())])
		.condition(Condition.NoTagCondition.new(HexBattleActionLockStatus.TAG_CANT_ACT))
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(COOLDOWN_MS))
		.build())
	.component_config(ActivateInstanceConfig.builder()
		.trigger(TriggerConfig.new(
			ProjectileEvents.PROJECTILE_HIT_EVENT,
			_projectile_hit_filter))
		.timeline_id(HIT_TIMELINE_ID)
		.on_timeline_start([HexBattleDamageAction.new(
			HexBattleTargetSelectors.current_target(),
			_chain_damage_resolver(),
			BattleEvents.DamageType.MAGICAL
		).on_hit(FlowAction.if_(
			_has_next_chain_target,
			[LaunchProjectileAction.new(
				_next_chain_target_selector(),
				_next_chain_projectile_config_resolver(),
				_next_chain_start_position_resolver(),
				_next_chain_target_position_resolver(),
				null,
				_next_chain_custom_data_resolver())]
		))])
		.build())
	.build())
```
`all_skills.gd`：`arr.append(_Entry.new(HexBattleChainLightning.ABILITY, [HexBattleChainLightning.CHAIN_LIGHTNING_CAST_TIMELINE, HexBattleChainLightning.CHAIN_LIGHTNING_HIT_TIMELINE]))`

## 1.5 scenario

map 7×3，caster[0,0] + enemy_0[1,0] enemy_1[2,0] enemy_2[3,0] enemy_3[6,2]（链外）。default get_actions。max_ticks 80。

| 断言 | 期望 |
|---|---|
| enemy_0 | `assert_float_in(dmg,[60,90])` |
| enemy_1 | `[48,72]` |
| enemy_2 | `[38.4,57.6]` |
| enemy_3 | `filter_damage_events` size 0 |
| 主伤害事件数 | 3 |
| `projectileLaunched` | size 3，`visualType=="lightning"`，且每条带 `customData.ability_instance_id` / `chain_id` / `hit_index` 0/1/2 |
| `projectileHit` | size 3，且每条带 `customData.ability_instance_id` / `chain_id` / `hit_index` 0/1/2 |
| 时序 | 3 个 damage event 所在 replay frame 严格递增（证明不是同一 HIT local loop） |

crit 双值兜底（damage_action `randf()<0.1`）。收工 **重跑 5 次**。

## 1.6 新机制清单

1. **Projectile `customData` 透传**：`LaunchProjectileAction` 已把 customData 存进 projectile launch params；补 `ProjectileSystem._emit_launch_event` / `_emit_hit_event` 把该字典写入 `projectileLaunched` / `projectileHit` event。无新增 event kind，无 core Timeline 扩展。
2. **`FlowAction.if_`**：通用 Action flow 组合器，签名为 `FlowAction.if_(predicate, then_actions, else_actions := [])`；predicate 是 `func(ctx: ExecutionContext) -> bool` 的纯判断。它只负责分支与聚合 `ActionResult`，不做技能业务逻辑，不污染 `Action.BaseAction` 的 `execute()` 合同。
3. **Chain Lightning next-target helper**：链路状态来自 projectile `customData`（`ability_instance_id` / `chain_id` / `hit_index` / `damage` / `visited_actor_ids`）。是否继续弹跳由 `_has_next_chain_target(ctx)` 判断；下一段 projectile 仍由 `LaunchProjectileAction` 发射，不新增专用 projectile launcher。

实现备注：V1 的 `visited_actor_ids` 用 Array 足够（MAX_HITS=3）；如果未来扩到大场景/长链，应改成 Dictionary set 语义。`MAX_HITS` V1 是技能常量；若后续有“链长被 buff 延长”，再从 ability state / modifier 读取，不提前扩 resolver。

**Ordering 合同（已接受）**：
- 下一段 projectile 在当前跳 `apply_damage` 完成后、`broadcast_post_damage` 前发射。
- 下一段 projectile 的伤害仍必须等后续 `projectileHit` 才结算；因此不会把下一跳伤害插到当前跳 post reactions 前。
- replay 事件顺序可能是 `damage(A) → projectileLaunched(A→B) → thorn/reflect(...)`；这是本技能 V1 接受的表演语义。
- 若当前跳 post reaction 把 caster 反死，已发射的下一段 projectile 可能仍有视觉事件，但后续 hit trigger 必须因为 caster dead / ability expired / ability_instance_id 不匹配而不继续结算伤害。不能依赖“actor death 一定会移除 ability”这个隐含假设；hit filter 或 `_next_chain_data` 要显式确认 caster alive。scenario 需补这个边界回归。

明确不做：不新增 dynamic Timeline tag，不新增全局 tick 分支，不从 EventCollector 反查历史事件驱动逻辑。
同时不修改 `LaunchProjectileAction` 的空 `TargetSelector` 语义；Chain Lightning 的终止条件由外层 `FlowAction.if_` 表达，避免把 actor-target-only 语义写进通用 projectile launch primitive。

## 1.7 表演层

| 接入点 | 处理 |
|---|---|
| BUFF_REGISTRY | N/A |
| StageCue | 起手复用 `magic_fireball`（§7.3，无专属闪电资产不编新名） |
| default_registry | 不动 |
| projectile | 复用 `visualType="lightning"`；无需新 visualizer |

链锁折线特效由连续 `projectileLaunched/projectileHit` 事件自然驱动；scenario 只读逻辑事件，不要求专属闪电资产。

> **评审意见**：原 Action local loop 方案不通过；专用 `LaunchNextChainProjectileAction` 也撤回。当前方案收敛为 `projectileHit -> DamageAction.on_hit -> FlowAction.if_(has_next_chain_target, [LaunchProjectileAction])`。落码前需重点确认 `FlowAction.if_` 不改变既有 Action 执行合同，`customData` 透传只影响 projectile event payload，不改变既有 fireball/precise_shot 行为；并补 “post reaction 反死 caster 后不继续结算下一跳伤害” 回归。
