# 剩余 5 技能可执行级实施方案（align 门文档）

> 配套 [`skill-implementation-progress.md`](skill-implementation-progress.md) 与 [`.lomo-team/reference/inkmon-skill-design.md`](../../.lomo-team/reference/inkmon-skill-design.md)。
> 本文 = taxonomy 16 技能剩余 5 个的**可执行级 align 方案**，逐个评审通过后才落码。
> 创建：2026-05-18 · Opus 4.7

---

## 评审追踪表

| 顺序 | # | 技能 | 难度 | 真新机制 | 评审状态 |
|---|---|---|---|---|---|
| 1 | 9 | Chain Lightning | ★☆☆☆☆ | 无 | ⬜ 待评审 |
| 2 | 12 | Shadow Step | ★★☆☆☆ | 无 | ⬜ 待评审 |
| 3 | 14 | Stance | ★★★☆☆ | 无 | ⬜ 待评审 |
| 4 | 15 | Demon Form | ★★★☆☆ | 无 | ⬜ 待评审 |
| 5 | 16 | Summon Totem | ★★★★★ | 框架可行性(spike 查清) | ⬜ 待评审(spike 门) |

状态：⬜ 待评审 · 🟡 需改(见该节末「评审意见」) · ✅ 已批准可落码

---

## 收敛的全局决策（评审时若推翻在此改）

| 项 | 结论 | 依据 |
|---|---|---|
| 实施顺序 | Chain → Shadow → Stance → Demon → Totem | 难度递增；progress「下一个建议」 |
| schema 倾向 | 全复用，不新增 event/枚举/API | Chain=MAGICAL、Shadow=ActorDisplacedEvent；非 fork |
| Demon Form 实现 | 方案 A：每 tick `add_modifier` 一个独立 +2 ADD_BASE | `raw.add_modifier` 是现成公共 API；无 stacks/动态/组件 |
| Summon Totem | spike 先行验证框架原语 → 绿再 TDD 建技能 | 战斗中途 add/remove actor + recording 完整性未知 |
| crit 建模 | 「+X%」用 damage resolver ×系数，**不**强设 is_critical | DamageAction 无强制 crit 入口；resolver 系数是既有 pattern |

---

# 1 · Chain Lightning #9

**设计卡**：首目标魔法伤害 → 跳最近未命中敌人，每跳 -20%，最多 3 跳。

## 1.1 调研结论

| 既有原语 | 现状 | 够用 |
|---|---|---|
| `HexBattleDamageUtils.apply_damage`+`broadcast_post_damage` | poison_tick 验证 pre→apply→post | ✅ |
| `HexBattlePreEvents.PreDamageEvent` | poison_tick 走 expose/shield 拦截 | ✅ |
| `BattleEvents.DamageType.MAGICAL` | fireball 用例 | ✅ 复用 |
| `battle.get_alive_actors()`+`HexCoord.distance_to` | HexWorldGI:112 / HexCoord:134 | ✅ 跳目标 |
| Cooldown/NoTagCondition/StageCueAction | fireball/poison 同款 | ✅ |

0 缺口。链锁迭代在 Action 内 local 循环。

## 1.2 文件清单

| 文件 | 新建/改 |
|---|---|
| `logic/actions/chain_lightning_action.gd` | 新建 |
| `logic/skills/chain_lightning.gd` | 新建 |
| `logic/skills/all_skills.gd` | 改(+1 行注册) |
| `tests/battle/skill_scenarios/chain_lightning_scenario.gd` | 新建 |
| `docs/skills/skill-implementation-progress.md` | 改(回写) |

## 1.3 数值常量表

| 常量 | 值 | 理由 |
|---|---|---|
| CONFIG_ID | `skill_chain_lightning` | 对齐 `skill_*` |
| TIMELINE_ID | `skill_chain_lightning` | 同 fireball |
| BASE_DAMAGE | `60.0` MAGICAL | 多目标，单跳 < fireball 80 |
| MAX_HOPS | `3` | 设计卡 |
| FALLOFF | `0.2`（×0.8/跳） | 设计卡 -20% |
| COOLDOWN_MS | `5000.0` | 多目标 > fireball 4000 |
| RANGE meta | `5` | 同 fireball |
| Timeline | total 600，CAST:200 HIT:400 END:600 | 瞬发，留 cast tell |
| 伤害序列 | 60 / 48 / 38.4 | 60×0.8ⁿ |

