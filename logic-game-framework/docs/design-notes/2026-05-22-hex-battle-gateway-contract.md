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
| Semantic ability tag | 描述 buff / status 语义的 ability tag，例如 `stun`、`silence`、`control`。 |
| Functional gate tag | 被 Gateway 消费的功能 tag，例如 `cant_act`、`cant_use_skill`、`cant_use_passive`。 |
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

Stun / Silence 只要求 ActiveGateway。Break / 破坏是第一批 PassiveGateway / passive Ability disabled state 的候选，但不应混进 ActiveGateway 第一轮实现。

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

每类 component 的默认 Gateway slot 由 LGF core 配置；Gateway slot 的具体规则由 example / game layer 实现。

这里要区分两件事：

- Gateway slot / id：入口类别，例如 `ACTIVE_USE`、`PASSIVE_TRIGGER`、`PRE_EVENT`、`NONE`。这是 core 可以知道的组件管道事实。
- Gateway policy：这个入口具体被什么状态挡住，例如 `cant_act`、`cant_use_skill`。这是 hex battle 的游戏规则，core 不知道。

因此 core 可以给 component class 配默认 slot：

```gdscript
class_name CoreGatewayIds

const COMPONENT_DEFAULT := ""
const NONE := "none"
const ACTIVE_USE := "active_use"
const PASSIVE_TRIGGER := "passive_trigger"
const PRE_EVENT := "pre_event"
```

```gdscript
class_name ActiveUseComponent

const COMPONENT_TYPE := "ActiveUseComponent"
const DEFAULT_GATEWAY_ID := CoreGatewayIds.ACTIVE_USE
```

下表是 core 的默认 slot，不是 hex battle 的状态规则：

| Component | 默认 Gateway slot | 备注 |
|---|---|---|
| `ActiveUseComponent` | `ACTIVE_USE` | hex battle 默认解释为普通 active skill；可覆盖为 `hex_active_basic_attack` / `hex_active_move` / `NONE`。 |
| `NoInstanceComponent` | `PASSIVE_TRIGGER` | PassiveGateway policy 实现前 pass-through + warning。 |
| `PreEventComponent` | `PRE_EVENT` | PassiveGateway policy 实现前 pass-through + warning。 |
| `TagComponent` | `NONE` | 只表达生命周期 tag，不作为触发入口。 |
| Time duration / lifecycle component | `NONE` | 不做触发 gate。 |

覆盖规则：

1. config 显式 gateway override 优先。
2. 没有显式 override 时，使用 component class 的 `DEFAULT_GATEWAY_ID`。
3. `NONE` 明确表示不进入 Gateway policy。
4. 非 active gateway 在 hex policy 实现前 pass-through + warning。
5. validator 后续要求非 active trigger component 显式 gateway 或 `NONE`。

示例：

```gdscript
# 普通主动技能：不写 gateway，core 使用 ActiveUseComponent.DEFAULT_GATEWAY_ID = ACTIVE_USE。
ActiveUseConfig.builder()
	.timeline_id(TIMELINE_ID)
	.build()

# 基础攻击：显式覆盖默认 slot。这个 id 属于 hex battle，core 只当字符串传递。
ActiveUseConfig.builder()
	.gateway(HexBattleGatewayIds.ACTIVE_BASIC_ATTACK)
	.timeline_id(TIMELINE_ID)
	.build()

# 特殊入口：显式声明不走 Gateway。
ActiveUseConfig.builder()
	.gateway(CoreGatewayIds.NONE)
	.timeline_id(TIMELINE_ID)
	.build()
```

调用方向必须保持为：

```text
LGF core -> 调用 core GatewayPolicyRegistry
hex      -> 注册 HexBattleGatewayPolicyProvider
```

core 不能调用 `HexBattleGatewayPolicy` 这个具体类，也不要求 `HexWorldGameplayInstance` 实现 `get_gateway_policy()`。core 只调用一个可被项目层替换的 provider registry。hex battle 在初始化阶段注册自己的 provider。

示意：

```gdscript
class_name GatewayCheckResult

var ok := true
var reason := ""
var failed_component_type := "gateway"

static func ok_result() -> GatewayCheckResult:
	return GatewayCheckResult.new()

static func blocked(block_reason: String) -> GatewayCheckResult:
	var result := GatewayCheckResult.new()
	result.ok = false
	result.reason = block_reason
	return result
```

