# 进阶技能开发规划（Phase 2+）

> 已完成归档。本文曾是 16 个示范技能之后的进阶技能讨论入口，当前只作为 Phase 2+ 设计来源和历史决策索引。
> 前置假设：[`remaining-skills-impl-plan.md`](remaining-skills-impl-plan.md) 覆盖的 Chain Lightning / Shadow Step / Stance / Demon Form / Summon Totem 已完成并回写 [`skill-implementation-progress.md`](skill-implementation-progress.md)。

> 历史修正：当时 Summon Totem 仍处于 spike closeout / 待正式实现状态，因此 Fire Tile / 地形伤害格必须排在 Summon Totem 正式实现之后。当前已完成状态以 [`skill-implementation-progress.md`](skill-implementation-progress.md) 为准。
> 来源：`.lomo-team/reference/inkmon-skill-design.md` 第九节 Phase 2+ 候选 + 当前 hex-atb-battle 已落地 pattern。
> 创建：2026-05-20 · Codex
> Gateway 方案：[`2026-05-22-hex-battle-gateway-contract.md`](../design-notes/2026-05-22-hex-battle-gateway-contract.md)。

## 目标

这批技能不是为了扩充最终技能池数量，而是补 16 技能之后仍缺的可复用机制范式：

- active-use gating / control status
- stun / silence control boundary
- passive break / disabled passive boundary
- board hazard / tile effect
- buff cleanup / dispel
- atomic position swap
- actual-damage-based follow-up
- hex-specific line / cone target shape

每个新技能必须能回答两个问题：

1. 它给未来 AI / 设计者留下了什么可模仿 pattern？
2. 它是否复用现有 LGF / hex battle 机制，而不是另起一套系统？

## 非目标

- 不做羁绊、商店、装备合成、升星等 meta 层系统。
- 不为了一个技能建立通用 StatusSystem / TileSystem / EquipmentSystem。
- 不把单技能私有逻辑提升成 public Primitive Action，除非至少两个以上技能能直接复用。
- 不改 core Timeline 语义；延迟、周期、链式响应继续优先走现有 Timeline / Action / Event 流。

## 候选总览

| 顺序 | 技能 / 机制 | 价值 | 新 pattern | 初始状态 |
|---|---|---|---|---|
| A | Stun / 眩晕 | P0 | hard control；阻止 Move / Strike / active skill 的下一次主动行动 | Gateway 已拍板；待实现 |
| B | Silence / 禁用技能 | P0 | soft control；区分 `cant_act` 与 `cant_use_skill` | Gateway 已拍板；待实现 |
| B2 | Break / 破坏 | P0 | passive control；禁用 passive skill，区分 triggered / persistent / periodic passive | 语义已拍板；待实现 |
| C0 | Summon Totem 正式实现 | P0 | actor spawn；actor-level lifetime；召唤物自动攻击 | spike closeout；必须先于 Fire Tile |
| C | Fire Tile / 地形伤害格 | P0 | passable board hazard；tile effect lifecycle | 等 Summon Totem 正式实现后再 spike |
| D | Cleanse / Dispel | P1 | Cleanse 友方/自身 negative buff；Dispel 敌方 positive buff 留未来 | Cleanse V1 已拍板；待实现 |
| E | Swap / 位置交换 | P1 | 双 actor 原子占位交换 + 双 displacement event | V1 已拍板；待实现 |
| F | Lifesteal / 吸血 | P1 | `actual_life_damage` 驱动 follow-up heal | 待评审 |
| G | Line / Cone AoE | P2 | hex shape TargetSelector | 待评审 |

状态：待评审 = 先讨论语义；待 spike = 先写探针确认底层可行性。

## 现有机制复用图

| 想做什么 | 优先复用 | 不先新增 |
|---|---|---|
| 眩晕 | ActiveGateway、`cant_act` gate tag、`TagComponentConfig`、`TimeDurationConfig`、`CancelActiveExecutionsAction` | 通用 interrupt policy / StatusSystem |
| 沉默 | ActiveGateway、`cant_use_skill` gate tag、`TagComponentConfig`、`TimeDurationConfig` | 全局 StatusSystem / Ability state machine |
| 破坏 | `cant_use_passive` gate tag、passive Ability disabled state、外部注册型 component break hook、`TimeDurationConfig` | 全局 StatusSystem / 每个 passive skill 私有 hook / 通用 component suspend-resume 协议 |
| 召唤图腾 | `HexBattleSpawnActorAction`、`CharacterActor`、`HexBattleCharacterAttributeSet`、hex actor-level lifetime、`HexBattleTotemAttack` nearest-enemy target selection、`HexBattleProcedure` actor source | LGF core SpawnActorAction / `HexBattleTotemLifetime` Ability / 完整 AI strategy 框架 |
| 地形伤害格 | `HexBattleSpawnActorAction`、`EnvironmentActor`、`CollisionProfile.blocks_path=false`、Summon Totem 打通后的 actor spawn / lifetime / replay 合同 | 独立 TileSystem，除非 spike 证明 grid occupant 模型不支持 passable overlay |
| 清除 debuff | `AbilitySet` ability 列表、buff `ability_tags(["buff","negative"])`、TimeDuration lifecycle | 直接改 buff component 内部字段 |
| 位置交换 | `HexWorldGameplayInstance.grid` 占位操作、`ActorDisplacedEvent`、`ActionLockStatus` | 用两次 PushAction 伪装 swap |
| 吸血 | `DamageEvent.actual_life_damage`、`HexBattleHealAction`、post-damage filter | 按 raw damage 直接加血 |
| 直线 / 扇形 AoE | `TargetSelector` 子类、`HexCoord` 邻接/方向、Fireball damage pattern | 新 AoE action / 新 damage pipeline |