## 1.4 代码骨架

`chain_lightning_action.gd`（`visited`/`damage` 全 local，共享无状态）：
```gdscript
class_name HexBattleChainLightningAction
extends Action.BaseAction

var _base_damage: FloatResolver
var _max_hops: int
var _falloff: float

func _init(target_selector: TargetSelector, base_damage: FloatResolver,
		max_hops: int, falloff: float) -> void:
	super._init(target_selector)
	type = "chain_lightning"
	_base_damage = base_damage
	_max_hops = max_hops
	_falloff = falloff

func execute(ctx: ExecutionContext) -> ActionResult:
	var battle: HexWorldGameplayInstance = ctx.game_state_provider
	var caster_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
	var targets := get_targets(ctx)
	if battle == null or caster_id == "" or targets.is_empty():
		return ActionResult.create_success_result([], { "skipped": true })
	var caster := battle.get_character_actor(caster_id)
	if caster == null:
		return ActionResult.create_success_result([], { "skipped": true })
	var caster_team := caster.get_team_id()

	var visited: Array[String] = []
	var current_id: String = targets[0]
	var damage: float = _base_damage.resolve(ctx)
	var all_events: Array[Dictionary] = []

	for _hop in range(_max_hops):
		if current_id == "":
			break
		var cur := battle.get_actor(current_id)
		if cur == null or cur.is_dead():
			break
		all_events.append_array(_zap(caster_id, current_id, damage, ctx, battle))
		visited.append(current_id)
		damage *= (1.0 - _falloff)
		current_id = _nearest_unvisited_enemy(caster_team, cur.hex_position, visited, battle)

	return ActionResult.create_success_result(all_events, { "hops": visited.size() })

func _zap(source_id: String, target_id: String, amount: float,
		ctx: ExecutionContext, battle: HexWorldGameplayInstance) -> Array[Dictionary]:
	var alive := battle.get_alive_actor_ids()
	var pre := HexBattlePreEvents.PreDamageEvent.create(
		source_id, target_id, amount,
		BattleEvents._damage_type_to_string(BattleEvents.DamageType.MAGICAL))
	var mutable := GameWorld.event_processor.process_pre_event(pre.to_dict(), battle)
	if mutable.cancelled:
		return []
	var dmg: float = mutable.get_current_value("damage")
	var evt := BattleEvents.DamageEvent.create(
		target_id, dmg, BattleEvents.DamageType.MAGICAL, source_id, false, false)
	var res := HexBattleDamageUtils.apply_damage(evt, alive, ctx, battle)
	HexBattleDamageUtils.broadcast_post_damage(res.damage_event_dict, alive, battle)
	return res.all_events

func _nearest_unvisited_enemy(team: int, from_pos: HexCoord,
		visited: Array[String], battle: HexWorldGameplayInstance) -> String:
	var best := ""
	var best_d := 1 << 30
	for a in battle.get_alive_actors():
		if a.get_team_id() == team or a.get_id() in visited:
			continue
		var d := from_pos.distance_to(a.hex_position)
		if d < best_d:
			best_d = d
			best = a.get_id()
	return best
```

`chain_lightning.gd`（装配照 fireball，去投射物）：
```gdscript
class_name HexBattleChainLightning
const CONFIG_ID := "skill_chain_lightning"
const TIMELINE_ID := "skill_chain_lightning"
const BASE_DAMAGE := 60.0
const MAX_HOPS := 3
const FALLOFF := 0.2
const COOLDOWN_MS := 5000.0

static var CHAIN_LIGHTNING_TIMELINE := TimelineData.new(TIMELINE_ID, 600.0, {
	TimelineTags.CAST: 200.0, TimelineTags.HIT: 400.0, TimelineTags.END: 600.0,
})

static var ABILITY := (AbilityConfig.builder()
	.config_id(CONFIG_ID).display_name("连锁闪电")
	.description("对目标造成魔法伤害，弹跳至最近的其他敌人，每跳衰减 20%，最多 3 跳")
	.ability_tags(["skill", "active", "ranged", "magic", "enemy"])
	.meta(HexBattleSkillMetaKeys.RANGE, 5)
	.active_use(ActiveUseConfig.builder()
		.timeline_id(TIMELINE_ID)
		.on_timeline_start([StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val("magic_fireball"))])
		.on_tag(TimelineTags.HIT, [HexBattleChainLightningAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.float_val(BASE_DAMAGE), MAX_HOPS, FALLOFF)])
		.condition(Condition.NoTagCondition.new(HexBattleActionLockStatus.TAG_CANT_ACT))
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(COOLDOWN_MS))
		.build())
	.build())
```
`all_skills.gd`：`arr.append(_Entry.new(HexBattleChainLightning.ABILITY, [HexBattleChainLightning.CHAIN_LIGHTNING_TIMELINE]))`

