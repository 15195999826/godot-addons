# Advanced Skills Next Batch - Lifesteal + Line/Cone AoE

> 下一轮实现候选。当前优先级仍是 Summon Totem 正式实现 -> Fire Tile -> Cleanse -> Swap。
> 本文只保存暂缓技能的设计口径，避免 `advanced-skills-impl-plan.md` 主入口继续膨胀。

## Scope

本批次包含两个技能 / 机制：

- Lifesteal / 吸血：验证 `DamageEvent.actual_life_damage` -> heal 的桥接。
- Line / Cone AoE：验证 hex shape `TargetSelector`，不是新增 damage pipeline。

## Phase F · Lifesteal / 吸血

> 讨论备注：本节只是当前初稿。Lifesteal 还没有充分讨论，下一次实现前必须先和用户重新讨论技能形态、触发范围、排除规则与测试口径，不要直接按本文落码。

### 技能描述

V1 做主动技能，不做 passive lifesteal aura：

```text
Blood Strike
主动近战技能。对敌方 CharacterActor 造成物理伤害，并按本次实际生命伤害的一定比例治疗自己。
```

建议参数：

- target：敌方 `CharacterActor`
- range：1
- damage：复用近战物理 damage resolver，可先按 `caster.atk`
- lifesteal_ratio：50%

### Chosen

吸血基准定为：

```text
heal_amount = DamageEvent.actual_life_damage * lifesteal_ratio
```

语义：

- shield 全吸收时，`actual_life_damage = 0`，不吸血。
- 部分 shield / 减伤 / 易伤 / 暴击后，按最终实际生命伤害吸血。
- target 剩余 HP 小于伤害时，只按实际扣掉的生命值吸血，不按 overkill damage。
- self damage 不触发 lifesteal。
- reflected damage 不触发 lifesteal。
- overheal 不加新规则，走现有 `HexBattleHealAction` 的 clamp 规则。

实现建议：

- 使用 `HexBattleDamageAction.on_hit(...)` 回调读取当前 `DamageEvent.actual_life_damage`。
- 回调 action 可以先做 skill-local `_LifestealHealAction`。
- heal 仍走现有 heal pipeline / replay event，不直接改 HP。

### Rejected

- 不按 raw damage 吸血：会无视 shield、减伤、目标剩余 HP。
- 不在 PreDamage 阶段预估吸血：会和 shield / crit / expose 等后续修改冲突。
- 不先做 passive lifesteal：会引出“哪些伤害类型能触发吸血”的全局规则。
- 不让 reflected damage / self damage 触发 lifesteal。

### 验收

- shield 全吸收时 heal = 0。
- shield 部分吸收时 heal = `actual_life_damage * ratio`。
- target 低血量被 overkill 时，heal 只按实际扣掉的生命值计算。
- reflected damage / self damage 不触发 lifesteal。
- heal event 进入 replay，source / target 字段正确。

## Phase G · Line / Cone AoE

### 技能描述

这个 phase 主要补 hex shape target selector。技能可以二选一先做：

```text
Piercing Line
沿一个方向选取 N 格，命中线上的敌方 CharacterActor。
```

或：

```text
Flame Cone
以 caster 到目标方向为中心，命中前方扇形范围内的敌方 CharacterActor。
```

### Chosen 倾向

新增 example-local `TargetSelector` 子类，复用 Fireball / `HexBattleDamageAction` 伤害结算。

优先做 `Piercing Line`，因为它比 cone 更容易验证 6 向 direction、阻挡、hit order：

- direction：优先从 `caster -> selected target coord` 计算。
- length：先用 3。
- target filter：敌方 alive `CharacterActor`。
- damage：复用 `HexBattleDamageAction`。

### Rejected

- 不新增 `AoEAction`：形状选择是 `TargetSelector` 责任，伤害仍是 `DamageAction`。
- 不把 line / cone 全部一次做完：先做一个最能证明方向语义的 shape。
- 不依赖前端猜形状：如果需要表演，逻辑事件或 `stageCue` 要带 shape params。

### 待拍板问题

- direction 最终用 caster facing，还是 caster -> target？当前倾向 caster -> target。
- line 是否穿透 StoneWall / blocking `EnvironmentActor`？
- line 是否穿透第一个命中的 actor？
- cone 是否作为后续第二个 shape 再做？
- hit order 是否需要写入 replay，还是只要求同 tick 目标集合稳定？

### 验收

- TargetSelector 单测 / scenario 覆盖 6 个方向。
- 有 wall / occupied actor 时语义明确。
- 多目标 damage event 数量和目标集合稳定。
- 如有 stage cue，payload 带 shape params，frontend 不反推逻辑范围。