## Hex 应用层 Ability 目录整理

本轮目录整理只针对 hex battle example 的应用层内容：`example/hex-atb-battle/logic`。不改 `core/abilities`，不借目录整理顺手引入 Gateway / Stun / Poison 的新 runtime 行为。

### Chosen

把 hex 应用层的 `skills/` 与 `buffs/` 统一收敛到 `abilities/` 下面，按 Ability 在游戏中的职责分组：

```text
logic/abilities/
  active/
    fireball.gd
    poison.gd
    strike.gd
    ...

  buffs/
    action_lock_status.gd
    poison_buff.gd
    expose_buff.gd
    ward_buff.gd
    ...

  passives/
    thorn.gd
    vitality.gd
    vigor.gd
    deathrattle_aoe.gd
    ...

  shared/
    all_skills.gd
    cooldown_system.gd
    skill_helpers.gd
```

- `active/`：由 AI / 玩家主动发起的 Ability，例如 attack、move、spell、control skill。
- `buffs/`：以 Ability 生命周期存在的状态效果，例如 Poison、Expose、Ward、ActionLock、未来 Stun / Silence。
- `passives/`：常驻或事件响应型 Ability，例如 Thorn、Vigor、Vitality、Deathrattle。
- `shared/`：hex ability 内容层的注册、helper、cooldown 等 glue code；不放 LGF core 机制。

### Poison 定位

当前设计下，Poison 是 canonical buff，不是参数化 buff recipe：

- `PoisonBuff` 的功能属性固定，例如 tick interval、每层伤害、expire / stack 规则。
- 施加方只表达“这次添加几层”，例如 `add_stacks = 3`。
- 不为不同 Poison 技能复制多个 Poison buff class。
- 如果需要 helper，`create_apply_config(add_stacks)` 只作为调用便利，不代表一个新的 recipe 层。

目录整理不为 `PoisonBuff` 增加新功能；最多移动文件并更新引用路径。

### 迁移规则

- 移动 `.gd` 时同步移动对应 `.gd.uid`。
- `class_name` 保持不变，避免扩大调用面变更。
- 更新所有 `preload` / `load` / 文档路径引用。
- 不加兼容 shim，除非有明确外部路径消费者。
- 验证优先跑 hex skill scenarios；如果 Godot class cache 没刷新，再执行一次 `godot --headless --path . --import`。

## Gateway 设计摘要

Gateway 是 hex battle example 层的“入口资格”规则，不是新的 core runtime system。完整方案见 [`2026-05-22-hex-battle-gateway-contract.md`](../design-notes/2026-05-22-hex-battle-gateway-contract.md)。

本批技能只实现 ActiveGateway；PassiveGateway / BuffGateway 先保留设计边界，等 Stun / Silence 跑通后再扩。

### ActiveGateway 合同

- hex battle 中，一个可主动释放的 Ability 必须有且仅有一个 `ActiveUseComponent`。
- `can_use_skill_on(actor, skill, target)` 可以读取唯一 `ActiveUseComponent` 的 gateway 配置，不需要 snapshot / profile 复制层。
- target eligibility 仍走 ability metadata + declarative query，不进 runtime `Condition`。
- dynamic actor-state gate 走 ActiveGateway runtime condition，例如 `cant_act`、`cant_use_skill`。
- `Move` 当前使用 `ActivateInstanceConfig`，AI 路径由 `CharacterActor.can_act()` 的 primary gate 阻止；未来玩家直控 move path 需要补自己的 action-lock gate。

### Tag 词表

状态语义分两层：

- semantic ability tag：`stun`、`silence`、`passive_break`、`control`、`negative`
- functional gate tag：`cant_act`、`cant_use_skill`、`cant_use_passive`、`cant_move`、`cant_basic_attack`

Stun buff 的语义放在 buff ability 的 `ability_tags`，功能门禁放在 component tag。V1 不额外挂 `stunned` component tag，除非出现必须 `actor.ability_set.has_tag("stunned")` 的真实消费者。Cleanse / UI / immunity 读 `stun` / `control`；Gateway 消费 `cant_act`。

## Phase A · Stun / 眩晕

### 价值

当前已有 `cant_act`，但它主要是 forced displacement 后的短时 action lock，还没有一个正式的“眩晕技能”作为 hard control 示例。Stun 应作为控制类技能的第一块基准：打断目标当前 active execution，并阻止 duration 内再次主动行动，包括 Move、Strike 和所有 active skill。

这能先把 hard control 语义立住，再和 Silence 的 soft control 对照，避免把 `cant_act` / `cant_use_skill` 混成一类状态。

### 初始方案

新增一个通用负面 buff recipe，例如 `stun_buff`：