## 1.5 scenario

map 7×3，caster[0,0] + enemy_0[1,0] enemy_1[2,0] enemy_2[3,0] enemy_3[6,2]（链外）。default get_actions。max_ticks 60。

| 断言 | 期望 |
|---|---|
| enemy_0 | `assert_float_in(dmg,[60,90])` |
| enemy_1 | `[48,72]` |
| enemy_2 | `[38.4,57.6]` |
| enemy_3 | `filter_damage_events` size 0 |
| 主伤害事件数 | 3 |

crit 双值兜底（damage_action `randf()<0.1`）。收工 **重跑 5 次**。

## 1.6 新机制清单

**无。** ChainLightningAction 设计卡 §9 已有骨架；复用 MAGICAL/PreDamageEvent/DamageUtils；visited local；0 新事件/schema/API。

## 1.7 表演层

| 接入点 | 处理 |
|---|---|
| BUFF_REGISTRY | N/A |
| StageCue | 复用 `magic_fireball`（§7.3，无专属闪电资产不编新名） |
| default_registry | 不动 |
| projectile | N/A（瞬发） |

链锁折线特效非 V1（scenario 不读表演层）。

> **评审意见**：（待填）

---

# 2 · Shadow Step #12

**设计卡**：瞬移到目标"身后"，+50% 一击。

## 2.1 调研结论 + 核心问题

| 既有原语 | 现状 | 够用 |
|---|---|---|
| `battle.grid.move_occupant(from,to)` + `actor.hex_position=` | push_action:138 落地 | ✅ |
| `BattleEvents.ActorDisplacedEvent.create(...)` | push_action:141 落地 | ✅ 复用(kind=teleport) |
| `HexCoord.get_neighbors()/distance_to` | HexCoord:163/134 | ✅ |
| `HexBattleDamageAction` | strike/knockback | ✅(resolver ×1.5) |

**核心问题**：CharacterActor **无 facing 属性**；且本技能 gap closer（RANGE>1），caster 与 target 多数非相邻，`direction_to_neighbor` 仅相邻有效。
→ **"身后"鲁棒定义**：target 的 6 个邻格中，**离 caster 最远的空格**（= 远离 caster 的那一侧，无需 facing、任意距离成立、确定性）。

## 2.2 文件清单

| 文件 | 新建/改 |
|---|---|
| `logic/actions/shadow_step_action.gd` | 新建 |
| `logic/skills/shadow_step.gd` | 新建 |
| `logic/skills/all_skills.gd` | 改(+1) |
| `tests/battle/skill_scenarios/shadow_step_scenario.gd` | 新建 |
| `docs/skills/skill-implementation-progress.md` | 改 |

## 2.3 数值常量表

| 常量 | 值 | 理由 |
|---|---|---|
| CONFIG_ID | `skill_shadow_step` | |
| TIMELINE_ID | `skill_shadow_step` | |
| DAMAGE_MULT | `1.5`（caster.atk×1.5） | 设计卡 +50%；resolver 系数（非强制 crit） |
| COOLDOWN_MS | `6000.0` | gap closer + 高单发，长 CD |
| RANGE meta | `4` | gap closer 突进距离 |
| Timeline | total 500，TELEPORT:150 HIT:300 END:500 | 先瞬移后斩 |

## 2.4 代码骨架

