# 3 · Stance: Wrath/Calm #14

> 开发入口：[`../remaining-skills-impl-plan.md`](../remaining-skills-impl-plan.md)
> 上一阶段：[phase-02-shadow-step.md](phase-02-shadow-step.md)
> 下一阶段：[phase-04-demon-form.md](phase-04-demon-form.md)


**设计卡**：两姿态主动切换。Wrath 造伤+50%/受伤+50%；Calm 造伤-25%/受伤-25%。

## 3.1 调研结论 + 范式

**方案更新**：Stance 不再拆成 `skill_stance + buff_stance_wrath + buff_stance_calm` 三个 Ability。姿态是 `skill_stance` 自身拥有的运行时状态，用 owner 的 `AbilitySet.tag_container` loose tag 记录：

| tag | 语义 |
|---|---|
| `stance:skill_stance:wrath` | Wrath 当前激活 |
| `stance:skill_stance:calm` | Calm 当前激活 |

`skill_stance` 是一个主动 Ability，同时组合三类现有/基础设施 component：
- grant 后默认进入 Wrath。
- 主动释放时切换 loose tag：Wrath → Calm；Calm → Wrath。
- outgoing / incoming 伤害修正由 `skill_stance` 自己挂的 `PreEventConfig` 根据当前 stance tag 决定。

这避免了两个 buff Ability 互斥，也避免把 Wrath / Calm 塞进 buff UI 的 positive / negative 分类。replay 仍能看到 tag change，因为 `RecordingUtils.record_tag_changes()` 已订阅 `AbilitySet.tag_container`。

无 outgoing_damage_amp 属性。两侧都走 **PreDamageEvent 修改通路**，注册入口是 `skill_stance` 自己挂的 `PreEventConfig`：
- 受伤 ±%：incoming `PreEventConfig` 过滤 `target_actor_id==owner` → 读 stance tag → `Modification.multiply("damage", k)`
- 造伤 ±%：outgoing `PreEventConfig` 过滤 `source_actor_id==owner` → 读 stance tag → `Modification.multiply("damage", k)`

**生命周期合同**：stance tags 是 loose tag，必须由 `skill_stance` 自己负责生命周期清理。通过 §0.6 的 `NoInstanceConfig.on_apply_actions/on_remove_actions` 表达：grant 时加默认 Wrath，remove 时清 Wrath / Calm。切换逻辑仍由 `LooseTagAction` + `FlowAction.if_` 组合表达。

**唯一性合同(V1 受控 + guardrail)**：当前测试 / 装备路径由我们控制，同一 actor 不会拥有多个 `skill_stance` 实例，因此不阻塞技能落码。但 stance tags 是 loose tag，多实例会互相污染：一个实例 remove 时会清掉另一个实例仍在使用的 Wrath/Calm。进入非受控 loadout / AI-generated grant 前，必须补最小 `AbilityConfig.unique_by_config: bool` 或 `grant_unique_ability` helper；`skill_stance` 标 true，grant 时发现同 config 已存在则 reject 或 replace，并打 warning。

## 3.2 文件清单

| 文件 | 新建/改 |
|---|---|
| `logic/skills/stance.gd` | 新建：含 `skill_stance` 配置、tag lifecycle actions、PreDamage handlers、tag 切换组合 |
| `logic/skills/all_skills.gd` | 改(+1：只注册 `skill_stance`) |
| `core/abilities/core/ability_config.gd` / `ability_set.gd` | 可同批或后续 guard：`unique_by_config` 最小 bool + grant 检查；受控 V1 不作为 Stance scenario 前置 |
| `tests/battle/skill_scenarios/stance_scenario.gd` | 新建 |
| `docs/skills/skill-implementation-progress.md` | 改 |

## 3.3 数值常量表