- buff tags：`["buff", "negative", "control", "stun"]`
- component tags：`cant_act`
- on apply：`CancelActiveExecutionsAction`，只取消目标当前 `ability_tags` 含 `active` 的 execution instances
- demo duration：2000ms；机制上 duration 仍由施加方传入，例如 1000ms、2000ms、3000ms
- skill：`skill_stun` 命中目标后 apply `HexBattleStunBuff.create_config(duration_ms)`

V1 语义：

- 阻止 Move / Strike / 所有 active skill 的下一次主动触发。
- 取消已经 in-flight 的 active execution instance；不回滚已经触发过的 timeline action。
- 不冻结 buff tick / post-damage / deathrattle 这类被动响应。

### Chosen

Stun 是通用 buff recipe，不是每个技能各自复制一个 buff。核心属性是 `duration_ms`，由施加方传入：

```gdscript
HexBattleStunBuff.create_config(duration_ms)
```

固定 duration 的技能可以在自身 config 中持有 `STUN_DURATION_MS`，并把 `HexBattleStunBuff.create_config(STUN_DURATION_MS)` 交给 `HexBattleApplyBuffAction`。如果以后 duration 需要按 caster 属性 / 技能等级 / 命中结果动态计算，再扩展 ApplyBuffAction 接受 buff factory / resolver，在 execute 时生成 config；仍然不为每个技能复制一个 Stun buff class。

Stun buff 是状态生命周期所有者；它通过 `TagComponentConfig` 持有 `cant_act`，通过 `TimeDurationConfig` 控制持续时间，通过 on-apply action 显式取消当前 active execution instances。ActiveGateway 消费 `cant_act`，UI / cleanse / immunity 消费 buff 的 `stun` / `control` / `negative` ability tags。

Stun = `cant_act + interrupt active executions + duration`。`cant_act` 只挡未来入口；interrupt 只取消当前 execution instance；二者必须显式组合，不互相隐式触发。

重复施加 Stun 的 V1 策略是 independent instances：每一次 Stun 都 grant 一个新的 `HexBattleStunBuff` Ability 实例，不 refresh、不 replace、不合并 duration。这样可以保留来源追溯：每个 Stun 实例都能记录自己的 source skill / caster / applied_at / duration metadata。

独立实例的清理必须走 `TagComponentConfig` / `TagComponent` 的 component-owned tag 生命周期。`cant_act` 由每个 Stun Ability 实例贡献一份 component tag；某个 Stun 到期 remove 时只移除该 ability id 对应的 component tags。只要还有其它 Stun 实例贡献 `cant_act`，Gateway 仍应看到 actor 处于 `cant_act`。不要用 `LooseTagAction.Remove("cant_act")` 或手写 loose tag remove 表达 Stun remove cleanup，否则 A Stun 到期会误删 B Stun 的 gate tag。

### Rejected

- 不抽通用 interrupt policy：当前只有 Stun 一个真实用例，固定规则“取消 active execution instances”足够。
- 不让 `cant_act` 自动 cancel in-flight timeline：`cant_act` 只表示不能发起新行动。
- 不新建 StatusSystem：现有 buff + tag + gateway + lifecycle action 足够表达 V1。
- 不把 Stun 写成 `cant_use_skill`：Stun 是 hard control，Silence 才是 soft control。
- 不给 V1 强制增加 `stunned` component tag：buff ability_tags 已经承载 stun 语义。
- 不把重复 Stun 做成 refresh / replace / max-duration merge：这些会丢失单次眩晕来源，除非后续明确不再需要来源追溯。

### 待拍板问题

- Stun 是否给前端单独 stage cue / floating text？
- Stun interrupt 是否应记录单独 `executionInterrupted` / `abilityInterrupted` event，供 replay / frontend 解释后续 keyframe 为什么不再发生。

### 验收

- 被 stun 的 actor 无法 Move / Strike / 释放任意 active skill，并产生 `AbilityActivateFailed`。
- Stun apply 会取消目标当前 active execution instances。
- 已触发过的 timeline action 不回滚；未触发的 active timeline tag 不再执行。
- stun duration 结束后，Move / Strike / active skill 恢复。
- buff tick / post-damage / deathrattle 不被 Stun 阻断。
- 不同技能可以通过同一个 `HexBattleStunBuff.create_config(duration_ms)` 施加不同 duration 的 Stun，不需要为每个技能定义一个新 Stun buff。
- 多个 Stun 独立实例重叠时，一个实例到期不会清掉其它实例贡献的 `cant_act`；直到最后一个 Stun 移除后，actor 才恢复主动行动入口。

### 必测场景

新增 skill scenario：`stun_independent_instances_scenario.gd`。

Case 1：短 Stun 先施加，长 Stun 后施加。

- t=0ms：目标获得 Stun A，duration=1000ms，source=`stun_short`。
- t=500ms：目标获得 Stun B，duration=3000ms，source=`stun_long`。
- 预期：目标身上存在两个独立 `HexBattleStunBuff` Ability 实例，metadata 能区分 A / B 来源。
- 预期：t=1000ms 后 Stun A 到期并 remove，`cant_act` 仍为 true，因为 Stun B 仍在。
- 预期：t=3500ms 后 Stun B 到期并 remove，`cant_act` 才变为 false，Move / Strike / active skill 恢复可用。

Case 2：长 Stun 先施加，短 Stun 后施加。