`shadow_step_action.gd`（只管瞬移；伤害交同 timeline 后续 DamageAction）：
```gdscript
class_name HexBattleShadowStepAction
extends Action.BaseAction

func _init(target_selector: TargetSelector) -> void:
	super._init(target_selector)
	type = "shadow_step"

func execute(ctx: ExecutionContext) -> ActionResult:
	var battle: HexWorldGameplayInstance = ctx.game_state_provider
	var caster_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
	var targets := get_targets(ctx)
	if battle == null or caster_id == "" or targets.is_empty():
		return ActionResult.create_success_result([], { "skipped": true })
	var caster := battle.get_character_actor(caster_id)
	var target := battle.get_actor(targets[0])
	if caster == null or target == null or target.is_dead():
		return ActionResult.create_success_result([], { "skipped": true })

	var from_pos := caster.hex_position
	var land := _behind_slot(target.hex_position, from_pos, battle)
	if land == null:
		# 无空落点：技能不位移，HIT 仍在原地结算（仅当原地在射程内有意义）
		return ActionResult.create_success_result([], { "teleported": false })

	if not battle.grid.move_occupant(from_pos, land):
		return ActionResult.create_success_result([], { "teleported": false })
	caster.hex_position = land
	var dist := from_pos.distance_to(land)
	var evt := BattleEvents.ActorDisplacedEvent.create(
		caster_id, from_pos.to_dict(), land.to_dict(),
		"teleport", caster_id, dist, 0.0, 0.0)        # 自位移：无 stagger
	var pushed := ctx.event_collector.push(evt.to_dict())
	return ActionResult.create_success_result([pushed], { "teleported": true })

# target 6 邻格里离 caster 最远的空格；无则 null
func _behind_slot(target_pos: HexCoord, caster_pos: HexCoord,
		battle: HexWorldGameplayInstance) -> HexCoord:
	var best: HexCoord = null
	var best_d := -1
	for n in target_pos.get_neighbors():
		if not battle.grid.has_tile(n) or battle.grid.is_occupied(n):
			continue
		var d := caster_pos.distance_to(n)
		if d > best_d:
			best_d = d
			best = n
	return best
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

static var SHADOW_STEP_TIMELINE := TimelineData.new(TIMELINE_ID, 500.0, {
	TimelineTags.TELEPORT: 150.0, TimelineTags.HIT: 300.0, TimelineTags.END: 500.0,
})

static var ABILITY := (AbilityConfig.builder()
	.config_id(CONFIG_ID).display_name("影袭")
	.description("瞬移到目标背侧并造成 150% 攻击力的一击")
	.ability_tags(["skill", "active", "melee", "enemy"])
	.meta(HexBattleSkillMetaKeys.RANGE, 4)
	.meta(HexBattleSkillMetaKeys.ALLOWED_TARGET_KINDS, ["Character"])
	.active_use(ActiveUseConfig.builder()
		.timeline_id(TIMELINE_ID)
		.on_tag(TimelineTags.TELEPORT, [HexBattleShadowStepAction.new(
			HexBattleTargetSelectors.current_target())])
		.on_tag(TimelineTags.HIT, [HexBattleDamageAction.new(
			HexBattleTargetSelectors.current_target(),
			_ATK_X15, BattleEvents.DamageType.PHYSICAL)])
		.condition(Condition.NoTagCondition.new(HexBattleActionLockStatus.TAG_CANT_ACT))
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(COOLDOWN_MS))
		.build())
	.build())
```
> ⚠️ 需确认：`TimelineTags.TELEPORT` 是否存在常量；不存在则复用 `TimelineTags.CAST` 或加常量（加常量=改 stdlib 常量表，列入新机制清单待评审）。

## 2.5 scenario

map 7×3，caster[0,0] enemy_0[4,0]（相距 4，背侧 [5,0] 空）。default get_actions。max_ticks 60。

| 断言 | 期望 |
|---|---|
| `ActorDisplacedEvent` 出现且 `displacement_kind=="teleport"` source=caster | size≥1 |
| caster 终态相邻 enemy_0 | `final` 位置 distance==1（用 displaced 事件 final pos 推算） |
| enemy_0 受击 = atk×1.5 | `assert_float_in([atk*1.5, atk*1.5*1.5])` |

（scenario 无位置断言 API → 用 ActorDisplacedEvent 的 `to`/`from` 字段断言落点。）

## 2.6 新机制清单

