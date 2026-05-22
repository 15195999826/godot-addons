# Hex Battle Gateway Contract

## 范围

本文固化 hex-atb-battle 的 Gateway 设计边界，用于后续 Stun / Silence / Passive seal / Buff gate 等状态控制机制。

Gateway 不是 LGF core 的新系统；它是 hex battle example 层的入口资格规则，用来复用现有 Ability / Component / Condition / metadata / tag 机制。

## 背景

当前主动技能大量重复：

```gdscript
.condition(Condition.NoTagCondition.new(HexBattleActionLockStatus.TAG_CANT_ACT))
```

Stun / Silence 会继续扩大这种重复：Stun 需要挡所有主动行动，Silence 需要只挡技能，不挡移动或普攻。

同时，已有设计约束不能被推翻：

- cast target eligibility 仍是 declarative metadata + query，不进 Condition。
- `can_use_skill_on()` 是 AI / UI / 玩家 cast 的事前查询入口。
- `Condition` 是事件到达后的 runtime gate，适合动态 actor state / cooldown / reactive trigger。
- SkillPreview 可以故意绕过部分 can-use 预判，让下游 ActiveUse 管道产生 `AbilityActivateFailed`。

因此 Gateway 的目标不是创建另一个施法系统，而是把“入口是否允许通过”的动态规则集中表达，并让 precheck / runtime enforcement 能共用同一套语义。

## 术语

| 术语 | 含义 |
|---|---|
| Gateway | 一个入口的资格规则，返回 ok / reason。 |
| Semantic status tag | 描述角色状态的 tag，例如 `stunned`、`silenced`。 |
| Functional gate tag | 被 Gateway 消费的功能 tag，例如 `cant_act`、`cant_skill`。 |
| Target eligibility | range / team / allowed target kind / self 等目标合法性。 |
| Runtime gate | event 已到达 component 后的动态拦截，例如 `cant_act`、cooldown。 |

## 决策

### 1. Gateway 是入口资格，不是效果执行

Gateway 只回答“这次入口能不能通过”。

它不负责：

- 执行 damage / heal / move。
- 创建、移除、刷新 buff。
- 维护 tag 生命周期。
- 推进 timeline。
- 选择 action 列表。

### 2. 先实现 ActiveGateway，Passive / Buff 延后

Gateway 家族按入口分三类：

| 家族 | 入口 | 初始状态 |
|---|---|---|
| ActiveGateway | `abilityActivate` -> `ActiveUseComponent` | 先实现 |
| PassiveGateway | `NoInstanceComponent` / `PreEventComponent` reaction | 先设计，后实现 |
| BuffGateway | buff grant / apply / tick / aura | 先设计，后实现 |

Stun / Silence 只要求 ActiveGateway。Passive / Buff 不应在第一轮顺手铺开。

例外：`Move` 当前使用 `ActivateInstanceConfig`，不是 `ActiveUseConfig`。AI / ATB 路径下，`cant_act` 由 `CharacterActor.can_act()` 的 primary gate 阻止；未来如果出现玩家直控 move command，需要给该 direct path 补 action-lock gate，或把 Move 迁入 ActiveUse 管道。

### 3. Active ability 在 hex battle 中有且仅有一个 ActiveUseComponent

LGF core 的 `AbilityConfig.active_use_components` 是 Array，core 允许一个 Ability 有多个 ActiveUseConfig。

hex-atb-battle 收紧 example 层合同：

```text
可主动释放的 hex Ability 必须有且仅有一个 ActiveUseComponent。
```

因此 `can_use_skill_on(actor, skill, target)` 可以直接读取唯一 ActiveUseComponent 的 gateway 配置，不需要额外 snapshot / profile 复制层。

如果未来出现确实需要多个 active entry 的复合技能，应先拆成多个 Ability；只有拆分不成立时再重新讨论多 ActiveUse contract。

### 4. Component type 可以有默认 Gateway，并允许覆盖

默认 Gateway 由 component type 提供：

| Component | 默认 Gateway | 备注 |
|---|---|---|
| `ActiveUseComponent` | `ACTIVE_SKILL` | 可覆盖为 `ACTIVE_MOVE` / `ACTIVE_BASIC_ATTACK` / `NONE`。 |
| `NoInstanceComponent` | `PASSIVE_TRIGGER` | PassiveGateway 实现前 pass-through + warning。 |
| `PreEventComponent` | `PRE_EVENT` | PassiveGateway 实现前 pass-through + warning。 |
| `TagComponent` | `NONE` | 只表达生命周期 tag，不作为触发入口。 |
| Time duration / lifecycle component | `NONE` | 不做触发 gate。 |

覆盖规则：

1. component 显式 gateway 优先。
2. 没有显式配置时使用 component type 默认值。
3. 非 active gateway 在实现前 pass-through + warning。
4. validator 后续要求非 active trigger component 显式 gateway 或 `NONE`。