- t=0ms：目标获得 Stun A，duration=3000ms，source=`stun_long`。
- t=500ms：目标获得 Stun B，duration=1000ms，source=`stun_short`。
- 预期：t=1500ms 后 Stun B 到期并 remove，`cant_act` 仍为 true，因为 Stun A 仍在。
- 预期：t=3000ms 后 Stun A 到期并 remove，`cant_act` 才变为 false。

这两个 case 的核心断言不是 UI 数字，而是 `AbilitySet` 中 Stun 实例数量、每个实例的 source metadata、以及 `ability_set.has_tag("cant_act")` 在每个时间点的状态。

## Phase B · Silence / 禁用技能

### 价值

Silence 要表达的是“在一定时间内，禁止 actor 使用主动技能”，不等同于不能移动 / 不能普攻。它应在 Stun 之后讨论，用来建立 soft control pattern。

这能补一个重要边界：control status 不应该全部混成一个 `cant_act`。

### 初始方案

新增一个负面 buff，例如 `silence_buff`：

- buff tags：`["buff", "negative", "control", "silence"]`
- component tag：`cant_use_skill`
- duration：短时，例如 2000ms
- skill：`skill_silence` 命中目标后 apply buff

Gateway 侧按 active gateway id / action kind 区分入口：

- `ACTIVE_SKILL` / 普通 active skill：被 `cant_use_skill` 阻止
- `ACTIVE_BASIC_ATTACK` / Strike：不被 `cant_use_skill` 阻止
- `ACTIVE_MOVE` / Move：不被 `cant_use_skill` 阻止

不能用 `ability_tags.has("skill")` 判定 Silence 是否生效；当前 Strike 也带 `"skill"` tag。Silence 的 gate policy 必须读 gateway id / action kind。

### Chosen

复用 ActiveGateway 的 runtime condition。Silence 是释放前 gate，不是 runtime cancel。

Silence buff 是状态生命周期所有者；它通过 `TagComponentConfig` 持有 `cant_use_skill`。ActiveGateway 根据 active ability 的 gateway / action kind 判定是否消费 `cant_use_skill`。UI / cleanse / immunity 消费 buff 的 `silence` / `control` / `negative` ability tags。

Silence = `cant_use_skill + duration`。它只挡未来主动技能入口，不取消已经 in-flight 的 execution，不影响 Move、Strike、passive、buff tick、DOT、deathrattle。

### Rejected

- 不直接用 `cant_act` 代替 silence：语义会变成 stun / stagger。
- 不取消已经 in-flight 的 ability timeline：这会碰 Timeline cancel 语义，当前不作为 V1。
- 不新建 StatusSystem：现有 buff + tag + ActiveGateway 足够表达。
- 不用 `ability_tags.has("skill")` 判断是否被 Silence 阻止：tag 用于分类 / UI / 查询；gate policy 应使用 gateway id / action kind。

### 待拍板问题

- 前端显示是否复用 buff icon / floating text，还是只进 log？

### 验收

- 被 silence 的 actor 使用普通主动技能时产生 `AbilityActivateFailed`，reason 可读。
- 被 silence 的 actor 仍可 Move。
- 被 silence 的 actor 仍可 Strike / basic attack。
- silence 不影响已在执行中的 timeline。
- silence 不影响 passive / buff tick / DOT / deathrattle。
- silence duration 结束后同一个主动技能可正常释放。

### 必测场景

新增 skill scenario：`silence_active_skill_gate_scenario.gd`。

- t=0ms：目标获得 Silence，duration=2000ms。
- 预期：目标尝试释放普通 active skill（例如 Fireball / Poison）失败，失败 reason 指向 `cant_use_skill`。
- 预期：目标尝试 Strike / basic attack 成功。
- 预期：目标尝试 Move 成功；AI / ATB path 和未来 direct player move path 都需要覆盖各自 gate。
- 预期：已开始的 active execution 不被 Silence 取消。
- 预期：passive / buff tick / deathrattle 在 Silence 期间照常触发。
- 预期：t=2000ms 后 `cant_use_skill` 消失，普通 active skill 恢复可用。

## Phase B2 · Break / 破坏

### 价值

Break 表达的是“在一定时间内，禁用 actor 的 passive skill”。它不等同于 Stun / Silence：Stun 管主动行动，Silence 管主动技能入口，Break 管被动技能。

Break 必须同时覆盖三类 passive：

- triggered passive：例如 Thorn / Deathrattle，靠事件触发。
- persistent passive：例如 Vigor / Vitality，持续注册属性依赖或 modifier。
- periodic passive：例如 DemonForm，靠 `GRANTED_SELF` 启动 periodic timeline。

### 初始方案

新增一个负面 buff，例如 `break_buff`：

- buff tags：`["buff", "negative", "control", "passive_break"]`
- component tag：`cant_use_passive`
- duration：短时，例如 2000ms
- on apply：对目标当前 passive abilities 增加 Break source，使它们进入 disabled state
- on remove：移除对应 Break source；只有最后一个 source 移除后，passive ability 才恢复

### Chosen

Break = `cant_use_passive + passive Ability disabled state + duration`。

Break 不让每个 passive skill 自己写 hook。状态由 Break buff 拥有；passive Ability 保留自己的 identity、stacks、source metadata、execution instance 和 trace。Break 期间 passive Ability 进入 disabled state：