**无（前提：复用 ActorDisplacedEvent + TimelineTags.TELEPORT 已存在）。** 若 TELEPORT 常量需新增 → 列 1 条「stdlib TimelineTags 加值」待评审定夺。

## 2.7 表演层

| 接入点 | 处理 |
|---|---|
| BUFF_REGISTRY | N/A |
| StageCue | 可选复用 `melee_combo`（瞬斩感）；或不接（瞬移本身无 cue 也不红） |
| default_registry / projectile | 不动 / N/A |

前端瞬移动画走既有 ActorDisplaced 订阅（push 已铺）；本技能不欠表演层。

> **评审意见**：（待填）

---

# 3 · Stance: Wrath/Calm #14

**设计卡**：两姿态主动切换。Wrath 造伤+50%/受伤+50%；Calm 造伤-25%/受伤-25%。

## 3.1 调研结论 + 范式

无 outgoing_damage_amp 属性。两侧都走 **Expose 同款 PreEvent 通路**（对称、collision 也吃、与既有第一个 modify_intent 用例一致）：
- 受伤 ±%：`PreDamageEvent` filter `target_actor_id==owner` → `Modification.multiply("damage",k)`
- 造伤 ±%：`PreDamageEvent` filter `source_actor_id==owner` → `Modification.multiply("damage",k)`

切换：`ability_set.revoke_abilities_by_config_id(另一姿态)` + `grant_ability(目标姿态)`（幂等，ability_set.gd:95 现成）。

## 3.2 文件清单

| 文件 | 新建/改 |
|---|---|
| `logic/buffs/wrath_stance_buff.gd` | 新建 |
| `logic/buffs/calm_stance_buff.gd` | 新建 |
| `logic/actions/switch_stance_action.gd` | 新建 |
| `logic/skills/stance.gd` | 新建 |
| `logic/skills/all_skills.gd` | 改(+3：技能+2 buff) |
| `frontend/visualizers/buff_visualizer.gd` | 改(BUFF_REGISTRY +2 行) |
| `tests/battle/skill_scenarios/stance_scenario.gd` | 新建 |
| `docs/skills/skill-implementation-progress.md` | 改 |

## 3.3 数值常量表

| 常量 | 值 |
|---|---|
| WRATH CONFIG_ID | `buff_stance_wrath` |
| CALM CONFIG_ID | `buff_stance_calm` |
| 技能 CONFIG_ID | `skill_stance` |
| Wrath 造伤/受伤 mult | `1.5` / `1.5` |
| Calm 造伤/受伤 mult | `0.75` / `0.75` |
| 姿态 duration | 永久（无 TimeDurationConfig，靠切换 revoke） |
| 技能 COOLDOWN_MS | `2000.0`（防抖） |
| 技能 Timeline | total 300，HIT:150 END:300 |
| 初始姿态 | 中立（无 stance ability），首次施放 → Wrath，再 → Calm，循环 |

## 3.4 代码骨架

`wrath_stance_buff.gd`（calm 同构，mult 改 0.75 / tags negative）：
```gdscript
class_name HexBattleWrathStanceBuff
const CONFIG_ID := "buff_stance_wrath"
const DMG_MULT := 1.5

static func _incoming() -> PreEventConfig:
	return PreEventConfig.new(HexBattlePreEvents.PRE_DAMAGE_EVENT,
		func(_m: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
			return EventPhase.modify_intent(ctx.ability.id, [
				Modification.multiply("damage", DMG_MULT, ctx.ability.config_id, "愤怒受伤")]),
		func(e: Dictionary, ctx: AbilityLifecycleContext) -> bool:
			return e.get("target_actor_id","") == ctx.owner_actor_id,
		"Wrath +50% taken")

static func _outgoing() -> PreEventConfig:
	return PreEventConfig.new(HexBattlePreEvents.PRE_DAMAGE_EVENT,
		func(_m: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
			return EventPhase.modify_intent(ctx.ability.id, [
				Modification.multiply("damage", DMG_MULT, ctx.ability.config_id, "愤怒造伤")]),
		func(e: Dictionary, ctx: AbilityLifecycleContext) -> bool:
			return e.get("source_actor_id","") == ctx.owner_actor_id,
		"Wrath +50% dealt")

static var WRATH_BUFF := (AbilityConfig.builder()
	.config_id(CONFIG_ID).display_name("愤怒姿态")
	.description("造成与受到的伤害均 +50%")
	.ability_tags(["buff", "negative"])     # 双刃，归 negative
	.component_config(_incoming())
	.component_config(_outgoing())
	.build())
```