```gdscript
class_name GatewayPolicy
extends RefCounted

func check(
	gateway_id: String,
	component_type: String,
	ctx: AbilityLifecycleContext,
	event_dict: Dictionary,
	game_state_provider: Variant
) -> GatewayCheckResult:
	return GatewayCheckResult.ok_result()
```

```gdscript
class_name GatewayPolicyProvider
extends RefCounted

func check(
	gateway_id: String,
	component_type: String,
	ctx: AbilityLifecycleContext,
	event_dict: Dictionary,
	game_state_provider: Variant
) -> GatewayCheckResult:
	return GatewayCheckResult.ok_result()
```

```gdscript
class_name GatewayPolicyRegistry

static var _provider: GatewayPolicyProvider = GatewayPolicyProvider.new()

static func set_provider(provider: GatewayPolicyProvider) -> void:
	Log.assert_crash(provider != null, "GatewayPolicyRegistry", "provider is required")
	_provider = provider

static func check(
	gateway_id: String,
	component_type: String,
	ctx: AbilityLifecycleContext,
	event_dict: Dictionary,
	game_state_provider: Variant
) -> GatewayCheckResult:
	return _provider.check(gateway_id, component_type, ctx, event_dict, game_state_provider)
```

`ActiveUseComponent` 的顺序变成：

```text
trigger matched
-> gateway check
-> conditions
-> costs
-> activate execution
```

core 在 gateway check 阶段只做：

```gdscript
var gateway_id := _resolve_gateway_id_from_config_or_component_default()
if gateway_id != CoreGatewayIds.NONE:
	var result := GatewayPolicyRegistry.check(gateway_id, type, ctx, event_dict, game_state_provider)
	if not result.ok:
		_push_activate_failed(ctx, event_dict, result.reason, result.failed_component_type)
		return false
```

hex battle 的 provider 才解释：

```gdscript
class_name HexBattleGatewayPolicyProvider
extends GatewayPolicyProvider

func check(
	gateway_id: String,
	component_type: String,
	ctx: AbilityLifecycleContext,
	event_dict: Dictionary,
	game_state_provider: Variant
) -> GatewayCheckResult:
	if gateway_id == CoreGatewayIds.ACTIVE_USE:
		return _check_active_skill(ctx)
	if gateway_id == HexBattleGatewayIds.ACTIVE_BASIC_ATTACK:
		return _check_basic_attack(ctx)
	if gateway_id == HexBattleGatewayIds.ACTIVE_MOVE:
		return _check_move(ctx)
	return GatewayCheckResult.ok_result()
```

注册点应该是 hex battle 的 bootstrap / setup 入口，而不是每个 skill：

```gdscript
class_name HexBattleGatewayBootstrap

static func install() -> void:
	GatewayPolicyRegistry.set_provider(HexBattleGatewayPolicyProvider.new())
```

如果未来同一进程需要并行跑多个 game layer，再把 `GatewayPolicyRegistry` 扩展为按 `game_state_provider.type` / project id 选择 provider；V1 先保持一个项目级 provider，避免把 policy 绑到 world 实例上。

也就是说，不是把 Gateway 写成 `.condition(HexBattleActiveGatewayCondition.new(...))`。那只是没有 core hook 时的临时替代方案，不作为本方案的 Chosen path。

### 4.1 Implementation boundary

LGF core 可以承载 gateway metadata 和调用通用 gateway hook，但不得解释项目层 Gateway policy。

允许放在 core 的内容：

- `gateway_id: String` 这类 opaque config 字段。
- builder 上的 `.gateway(value: String)` 这类赋值 API。
- component class 的默认 Gateway slot，例如 `ActiveUseComponent.DEFAULT_GATEWAY_ID = CoreGatewayIds.ACTIVE_USE`。
- `GatewayPolicyProvider` / `GatewayPolicyRegistry` / `GatewayCheckResult` 这类抽象机制。
- serialize / debug 输出中的 gateway 原始字符串。

不得放进 core 的内容：

- `ACTIVE_BASIC_ATTACK` / `ACTIVE_MOVE` 等 hex-specific Gateway id。
- `cant_act` / `cant_use_skill` / `cant_use_passive` / `stun` / `silence` / `passive_break` 等 hex-specific tag。
- Silence 只阻止普通 active skill，不阻止 basic attack / Move。
- Stun / Silence 的 block reason 文案。