- `Ability.receive_event()` 顶层短路，因此 Thorn / Deathrattle 这类 `NoInstanceComponent` triggered passive 不触发。
- `Ability.tick_executions()` 顶层短路，因此 DemonForm 这类 periodic passive 的 timeline instance 冻结，不 destroy、不 catch-up。
- persistent 外部注册效果由少数外部注册型 component 执行 break hook：`StatModifierComponent` / `DynamicStatModifierComponent` 临时撤销外部 stat modifier / dynamic dependency，Break 结束后按当前 Ability state 重新注册。

这条规则必须在未来实现处保留为代码注释，防止后续 AI / agent 把 break hook 扩散到所有 component：

```gdscript
# Passive Break rule:
# Only components that register persistent external state implement passive break hooks
# (StatModifierComponent / DynamicStatModifierComponent).
# NoInstanceComponent and ActivateInstanceComponent must not implement them:
# Ability disabled state gates event dispatch and timeline ticking.
```

DemonForm 的预期行为：

- Break 开始时，DemonForm Ability disabled；当前 atk bonus 失效；periodic timeline 冻结；stacks 保留。
- Break 期间，不增长 stacks，不补 tick。
- Break 结束时，atk bonus 按当前 stacks 恢复；periodic timeline 从冻结位置继续。
- 如果 Break 期间外部系统改了 DemonForm stacks，恢复时按当前 stacks 重建 stat modifier，这是允许行为。

### Rejected

- 不引入通用 `suspend_persistent_effect` / `resume_persistent_effect` 协议：这会让每类 component 都必须回答默认暂停/恢复语义，复杂度过高。
- 不让每个 passive skill 私有实现 Break hook：Vigor / Vitality / DemonForm 仍应只是组合 Ability components。
- 不 revoke / expire passive ability：Break 是临时禁用，不是移除能力；必须保留 stacks、source、trace、execution state。
- 不让 `NoInstanceComponent` / `ActivateInstanceComponent` 实现 break hook：事件触发和 timeline 推进由 Ability disabled state 顶层控制。
- 不在 Break 结束时 catch-up periodic tick：Break 期间的被动计时被冻结，错过的 tick 丢弃。

### 验收

- Break 期间，Thorn 被攻击不反伤；Break 结束后同样事件恢复触发。
- Break 期间，Vigor / Vitality 的属性收益失效；Break 结束后收益恢复，属性读取不出现 stale value。
- Break 期间，DemonForm stacks 不增长，atk bonus 失效，periodic timeline 不推进。
- Break 结束后，DemonForm atk bonus 按当前 stacks 恢复，timeline 继续，不补发 Break 期间错过的 tick。
- 多个 Break 重叠时，先结束的 Break 不会恢复 passive；只有最后一个 Break source 移除后才恢复。
- Break 期间 passive ability 被 revoke / expire 时，不重复注销外部注册状态，也不在 Break 结束时错误恢复已移除 ability。

### 必测场景

新增 skill scenario：`break_passive_disable_scenario.gd`。

- Thorn case：t=0ms apply Break，目标受到 damage，预期没有 reflect damage；t=2000ms 后 Break 结束，再次受到 damage，预期 Thorn 反伤。
- Vigor / Vitality case：apply Break 前记录 derived stat；Break 期间 derived stat 回到无 passive 的值；Break 结束后 derived stat 恢复。
- DemonForm case：DemonForm stacks=4 时 apply Break；Break 期间推进 6000ms，预期 stacks 仍为 4、atk bonus 失效；Break 结束后 atk bonus 按 stacks=4 恢复，后续 3000ms 后 stacks 变为 5。
- Overlap case：Break A duration=1000ms，Break B 在 t=500ms apply duration=3000ms；t=1000ms 后 passive 仍 disabled，t=3500ms 后 passive 恢复。

## Phase C · Fire Tile / 地形伤害格

> 前置：先完成 Phase C0 Summon Totem 正式实现。Fire Tile 不应先绕开 LGF 自建 tile registry；
> 先复用 Totem 打通的 actor spawn、actor-level lifetime、procedure 驱动与 replay/lifecycle 合同，
> 再判断 passable `EnvironmentActor` overlay 是否成立。
> `HexBattleSpawnActorAction` 是该前置的一部分：Totem 先用 `OCCUPANT` placement，Fire Tile 后续用
> `OVERLAY` placement。

### 价值

16 技能里有 actor buff、projectile、summon、death reaction，但还没有“格子本身带规则”的 board-control pattern。Fire Tile 是 hex tactics 很核心的机制，也能为 trap、ice tile、poison cloud 留样板。

### Spike 优先

这里先 spike，不直接写正式技能。关键未知是 grid 是否允许 passable overlay：

- `EnvironmentActor` 目前能表达环境物，但 grid occupant 可能天然一格一个 occupant。
- `CollisionProfile.blocks_path=false` 能表达“不阻挡寻路”，但不等于能与 character 共格。
- 如果不能共格，Fire Tile 不应伪装成普通 EnvironmentActor。

### 初始路线

路线 A：passable `EnvironmentActor`