`switch_stance_action.gd`：
```gdscript
class_name HexBattleSwitchStanceAction
extends Action.BaseAction

func _init() -> void:
	super._init(HexBattleTargetSelectors.ability_owner())
	type = "switch_stance"

func execute(ctx: ExecutionContext) -> ActionResult:
	var battle: HexWorldGameplayInstance = ctx.game_state_provider
	var oid := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
	var actor := battle.get_character_actor(oid) if battle != null else null
	if actor == null:
		return ActionResult.create_success_result([], { "skipped": true })
	var aset := actor.get_ability_set()
	var has_wrath := aset.has_ability(HexBattleWrathStanceBuff.CONFIG_ID)
	var has_calm := aset.has_ability(HexBattleCalmStanceBuff.CONFIG_ID)
	# 中立/Calm → Wrath；Wrath → Calm
	var to_wrath := not has_wrath
	aset.revoke_abilities_by_config_id(
		HexBattleCalmStanceBuff.CONFIG_ID if to_wrath else HexBattleWrathStanceBuff.CONFIG_ID)
	if to_wrath and not has_wrath:
		aset.grant_ability(Ability.new(HexBattleWrathStanceBuff.WRATH_BUFF, oid, oid), battle)
	elif not to_wrath and not has_calm:
		aset.grant_ability(Ability.new(HexBattleCalmStanceBuff.CALM_BUFF, oid, oid), battle)
	return ActionResult.create_success_result([], { "to": "wrath" if to_wrath else "calm" })
```

`stance.gd`：active skill，`ability_tags(["skill","active","self"])`，无 target（self），HIT 跑 `HexBattleSwitchStanceAction.new()`，带 NoTagCondition + Cooldown。

## 3.5 scenario

caster[0,0] + 1 enemy。`get_actions` 多步：①caster 施 stance（→Wrath）②caster Strike enemy（断 ×1.5）③enemy Strike caster（断 ×1.5）④caster 再施 stance（→Calm）⑤caster Strike enemy（断 ×0.75）。断言用 `assert_float_in` 兜 crit。`assert_actor_ability_present/absent` 验证姿态互斥。

## 3.6 新机制清单

**无。** 2 buff = inspire/expose 同构；SwitchStanceAction 用 ability_set 现成 API；PreEvent 复用 Expose 通路；0 新事件/schema/API。

## 3.7 表演层

| 接入点 | 处理 |
|---|---|
| BUFF_REGISTRY | **必接 +2 行**：`buff_stance_wrath` short "W" 红 `Color(0.85,0.25,0.2)`；`buff_stance_calm` short "C" 青 `Color(0.3,0.7,0.8)`，PrimarySource.NONE |
| StageCue | 复用 `melee_slash`（自我姿态切换的挥手提示） |
| default_registry / projectile | 不动 / N/A |

收工自检 §10 多 buff 同字段：grep `buff_visualizer.gd` + `hex_battle_skill_index.gd`/`skill_preview.gd:318` 确认 buff tag 过滤不丢。

> **评审意见**：（待填）

---

# 4 · Demon Form #15

**设计卡**：passive，每 3s 永久 +2 atk，无上限。

## 4.1 调研结论（关键澄清）

设计卡 §9「方案 B：Resolver 读 stacks」是**过时伪码**。本质 =「每 3s 给 atk 加一个 +2 的 ADD_BASE modifier」。`raw_attribute_set.add_modifier()`（:216）是现成公共 API。**无需 stacks / 无需动态计算 / 无需新组件 / 无需新 API**。periodic 驱动照 poison_buff（GRANTED_SELF + `TimelineData.periodic`）。

## 4.2 文件清单

| 文件 | 新建/改 |
|---|---|
| `logic/buffs/demon_form_buff.gd` | 新建 |
| `logic/actions/demon_form_tick_action.gd` | 新建 |
| `logic/skills/all_skills.gd` | 改(+1 buff，带 tick timeline) |
| `tests/battle/skill_scenarios/demon_form_scenario.gd` | 新建 |
| `docs/skills/skill-implementation-progress.md` | 改 |