这些全部由 hex battle example 层定义，例如：

- `HexBattleGatewayIds`
- `HexBattleSemanticAbilityTags`
- `HexBattleGateTags`
- `HexBattleGatewayPolicyProvider`

### 5. Target eligibility 不进 ActiveGateway runtime Condition

保留既有原则：

```text
range / target kind / ally / enemy / self
    -> ability metadata + can_use / can_target query
    -> 不进 Condition
```

ActiveGateway runtime condition 只处理动态 actor state，例如：

- `cant_act`
- `cant_use_skill`
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

### 7. 状态语义集中在 hex game layer

不要把 `stun` / `silence` / `cant_act` / `cant_use_skill` 放进 LGF core。core 只提供 tag / ability / condition / gateway hook 机制。

建议新增 hex 层集中定义：

```text
HexBattleSemanticAbilityTags
    STUN
    SILENCE
    PASSIVE_BREAK
    CONTROL
    NEGATIVE

HexBattleGateTags
    CANT_ACT
    CANT_USE_SKILL
    CANT_MOVE
    CANT_BASIC_ATTACK
    CANT_USE_PASSIVE
```

语义优先放在 buff ability 本身的 `ability_tags`，功能 gate 放在 component tag。V1 不要求额外挂 `stunned` component tag，除非出现必须 `actor.ability_set.has_tag("stunned")` 的真实消费者。

例如 Stun buff 定义为：

```text
ability_tags:
    buff
    negative
    control
    stun

component tags:
    cant_act
```

UI / cleanse / immunity 读 buff 的 `stun` / `control` / `negative` ability_tags；ActiveGateway 只消费 `cant_act`。

Stun buff 是全局通用 buff recipe，不应按每个技能复制一个 buff class。不同技能需要不同持续时间时，用参数化 factory 生成同一语义的 buff config：

```gdscript
HexBattleStunBuff.create_config(duration_ms)
```

施加型主动技能只传入 duration 并 grant 这份 buff config；重复 grant、刷新持续时间、覆盖旧实例等策略归 Stun buff 自己定义，不分散到每个施加技能里。

固定 duration 的技能可以在配置构建时调用 `HexBattleStunBuff.create_config(STUN_DURATION_MS)`。如果未来 duration 需要按 caster 属性、技能等级、命中结果动态计算，再扩展 ApplyBuffAction 接受 buff factory / resolver，在 execute 时生成 config；仍然不为每个技能复制一个 Stun buff class。

## Break / Passive disabled state

Break / 破坏的状态语义是“duration 内禁用 passive skill”，不是 `cant_act` 或 `cant_use_skill` 的变体。

Break buff 定义为：

```text
ability_tags:
    buff
    negative
    control
    passive_break

component tags:
    cant_use_passive
```

Break = `cant_use_passive + passive Ability disabled state + duration`。

`cant_use_passive` 是 hex-specific functional gate tag，用于表达 actor 当前处于 passive disabled 状态。真正让已有 passive 暂停的执行点是 passive Ability 自身的 disabled state，而不是把 Break 逻辑塞进每个 passive skill。

被 Break disabled 的 passive Ability 必须保留自己的 ability id、config id、stacks、source metadata、execution instance 和 trace。disabled 期间：

- `Ability.receive_event()` 顶层短路，`NoInstanceComponent` / `PreEventComponent` 这类 triggered passive 不再响应事件。
- `Ability.tick_executions()` 顶层短路，`ActivateInstanceComponent` 启动的 periodic passive timeline 冻结，不 destroy、不 catch-up。
- 只有外部注册型 persistent effect component 执行 break hook，临时撤销并恢复外部注册状态。

这条规则必须在未来实现处保留为代码注释：

```gdscript
# Passive Break rule:
# Only components that register persistent external state implement passive break hooks
# (StatModifierComponent / DynamicStatModifierComponent).
# NoInstanceComponent and ActivateInstanceComponent must not implement them:
# Ability disabled state gates event dispatch and timeline ticking.
```

当前明确允许实现 break hook 的 component 类型：

- `StatModifierComponent`
- `DynamicStatModifierComponent`

当前明确不应实现 break hook 的 component 类型：