- `environment_kind = "fire_tile"`
- `blocks_path=false`
- 不阻挡 actor 站上去
- 生成时立即造成一次 damage pulse；之后每隔固定 interval 再 pulse
- 每次 pulse 只检查 tick 当下站在该格子的 alive `CharacterActor`
- V1 不做 enter trigger：单位在两次 tick 之间进入，只会在下一次 tick 受伤；tick 前离开则不受伤
- 同一格允许多个 Fire Tile / `EnvironmentActor` overlay 并存；不 refresh、不 replace、不 merge、不 dedupe
- 每个 Fire Tile 实例独立 lifetime、独立 tick cadence、独立造成 damage pulse

路线 B：battle-level tile effect registry

- battle 维护 `coord -> tile_effects`
- tick 时扫描站在 effect 上的 actors
- event stream 记录 tile placed / tile expired / tile tick damage

### Chosen 倾向

先 spike 路线 A。如果 grid occupancy 不支持 overlay，则转路线 B。

### Fire Tile 契约

Fire Tile 是可叠加的 `EnvironmentActor` overlay，不占用 `grid.occupant`。同一个 hex coord 可以同时存在多个 Fire Tile 或其它 environment overlay；spawn 时不检查同格是否已有同类环境物。多个 Fire Tile 共存时，各自独立 lifetime、独立 tick、独立伤害归因和 replay 事件。

伤害 / 归因语义：

- Fire Tile 是普通 `EnvironmentActor`，不是无实体 tile effect。
- Fire Tile 配置为高 HP；正常情况下靠 lifetime 到期移除，但如果被反伤 / 其它伤害打死，就按普通 actor 死亡处理。
- Fire Tile pulse 的 `DamageEvent.source_actor_id = fire_tile_actor.id`。它就是造成伤害的 actor。
- Fire Tile actor 可额外记录 `creator_actor_id` / `source_skill_id` 作为追溯 metadata，但 combat attribution 不回填到 creator。
- Fire Tile pulse 走完整 damage pipeline：pre-damage、shield、damage event、death event、post-damage 都正常执行。
- 如果目标的 Thorn / 其它 post-damage 反应打回 source，Fire Tile 正常受伤；死了就按 `OVERLAY` cleanup 移除，没死就继续按 lifetime / tick 运行。

放置 / 清理语义：

- `HexBattleActor` 增加运行时 `placement_mode`，建议枚举为 `UNPLACED` / `OCCUPANT` / `OVERLAY`。
- `placement_mode` 是 hex grid 放置语义，和 `hex_position` / `collision_profile` 同层；不放到 LGF core `Actor`，也不只放在 `HexBattleSpawnActorAction` config。
- 只有 `HexWorldGameplayInstance` 的 placement / spawn API 能写 `placement_mode`，外部不要手改。
- `CharacterActor` / StoneWall 这类占格 actor 使用 `OCCUPANT`；Fire Tile 使用 `OVERLAY`。
- `remove_actor()` 按 `placement_mode` switch 清理：`OCCUPANT` 释放 `grid.occupant`，`OVERLAY` 只清 overlay registration。
- `OCCUPANT` 清理仍保留 identity guard：只有 `grid.get_occupant(coord) == actor` 时才 `remove_occupant(coord)`，防止脏位置误删别的 actor。
- `OVERLAY` 清理绝不碰 `grid.occupant`，否则 Fire Tile 到期会误删站在同格的角色。

Runtime tick 语义：

- Fire Tile 挂在 `EnvironmentActor` 上时，正式 battle runtime 必须 tick 所有 `HexBattleActor` 的 ability runtime。
- ATB 累积、AI 决策、主动行动启动仍然只属于 `CharacterActor`。
- 因此 battle tick 应拆成两条线：所有 `HexBattleActor` 跑 `ability_set.tick()` / `tick_executions()`；只有 alive `CharacterActor` 跑 ATB / AI。

时间语义：

- `spawn_time` 立即执行一次 damage pulse。
- 后续 pulse 从 `spawn_time + interval_ms` 开始，每隔 `interval_ms` 执行一次。
- 不双结算 `spawn_time`。
- pulse 命中对象是 tick 当下站在 Fire Tile coord 上的 alive `CharacterActor`。
- V1 没有 enter-trigger；进入格子本身不造成即时伤害。
- 同格有 N 个 Fire Tile 实例时，单位可能在同一时间点受到 N 次独立 pulse damage。

### Rejected

- 不把 Fire Tile 做成挂在 actor 身上的 burn buff：那是 DOT，不是 board hazard。
- 不用不可见 Actor 占格挡路：会把 hazard 误变成 wall。
- 不为 V1 引入同格唯一 / 刷新 duration / 合并层数规则：Fire Tile overlay 默认并存叠加。
- 不为 Fire Tile damage 跳过 post-damage：既然 Fire Tile 是 actor，就走普通 damage pipeline。
- 不把 Fire Tile 伤害归因给 creator：creator 只作为追溯 metadata，实际伤害 source 是 Fire Tile actor。
- 不先做通用 TileSystem：除非 Fire Tile + Trap + Aura 同时需要。

### 待拍板问题

- replay / frontend 需要哪些最小事件：placed、tick、expired？

### 验收