## 4.3 数值常量表

| 常量 | 值 |
|---|---|
| CONFIG_ID | `buff_demon_form` |
| TICK_TIMELINE_ID | `buff_demon_form_tick` |
| TICK_INTERVAL_MS | `3000.0` |
| ATK_PER_TICK | `2.0`（ADD_BASE atk） |
| 上限 | 无 |
| 挂载方式 | passive（scenario 用 `get_passives()`；demo 可绑某职业，评审定） |

## 4.4 代码骨架

`demon_form_tick_action.gd`（用 ability.stacks 仅作确定性计数器，保证 modifier id 唯一可重放）：
```gdscript
class_name HexBattleDemonFormTickAction
extends Action.BaseAction

const ATK_PER_TICK := 2.0

func _init() -> void:
	super._init(HexBattleTargetSelectors.ability_owner())
	type = "demon_form_tick"

func execute(ctx: ExecutionContext) -> ActionResult:
	if ctx.ability_ref == null:
		return ActionResult.create_success_result([], {})
	var ability := ctx.ability_ref.resolve()
	if ability == null or ability.is_expired():
		return ActionResult.create_success_result([], {})
	var battle: HexWorldGameplayInstance = ctx.game_state_provider
	var actor := battle.get_character_actor(ability.owner_actor_id) if battle != null else null
	if actor == null:
		return ActionResult.create_success_result([], {})

	var n := ability.get_stacks() + 1
	ability.set_stacks(n)                       # 仅计数器，确定性 id 用
	var raw := actor.attribute_set.get_raw()
	raw.add_modifier(AttributeModifier.create_add_base(
		"%s_%d" % [ability.config_id, n], "atk", ATK_PER_TICK, ability.id))
	ctx.event_collector.push(GameEvent.AbilityStacksChanged.create(
		ability.owner_actor_id, ability.id, ability.config_id, n - 1, n).to_dict())
	return ActionResult.create_success_result([], { "demon_atk_bonus": n * ATK_PER_TICK })
```
> ⚠️ 需确认：`Ability.set_stacks(n)` 是否存在；若只有 `add_stacks`/`remove_stacks`（见 surge/poison）则改 `ability.add_stacks(1)` 后 `n := ability.get_stacks()`。评审/落码时按实际 API 取。

`demon_form_buff.gd`（照 poison_buff）：
```gdscript
class_name HexBattleDemonFormBuff
const CONFIG_ID := "buff_demon_form"
const TICK_TIMELINE_ID := "buff_demon_form_tick"
const TICK_INTERVAL_MS := 3000.0

static var DEMON_FORM_TICK_TIMELINE := TimelineData.periodic(TICK_TIMELINE_ID, TICK_INTERVAL_MS)

static var DEMON_FORM_BUFF := (AbilityConfig.builder()
	.config_id(CONFIG_ID).display_name("恶魔形态")
	.description("每 3 秒永久 +2 攻击力，无上限")
	.ability_tags(["buff", "positive"])
	.stacks(0, 999999, Ability.OVERFLOW_CAP)
	.component_config(ActivateInstanceConfig.builder()
		.trigger(TriggerConfig.GRANTED_SELF)
		.timeline_id(TICK_TIMELINE_ID)
		.on_timeline_end([HexBattleDemonFormTickAction.new()])
		.build())
	.build())
```
`all_skills.gd`：`arr.append(_Entry.new(HexBattleDemonFormBuff.DEMON_FORM_BUFF, [HexBattleDemonFormBuff.DEMON_FORM_TICK_TIMELINE]))`

## 4.5 scenario

caster 挂 DemonFormBuff（`get_passives`），无敌人或弱敌防早死，跑足 ~10s（max_ticks 调够）。断言：caster `atk` 终值 = 初始 atk + floor(经过 ms / 3000) × 2。可用 `final_actor` 属性快照或对 enemy 的伤害递增间接验证（scenario 无属性断言则打木桩看伤害台阶）。
> ⚠️ scenario 断言 atk 需确认：ScenarioAssertContext 有无属性读取。无 → 用「打不死的木桩，看连续 Strike 伤害随时间升 2/3s」间接断。评审定断言策略。

## 4.6 新机制清单