| 常量 | 值 |
|---|---|
| 技能 CONFIG_ID | `skill_stance` |
| WRATH_TAG | `stance:skill_stance:wrath` |
| CALM_TAG | `stance:skill_stance:calm` |
| Wrath 造伤/受伤 mult | `1.5` / `1.5` |
| Calm 造伤/受伤 mult | `0.75` / `0.75` |
| 姿态 duration | 永久 loose tag（随 `skill_stance` grant/remove 生命周期初始化与清理） |
| 技能 COOLDOWN_MS | `2000.0`（防抖） |
| 技能 Timeline | total 300，HIT:150 END:300 |
| 初始姿态 | grant 后默认 Wrath；首次主动释放 → Calm，再 → Wrath，循环 |

## 3.4 代码骨架

`stance.gd`（单 Ability；无技能专用 Action / component）：
```gdscript
class_name HexBattleStance

const CONFIG_ID := "skill_stance"
const TIMELINE_ID := "skill_stance"
const WRATH_TAG := "stance:skill_stance:wrath"
const CALM_TAG := "stance:skill_stance:calm"
const WRATH_MULT := 1.5
const CALM_MULT := 0.75
const COOLDOWN_MS := 2000.0

static var STANCE_TIMELINE := TimelineData.new(TIMELINE_ID, 300.0, {
	TimelineTags.HIT: 150.0, TimelineTags.END: 300.0,
})

static func _has_wrath(ctx: ExecutionContext) -> bool:
	var actor := GameWorld.get_actor(ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else "")
	var aset := IAbilitySetOwner.get_ability_set(actor)
	return aset != null and aset.has_tag(WRATH_TAG)

static func _stance_mult(ctx: AbilityLifecycleContext) -> float:
	if ctx.ability_set == null:
		return 1.0
	if ctx.ability_set.has_tag(WRATH_TAG):
		return WRATH_MULT
	if ctx.ability_set.has_tag(CALM_TAG):
		return CALM_MULT
	return 1.0

static func _incoming() -> PreEventConfig:
	return PreEventConfig.new(
		HexBattlePreEvents.PRE_DAMAGE_EVENT,
		func(_m: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
			var mult := _stance_mult(ctx)
			if is_equal_approx(mult, 1.0):
				return EventPhase.pass_intent()
			return EventPhase.modify_intent(ctx.ability.id, [
				Modification.multiply("damage", mult, ctx.ability.config_id, "姿态受伤")
			]),
		func(e: Dictionary, ctx: AbilityLifecycleContext) -> bool:
			return e.get("target_actor_id", "") == ctx.owner_actor_id,
		"Stance incoming damage")

static func _outgoing() -> PreEventConfig:
	return PreEventConfig.new(
		HexBattlePreEvents.PRE_DAMAGE_EVENT,
		func(_m: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
			var mult := _stance_mult(ctx)
			if is_equal_approx(mult, 1.0):
				return EventPhase.pass_intent()
			return EventPhase.modify_intent(ctx.ability.id, [
				Modification.multiply("damage", mult, ctx.ability.config_id, "姿态造伤")
			]),
		func(e: Dictionary, ctx: AbilityLifecycleContext) -> bool:
			return e.get("source_actor_id", "") == ctx.owner_actor_id,
		"Stance outgoing damage")

static var ABILITY := (AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("姿态切换")
	.description("在 Wrath 与 Calm 两种姿态间切换")
	.ability_tags(["skill", "active", "self", "stance"])
	.component_config(NoInstanceConfig.builder()
		.on_apply_actions([
			LooseTagAction.Remove.new(HexBattleTargetSelectors.ability_owner(), CALM_TAG),
			LooseTagAction.Remove.new(HexBattleTargetSelectors.ability_owner(), WRATH_TAG),
			LooseTagAction.Apply.new(HexBattleTargetSelectors.ability_owner(), WRATH_TAG),
		])
		.on_remove_actions([
			LooseTagAction.Remove.new(HexBattleTargetSelectors.ability_owner(), WRATH_TAG),
			LooseTagAction.Remove.new(HexBattleTargetSelectors.ability_owner(), CALM_TAG),
		])
		.build())
	.component_config(_incoming())
	.component_config(_outgoing())
	.active_use(ActiveUseConfig.builder()
		.timeline_id(TIMELINE_ID)
		.on_timeline_start([StageCueAction.new(
			HexBattleTargetSelectors.ability_owner(),
			Resolvers.str_val("melee_slash"))])
		.on_tag(TimelineTags.HIT, [FlowAction.if_(
			_has_wrath,
			[
				LooseTagAction.Remove.new(HexBattleTargetSelectors.ability_owner(), WRATH_TAG),
				LooseTagAction.Apply.new(HexBattleTargetSelectors.ability_owner(), CALM_TAG),
			],
			[
				LooseTagAction.Remove.new(HexBattleTargetSelectors.ability_owner(), CALM_TAG),
				LooseTagAction.Apply.new(HexBattleTargetSelectors.ability_owner(), WRATH_TAG),
			]
		)])
		.condition(Condition.NoTagCondition.new(HexBattleActionLockStatus.TAG_CANT_ACT))
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(COOLDOWN_MS))
		.build())
	.build())
```