- actor 可站在 Fire Tile 上且寻路/占位不混乱。
- tick damage 走 `HexBattleDamageUtils.apply_damage`，能被护盾、death、post-damage 看到。
- Fire Tile pulse 的 damage / death event source 是 Fire Tile actor id；creator 只用于 metadata 追溯。
- Fire Tile 被 Thorn / post-damage 反应打中时正常扣高 HP；死亡时按 `OVERLAY` cleanup 移除。
- 同一 coord 可 spawn 多个 Fire Tile；它们不会互相覆盖或刷新，tick 时各自结算。
- replay event order 稳定；同 seed 重跑事件序列一致。

## Phase D · Cleanse / Dispel

### 价值

Poison / Expose / Silence / Burn 这类负面效果会越来越多，需要一个“状态清理”的范式。Cleanse 是 buff/debuff 系统的反向操作，能验证 ability lifecycle cleanup 是否可靠。

V1 只做 Cleanse：清理友方 / 自身负面状态。Dispel（驱散敌方 positive buff）是另一个技能，暂不混入本阶段。

### 初始方案

新增 `skill_cleanse`：

- target：友方 `CharacterActor` 或自己；不能选敌方，不能选 `EnvironmentActor`
- range：3
- effect：移除目标身上 1 个 negative buff Ability
- no-op：目标没有 negative buff 时，技能成功但不移除任何状态
- 无治疗效果

### Chosen

按 buff `ability_tags(["buff","negative"])` 选择并 revoke ability，让 buff 自己走 remove cleanup。

negative buff 定义：

```text
ability.has_ability_tag("buff") && ability.has_ability_tag("negative")
```

清理优先级：

1. 优先清 `ability_tags` 含 `control` 的 negative buff，例如 Stun / Silence。
2. 其次清 `ability_tags` 含 `passive_break` 的 negative buff。
3. 其余 negative buff 按 `AbilitySet.get_abilities()` 顺序，也就是 grant order。

执行建议：

```gdscript
target.ability_set.revoke_ability(
	negative_buff.id,
	AbilitySet.REVOKE_REASON_DISPELLED,
	"cleanse"
)
```

Cleanse 可以清控制类 negative，包括 Stun / Silence / Break；清理是否会立刻解除 `cant_act` / `cant_use_skill` / `cant_use_passive` 取决于对应 buff 的 component cleanup，但 Cleanse 不直接删 tag。

如果目标没有 negative buff，Action 返回 success + metadata `{ "cleanse_removed": false }`，不产生失败。

### Rejected

- 不直接删 tag：component tag / loose tag / buff state 来源不同，直接删 tag 容易漏 cleanup。
- 不做“万能清所有状态”：shield / stance / summon ownership 等 positive 或 structural 状态不应被误清。
- 不清全部 negative：V1 只清 1 个，测试和玩家反馈更清楚。
- 不附带治疗：避免一个技能同时验证 cleanse + heal 两套机制。
- 不把 Cleanse 写成框架层 Primitive Action，先作为 hex skill-local action；等多个技能需要时再抽 `HexBattleCleanseAction` 公共 primitive。
- 不在 V1 做 Dispel enemy positive buff：那是另一个技能。

### 待拍板问题

- 是否需要专属 `stageCue(cleanse)` / floating text，还是先只靠 `AbilityRemoved` 与 buff UI 消失表达？

### 验收

- Cleanse 可对自己释放，也可对友方释放；不能对敌方 / EnvironmentActor 释放。
- 清理 Poison / Expose / Silence / Break 至少两种不同实现形态。
- 被清理 buff 的 component cleanup 生效。
- 不误清 positive buff / shield / stance tag。
- 目标没有 negative buff 时成功 no-op，不产生错误。

## Phase E · Swap / 位置交换

### 价值

Push / Shadow Step 都是单 actor 位移。Swap 验证两个 actor 的 grid occupancy 原子变化，以及 replay / frontend 如何表达同一 tick 的双位移。

### 初始方案

新增 `skill_swap`：

- target：范围内任意一个存活 `CharacterActor`，友方 / 敌方都可以
- 不能选自己，不能选 `EnvironmentActor`
- range：3
- effect：caster 与 target 原子交换 `hex_position` 和 `grid.occupant`
- event：两个 `ActorDisplacedEvent`，带同一个 `swap_id`；caster event 先，target event 后
- failure：任一 actor dead / invalid / grid 状态不一致时，整个 swap 不发生
- 不造成伤害，不触发碰撞，不给双方加 `cant_act`

### Chosen

写 skill-local `_SwapPositionsAction`，内部做原子校验和占位交换。等第二个 swap-like 技能出现，再考虑 public primitive。

执行顺序：

```text
validate all:
- caster 是 alive CharacterActor
- target 是 alive CharacterActor
- caster != target
- caster.hex_position / target.hex_position 都 valid
- grid.get_occupant(caster_pos) == caster
- grid.get_occupant(target_pos) == target

commit:
- 临时清空两个 occupant
- target 放到 caster_pos
- caster 放到 target_pos
- 更新双方 hex_position
- push ActorDisplacedEvent(caster, from=caster_pos, to=target_pos, swap_id)
- push ActorDisplacedEvent(target, from=target_pos, to=caster_pos, swap_id)
```

所有 validate 必须先完成，再 commit。任一 validate 失败直接返回 failure，不改 grid / actor。

### Rejected