- `NoInstanceComponent`：由 Ability disabled state 拦截 `receive_event()`。
- `ActivateInstanceComponent`：由 Ability disabled state 拦截 `tick_executions()`。
- `TagComponent` / `TimeDurationComponent`：它们表达状态生命周期，不表达 passive 效果。

DemonForm 用于校验这个边界：Break 期间 DemonForm 的 stat bonus 失效，periodic timeline 冻结，stacks 保留；Break 结束后 stat bonus 按当前 stacks 恢复，timeline 从冻结位置继续，不补发 Break 期间错过的 tick。

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

### Gateway 自动 cancel / implicit interrupt

`cant_act` / Gateway 不自动取消已经 in-flight 的 execution instance。Gateway 只挡未来入口。

Stun V1 的语义包含“眩晕并打断当前抬手”，因此必须在 Stun buff apply 时显式组合 interrupt primitive，例如 `CancelActiveExecutionsAction`。这个 action 只取消目标当前 `ability_tags` 含 `active` 的 execution instances，不 revoke ability，不取消 buff / passive / DOT / aura / deathrattle execution。

Silence V1 仍然只是释放前 gate，不取消已经 in-flight 的 execution instance。它消费 `cant_use_skill`，只阻止普通 active skill，不阻止 Move / basic attack。

## Validator 要求

第一阶段：

- active ability 必须有且仅有一个 ActiveUseComponent。
- active ability 必须能 resolve 出 active gateway。
- active ability 不能手写重复 `NoTagCondition(cant_act)`，应走 Gateway hook / builder。
- 非 active trigger component 缺 gateway 时 warning。

第二阶段：

- 非 active trigger component 必须显式 gateway 或 `NONE`。
- 混合 active + passive + buff 语义的 Ability warning，建议拆 Ability。

## 验收用例

### ActiveGateway

- actor 持有 `cant_act` 时，Strike / active skill 的 direct `abilityActivate` 被 ActiveGateway runtime condition 拦住。
- actor 持有 `cant_act` 时，AI / ATB 路径的 Move 被 `CharacterActor.can_act()` primary gate 拦住。
- 未来 direct player move path 必须单独验证 action-lock gate，不能默认认为 ActiveGateway 已覆盖。
- actor 持有 `cant_use_skill` 时，普通 active skill 被挡；Move / basic attack 仍允许。
- direct `abilityActivate` 绕过 AI / ATB 时也会被 ActiveGateway runtime condition 拦住。
- `cant_act` / Gateway 本身不取消已经 in-flight 的 timeline。

### Stun interrupt

- Stun apply 会取消目标当前 active execution instances。
- interrupt 只作用于 `AbilityExecutionInstance`，不 revoke / remove ability。
- interrupt 不回滚已经触发过的 timeline action：投射物已发射就不追回；未到发射 tag 则不会再发射。
- buff / passive / DOT / aura / deathrattle execution 不被 Stun interrupt 取消。

### `can_use` / `can_target`

- out-of-range target 被 `can_target_skill_on` 拦。
- target kind 不在 `allowedTargetKinds` 被 `can_target_skill_on` 拦。
- actor `cant_act` 被 `can_use_skill_on` 拦。
- `can_target_skill_on` 不因 caster `cant_act` 返回 false。

### Passive / Buff 边界

- Stun 不阻止 thorn / deathrattle / buff tick。
- Break 持有 `cant_use_passive` 时，triggered passive 不响应事件，periodic passive timeline 冻结，persistent passive 的外部注册效果失效。
- Break 期间 buff tick / DOT tick 不应被误挡，除非该 buff 明确也是 passive ability。
- Break 实现时必须有单独 scenario 证明 `cant_use_passive` 只挡对应 passive ability，不影响 active skill / buff tick。

## 实施顺序

1. 定义 `HexBattleSemanticAbilityTags` / `HexBattleGateTags`。
2. 定义 ActiveGateway 的 gateway id 与 check result。
3. 给 active ability 加唯一 ActiveUse validator。
4. 用 Gateway hook / builder 替换重复 `cant_act` condition。
5. 实现 `CancelActiveExecutionsAction`，只取消 active execution instances。
6. 实现参数化 `HexBattleStunBuff.create_config(duration_ms)`。
7. 实现 Stun skill，施加方只传 duration 并 grant Stun buff。
8. 实现 Silence。
9. 实现 Break：`cant_use_passive` + passive Ability disabled state + 外部注册型 component break hook。
10. 再评估 BuffGateway。