不新增 `SwitchStanceAction`：切换姿态只是 “if has tag A then remove A + add B else remove B + add A”，用 `LooseTagAction` 和 §0 的 `FlowAction.if_` 表达即可。

## 3.5 scenario

caster[0,0] + 1 enemy。`get_actions` 多步：
1. 初始 grant 后断言 caster 有 `WRATH_TAG`、无 `CALM_TAG`。
2. caster Strike enemy，断 outgoing ×1.5。
3. enemy Strike caster，断 incoming ×1.5。
4. caster 施 stance，断 `WRATH_TAG` 移除、`CALM_TAG` 存在。
5. caster Strike enemy，断 outgoing ×0.75。
6. enemy Strike caster，断 incoming ×0.75。
7. caster 再施 stance，断回到 Wrath。

断言用 `assert_float_in` 兜 crit。额外补一个 lifecycle case：revoke / expire `skill_stance` 后，`WRATH_TAG` 和 `CALM_TAG` 都被清理。

## 3.6 新机制清单

1. **依赖 §0.6 NoInstance lifecycle actions**：`skill_stance` 用 `NoInstanceConfig.on_apply_actions/on_remove_actions` 表达默认 Wrath 与 remove 清理，不新增技能专用 component。
2. **AbilityConfig instance policy guard**：受控 V1 可先靠测试/装备路径保证 `skill_stance` 不多实例；进入非受控 loadout / AI-generated grant 前必须补 `unique_by_config` / `grant_unique_ability` / reject-or-replace 策略，避免多个同 config 主动技能共享 loose tag 造成状态污染。若实现成本很低，可在 Stance 同批先加最小 bool。

复用项：伤害修正仍走 `PreEventConfig` + `Modification.multiply` 通路；切换复用 `LooseTagAction.Apply` / `Remove` + `FlowAction.if_`；不新增事件/schema，不新增业务 `SwitchStanceAction`。

## 3.7 表演层

| 接入点 | 处理 |
|---|---|
| BUFF_REGISTRY | N/A：Wrath/Calm 是 stance tag，不是 buff ability |
| StageCue | 复用 `melee_slash`（自我姿态切换的挥手提示） |
| default_registry / projectile | 不动 / N/A |

若后续希望 UI 展示当前 stance，应新增 stance/tag visualizer，而不是走 BuffVisualizer。

> **评审意见**：已批准。Stance 从“三个 Ability（技能 + Wrath buff + Calm buff）”改为“单 Ability + loose stance tags”。主动释放用 `FlowAction.if_ + LooseTagAction` 切换 tag，不新增业务 Action；默认 Wrath 与 remove 清理由 §0.6 的 `NoInstanceConfig` lifecycle actions 表达；outgoing/incoming damage multiplier 由 `skill_stance` 自己挂的 `PreEventConfig` 读取当前 stance tag 决定。V1 受控测试路径不允许同 actor 多个 `skill_stance`；开放 loadout / AI-generated grant 前必须补 config-level `unique_by_config` 或等价 grant guard。