- 不用两次 PushAction：push 是方向位移和碰撞结算，swap 是占位交换，事件语义不同。
- 不先抽 `TeleportAction`：Shadow Step 的 teleport 与 swap 失败语义不同，先保持 skill-local。
- 不允许半成功：一个 actor 换了、另一个没换会破坏 grid/world 一致性。
- 不给双方加 `cant_act`：Swap 本身已经是即时位置操作，不额外引入行动锁。
- 不做 line-of-sight：V1 只检查 range。

### 验收

- 两个 actor 坐标互换，grid occupant 与 actor.hex_position 一致。
- 事件顺序稳定：caster `ActorDisplacedEvent` 在前，target `ActorDisplacedEvent` 在后，二者共享同一个 `swap_id`。
- blocked / dead / invalid target 不产生半成功。
- self target / EnvironmentActor target / out-of-range target 均失败且不改状态。

## Phase F · Lifesteal / 吸血

移到下一轮文档：[`advanced-skills-next-batch.md`](advanced-skills-next-batch.md#phase-f--lifesteal--吸血)。

当前定稿点：V1 做主动技能，吸血基准为 `DamageEvent.actual_life_damage * ratio`；不做 passive lifesteal，不让 reflected / self damage 触发 lifesteal。

## Phase G · Line / Cone AoE

移到下一轮文档：[`advanced-skills-next-batch.md`](advanced-skills-next-batch.md#phase-g--line--cone-aoe)。

当前倾向：先做 `Piercing Line`，新增 example-local `TargetSelector`，复用 `HexBattleDamageAction`；Cone 留后续第二个 shape。

## 暂缓项

| 候选 | 暂缓原因 |
|---|---|
| Pull | `PushAction` 已预留 distance / displacement_kind，新增 pattern 较少；可作为 Swap 前的小回归，不作为主 phase |
| Counter | 与 Thorn 的 PostDamage 反应重叠；等需要“防御姿态 + 反击”再做 |
| Flame Barrier | Thorns 变体，收益低 |
| Corpse / Exhume | 需要 corpse lifecycle，容易引入新系统；除非 Deathrattle + Summon 后明确需要 |
| Summon Wall | 与 Summon Totem / EnvironmentActor 重叠；等 Fire Tile spike 后再看 board object 统一策略 |
| Equipment On Hit | 属于装备系统，不放 LGF example 当前阶段 |
| Synergy / Star Level | 属于 inkmon meta 层，不放进技能示范库 |

## 推荐讨论顺序

1. 先拍板 Stun 语义：`cant_act + interrupt active executions + duration`，以及重复施加时的 duration 策略。
2. Silence 已收口为 `cant_use_skill + duration`：只挡普通 active skill，不挡 Move / Strike。
3. Break 已收口为 `cant_use_passive + passive Ability disabled state + duration`：Ability 顶层短路事件 / timeline，只有外部注册型 component 实现 break hook。
4. 先完成 Summon Totem 正式实现：新增 TOTEM class、actor-level lifetime、`summon_totem.gd`、`HexBattleTotemAttack`、procedure actor source / team list 合同。
5. 再决定 Fire Tile 是否进入 spike：这会影响后续 Trap / Wall / Hazard 的表示方式。
6. Cleanse 与 Stun / Silence / Break 可以成对设计：一个移除 negative control，一个验证 cleanup。
7. Swap 与 Line/Cone 都依赖方向/坐标语义，建议等 Shadow Step 的 facing 基础设施落地后再评审。
8. Lifesteal 独立性较强，可在 damage pipeline 稳定时穿插实现。

## 落码前总检查

- [x] 16 技能全部完成，`skill-implementation-progress.md` 已更新到 16 / 16 + Phase 2+ 区域到 9 / 9 (2026-05-24)。
- [x] 当前进阶技能的 Chosen / Rejected / 待拍板问题已收敛 (本文档 + advanced-skills-next-batch.md V1)。
- [x] 明确它补的是新 pattern (Stun/Silence/Break/Summon Totem/Fire Tile/Cleanse/Swap/Lifesteal/Piercing Line 各自代表独立 pattern,见 skill-implementation-progress.md 新 pattern 速查)。
- [x] 新 public Action / Condition / TargetSelector 必须登记 rationale；技能私有逻辑优先 SkillLocalAction。
    - 新 public Action: HexBattleCancelActiveExecutionsAction / HexBattleSpawnActorAction / HexBattleSpawnFireTileAction (都在 ALLOWLIST 登记)
    - 新 TargetSelector: _PiercingLineSelector (内嵌 piercing_line.gd, 私有不算 public)
    - 其它私有逻辑 (Cleanse / Swap / Lifesteal / FireTilePulse / TotemAttack 等) 走内嵌 SkillLocalAction
- [x] scenario 覆盖成功、失败、边界三类 case (per phase 至少 1 个 scenario, Break 4 个 case 覆盖 Thorn/Vigor/DemonForm/Overlap)。
- [x] 若涉及 grid / actor lifecycle / replay，先写 spike (Summon Totem Phase 05 spike) 或最小红测 (Break 4 scenarios TDD)。
- [x] 回写 `skill-implementation-progress.md` 的 Phase 2+ 区域或新增进阶进度表 (新增 Phase 2+ 表 + 新 pattern 速查行)。