**无。** `add_modifier` 现成公共 API；periodic 照 poison_buff；DemonFormTickAction 无状态（计数走 ability.stacks）；0 新事件/schema/组件/API。唯一开放点：长跑 N 个 modifier 的序列化体积——V1 接受（几十个），如需 compact 是后续优化非 V1。

## 4.7 表演层

| 接入点 | 处理 |
|---|---|
| BUFF_REGISTRY | **必接 +1**：`buff_demon_form` short "D" 暗红 `Color(0.6,0.1,0.1)`，PrimarySource.STACKS（显示叠层数=已 tick 次数） |
| StageCue / default_registry / projectile | 不接 / 不动 / N/A |

> **评审意见**：（待填）

---

# 5 · Summon Totem #16（spike 门，非直接 impl）

**设计卡**：召唤图腾 actor，低 HP、不移动、每 3s 攻击最近敌人、TTL 15s 或被打死。

## 5.1 为什么是 spike 门

3 个框架级未知，未查清不能写 impl 方案：

1. **战斗中途 add_actor 能否被 ATB/AI 驱动**：procedure 只 iter `get_alive_characters()`（CharacterActor）+ `ai_strategy.decide()`。图腾若非 CharacterActor 不会自动行动。
2. **中途新 actor 的 recording 完整性**：`setup_recording` 在 actor 何时挂？战斗中途加入的 actor 录像是否完整、replay 是否 bit-identical。
3. **TTL → remove_actor 通路**：`TimeDurationConfig` 只让 ability expire，不 remove actor 本体。需要「ability expire → battle.remove_actor」的通路，目前无落地参考。

## 5.2 Spike 计划（throwaway，断言框架原语而非图腾行为）

**spike scene**：`tests/battle/smoke_summon_spike.tscn`（spike 完可删/转正）

| spike 断言 | 验证点 |
|---|---|
| 战斗第 N tick 用 `battle.add_actor(EnvironmentActor.new(...))` + `grid.place_occupant` | 中途 add 不崩、grid 占位生效 |
| 一个 CharacterActor 中途 add + `set_team_id` + `equip_abilities` + 进 alive_actors | 是否自动进 ATB/AI 循环并行动 |
| 该 actor 的 grant/damage 事件出现在 replay | recording 是否覆盖中途 actor |
| `battle.remove_actor(id)` 后 grid 释放、无悬挂引用、replay 收尾正常 | TTL 自毁可行性 |
| 同 seed 跑 2 次 replay bit-identical | 中途增删 actor 不破确定性 |

**spike 产出 = 一份结论**写入本节「Spike 结论」，据此二选一：
- **路线 A**：图腾 = 低 HP CharacterActor（新「图腾」职业配置 + 简化 ai_strategy）→ 复用整套 ATB/AI/技能链
- **路线 B**：图腾 = 新 SummonActor 子类，自带 periodic auto-attack timeline（绕开 ATB），procedure 加最小驱动钩子

spike 绿后再出**正式 impl align 方案**（补本节），走 TDD（`lomo-kits:tdd` / `lomo-kits:smoke-test`）。

## 5.3 预判新机制清单（spike 后确认/收敛）

- 图腾 Actor 载体（新职业配置 或 新 SummonActor 子类）
- TTL → remove_actor 通路（新 Action + 谁调 remove）
- `ActorSummonedEvent`（新 event type，若 demo/replay 需要区分召唤）
- SummonTotemAction、图腾 auto-attack ability（可复用 Strike）

## 5.4 表演层（spike 后定）

新 unit visualizer（图腾形态）可能需进 `default_registry`；`ActorSummonedEvent` 视觉。spike 不接表演层（纯框架探针）。

> **评审意见**：（待填）

---

## 落码前总检查（每个技能批准后逐条过）

- [ ] 该节「评审状态」= ✅
- [ ] submodule 内实现 → commit；外层 bump 指针（分阶段即提）
- [ ] `smoke_skill_scenarios` 全绿；PreEvent/damage 类 **重跑 5 次**稳定
- [ ] 表演层 §7.1 逐项勾完或显式声明跳过
- [ ] 回写 `skill-implementation-progress.md`（状态/落地名/文件/scenario/Pattern 速查/偏离记录/日期/下一个建议）
- [ ] `enforcing-lgf` Validation Checklist 过