### 5. Target eligibility 不进 ActiveGateway runtime Condition

保留既有原则：

```text
range / target kind / ally / enemy / self
    -> ability metadata + can_use / can_target query
    -> 不进 Condition
```

ActiveGateway runtime condition 只处理动态 actor state，例如：

- `cant_act`
- `cant_skill`
- `cant_move`
- `cant_basic_attack`

Cooldown / resource cost 继续保留在现有 `Condition` / `Cost` 机制中。

### 6. `can_use_skill_on` 需要拆语义

当前 `can_use_skill_on(actor, skill, target)` 实际只做 target eligibility。

新命名建议：

```text
can_target_skill_on(actor, skill, target)
    只检查 target eligibility。

can_use_skill_on(actor, skill, target)
    检查 active gateway + target eligibility。
```

迁移期可以先保留旧函数名，但文档和 validator 中必须说明它是否已经升级为完整 use check。

### 7. 状态 tag 集中在 hex game layer

不要把 `stunned` / `silenced` / `cant_act` / `cant_skill` 放进 LGF core。core 只提供 tag / ability / condition 机制。

建议新增 hex 层集中定义：

```text
HexBattleStatusTags
    STUNNED
    SILENCED
    ROOTED

HexBattleGateTags
    CANT_ACT
    CANT_SKILL
    CANT_MOVE
    CANT_BASIC_ATTACK
    CANT_PASSIVE
```

语义 tag 和功能 gate tag 可以同时存在。例如 Stun buff 持有：

```text
stunned
control
status
cant_act
```

UI / cleanse / immunity 可以读 `stunned`、`control`；ActiveGateway 只消费 `cant_act`。

## Rejected

### 全局 StatusSystem

V1 不需要。现有 `Ability` + `TagComponentConfig` + `TimeDurationConfig` 足够表达状态生命周期。

### Ability-wide-only Gateway

一个 Ability 共享一个 Gateway 心智简单，但会把混合 component 的语义绑死。默认 Gateway 放在 component type 上更贴近实际触发入口。

约束不是禁止 Ability 级语义，而是要求 active ability 的唯一 active entry 可以被稳定查询。

### TargetPolicy + TargetAllowedCondition 路径

已在 2026-04-29 design note 中撤销。目标合法性是 declarative metadata，不应变成 runtime condition。

### Gateway snapshot / precomputed profile

Active ability 已有唯一 ActiveUseComponent 合同，不需要再复制一份 snapshot。后续如性能或 UI 离线配置查询需要，再添加只读 profile。

### Timeline cancel / interrupt

Stun / Silence V1 是释放前 gate，不取消已经 in-flight 的 execution instance。

## Validator 要求

第一阶段：

- active ability 必须有且仅有一个 ActiveUseComponent。
- active ability 必须能 resolve 出 active gateway。
- active ability 不能手写重复 `NoTagCondition(cant_act)`，应走 ActiveGateway wrapper / builder。
- 非 active trigger component 缺 gateway 时 warning。

第二阶段：

- 非 active trigger component 必须显式 gateway 或 `NONE`。
- 混合 active + passive + buff 语义的 Ability warning，建议拆 Ability。

## 验收用例

### ActiveGateway

- actor 持有 `cant_act` 时，Strike / active skill 的 direct `abilityActivate` 被 ActiveGateway runtime condition 拦住。
- actor 持有 `cant_act` 时，AI / ATB 路径的 Move 被 `CharacterActor.can_act()` primary gate 拦住。
- 未来 direct player move path 必须单独验证 action-lock gate，不能默认认为 ActiveGateway 已覆盖。
- actor 持有 `cant_skill` 时，非基础 active skill 被挡；Move / basic attack 是否允许按设计约定验证。
- direct `abilityActivate` 绕过 AI / ATB 时也会被 ActiveGateway runtime condition 拦住。
- 已经 in-flight 的 timeline 不被取消。

### `can_use` / `can_target`

- out-of-range target 被 `can_target_skill_on` 拦。
- target kind 不在 `allowedTargetKinds` 被 `can_target_skill_on` 拦。
- actor `cant_act` 被 `can_use_skill_on` 拦。
- `can_target_skill_on` 不因 caster `cant_act` 返回 false。

### Passive / Buff 边界

- Stun 不阻止 thorn / deathrattle / buff tick。
- 后续如果实现 `cant_passive`，必须有单独 scenario 证明它只挡对应 PassiveGateway。

## 实施顺序

1. 定义 `HexBattleStatusTags` / `HexBattleGateTags`。
2. 定义 ActiveGateway 的 gateway id 与 check result。
3. 给 active ability 加唯一 ActiveUse validator。
4. 用 ActiveGateway wrapper / condition 替换重复 `cant_act` condition。
5. 实现 Stun。
6. 实现 Silence。
7. 再评估 PassiveGateway / BuffGateway。
