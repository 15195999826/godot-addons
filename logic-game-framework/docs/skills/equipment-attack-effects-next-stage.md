# Equipment Attack Effects Post-V1

> Phase G V1 已落地。本文保留装备 grant passive、Daedalus-like critical strike、`PreBasicAttackEvent` / `BasicAttackLandedEvent` 边界，以及后续攻击特效扩展路线。

## Scope

Phase G V1 只验证“装备如何给角色提供攻击触发效果”，不做完整装备系统大重构。

目标：

- 装备可以给 owner grant passive ability。
- 装备可以提供属性，例如 `attack_lifesteal_pct`。
- 装备可以提供攻击特效：由普攻触发，或参与普攻伤害计算的装备效果统称。
- 装备移除后，相关属性和监听效果随 ability 生命周期撤销。

明确不做：

- 不把装备提升为 `Actor`，除非后续出现装备可被战斗事件直接命中、装备自身有 HP / cooldown / aura-modified stats 等需求。
- 不引入玩法层“法球”概念；本阶段只讨论攻击特效。
- 不修改 `Strike` 本体去硬编码具体装备效果。

## Baseline From Current Batch

已具备的基础能力：

```text
Strike Ability
  -> PreBasicAttackEvent(attack_damage, source_actor_id, target_actor_id, ...)
  -> DamageAction(final attack_damage)
       -> PreDamageEvent(generic damage modifiers)
       -> DamageEvent(actual_life_damage, ...)
  -> BasicAttackLandedEvent(attacker, target, source_ability_id, actual_life_damage, damage_event payload)
```

命名约定：

- 用 `BasicAttack` 表达“普攻 / 普通攻击”。
- 不用 `BaseAttack`，避免和 base attack damage / base atk 混淆。
- Phase G 已把普攻命中事件代码名统一为 `BasicAttackLandedEvent`，让代码名和事件语义一致。

消费者边界：

- 属性驱动效果由 `HexBattleGeneralPassive` 消费，例如 `attack_lifesteal_pct`。
- 装备攻击特效由装备 grant 的 passive ability 声明；普攻结算类效果优先复用新增的 `PreBasicAttackEvent`，后置 on-hit 效果才监听 `BasicAttackLandedEvent`。
- `PreDamageEvent` 继续只表达“任意伤害应用前”的通用修改，例如易伤、减伤、护盾前修正；它不承载“这是不是一次普攻”的语义。
- 普通技能伤害继续只依赖 `DamageEvent`，不触发普攻装备效果。

## Equipment Integration

Phase G V1 已落地：

- 装备作为 actor 持有的数据项或 container item，不直接成为 battle actor。
- 装备 grant 被动 ability 给 owner；item config 用数据声明授予关系。
- 被动 ability 负责：
  - 修改属性，例如 `attack_lifesteal_pct`。
  - 或注册 `PreBasicAttackEvent` handler，例如 critical strike chance / multiplier。
  - 或响应攻击命中事件，例如 on-hit slow、bonus damage。
- 移除装备时 revoke 对应 ability，属性和监听效果随 ability 生命周期撤销。

V1 item config shape：

```gdscript
_configs[&"daedalus_charm"] = {
	"id": &"daedalus_charm",
	"display_name": "Daedalus Charm",
	"icon_key": "rune",
	"max_stack": 1,
	"item_tags": [&"equipment"],
	"equipable": true,
	"granted_abilities": [
		{
			"ability_config_id": &"passive_daedalus_critical_strike",
			"source": &"equipment",
		},
	],
}
```

`ability_config_id` 的解析归 hex logic 层，不归 SkillPreview UI。V1 可以从 `HexBattleAllSkills.all_abilities()` 派生 `config_id -> AbilityConfig` map，或抽一个 hex equipment ability resolver；`HexBattleSkillIndex` 只服务 SkillPreview 技能选单，不作为装备 runtime 依赖。

装备只声明“授予哪个 ability”。Daedalus-like 暴击规则属于被授予的 passive ability：

```gdscript
AbilityConfig.builder()
	.config_id(&"passive_daedalus_critical_strike")
	.ability_tags(["passive", "equipment", "attack_effect", "critical_strike"])
	.meta(&"attack_effect", {
		"kind": &"critical_strike",
		"chance": 1.0,
		"damage_multiplier": 2.25,
	})
	.component_config(_build_pre_basic_attack_config())
```

`_build_pre_basic_attack_config()` 复用现有 `PreEventConfig` 机制，但挂在新增的普攻前事件上：

```gdscript
PreEventConfig.new(
	HexBattlePreEvents.PRE_BASIC_ATTACK_EVENT,
	func(_mutable: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
		if randf() >= CHANCE:
			return EventPhase.pass_intent()
		return EventPhase.modify_intent(ctx.ability.id, [
			Modification.multiply("attack_damage", DAMAGE_MULTIPLIER, ctx.ability.config_id, "Daedalus Critical"),
			Modification.set_value("is_critical", 1.0, ctx.ability.config_id, "Daedalus Critical"),
		]),
	func(event_dict: Dictionary, ctx: AbilityLifecycleContext) -> bool:
		return event_dict.get("source_actor_id", "") == ctx.owner_actor_id,
	"Daedalus Critical Strike"
)
```

Phase G 需要新增 `PreBasicAttackEvent`，不把普攻语义塞进 `PreDamageEvent`：

- `kind`: `HexBattlePreEvents.PRE_BASIC_ATTACK_EVENT`。
- `source_actor_id`: attacker actor id。
- `target_actor_id`: attack target actor id。
- `attack_damage`: 本次普攻进入通用伤害链路前的攻击伤害。
- `source_ability_id` / `source_ability_config_id`: 用于 replay / debug / 精确过滤。
- `is_critical`: numeric flag，默认 `0.0`；pre-basic-attack handler 命中后设为 `1.0`，`Strike` / basic attack action 转成 `DamageEvent.is_critical`。
- Phase G 先不加 `damage_role` / `can_crit` / `damage_type` 到该事件；如果后续出现“某些普攻不可暴击”或“普攻伤害类型可被装备改写”，再按真实需求补字段。

这样 Daedalus 是已有 PreEvent 系统里的一个 outgoing pre-basic-attack modifier，而不是旁路系统，也不会污染普通 skill / DOT / reflected damage 的 `PreDamageEvent`。

Lifecycle 先固定，不做条件字段：

```text
item 在 actor equipment container 内 = grant declared abilities
item 离开 actor equipment container = revoke abilities granted by that item
```

V1 不加 `grant_when` / `remove_when`；如果未来出现“背包内也生效 / 战斗开始才生效 / 套装激活”等规则，再扩 lifecycle policy。

`source: equipment` 的用途：

- replay / DevAgent / debug attribution 能区分 innate passive、buff passive、item-granted passive。
- Break / passive disable policy 在 V1 不按 `source = equipment` 单独分支；装备授予出来的是 passive，就走 passive 通用规则。
- 后续 item/stat source policy 有稳定入口，不需要从 config_id 命名反推来源。

Runtime 仍需要记录具体 item 来源：

```text
item_id -> [
  {
    actor_id,
    ability_instance_id,
    ability_config_id,
    source = equipment,
    item_config_id
  }
]
```

撤销时必须按 `ability_instance_id` revoke，不按 `ability_config_id` 粗暴 revoke，避免误删 actor 自带或其他装备 grant 的同 config ability。

装备 item 自身不需要 ability id / instance id。replay / DevAgent / revoke attribution 使用 `item_id` + grant 出来的 `ability_instance_id`；不要为了归因把装备提升为 ability-like runtime entity。

callback 不能承担失败回滚：`BaseContainer.on_item_moved_in` / `on_item_added` 是 void callback，`ItemSystem.move_item` 一旦进入 callback 阶段就已经是业务成功路径。因此装备进入 equipment container 前必须完成 grant 预校验：

```text
ItemSystem.move_item
  -> HexItemDomain.can_move_item / HexActorEquipmentContainer.can_add_item
  -> if target is equipment container:
       item config.granted_abilities 必须全部能解析为 AbilityConfig
       任一 ability_config_id 无法解析 = reject move
  -> container callbacks
```

同步落点不新增 InventoryKit hook，直接复用 container 既有 callback：

```text
ItemSystem.move_item
  -> target HexActorEquipmentContainer.on_item_moved_in / on_item_added
  -> read prevalidated item config.granted_abilities
  -> GameWorld.get_actor(owner_actor_id).ability_set.grant_ability(...)

ItemSystem.move_item / destroy_item / unregister_container
  -> source HexActorEquipmentContainer.on_item_moved_out / on_item_removed
  -> revoke ability_instance_id recorded for that item_id
```

- `HexActorEquipmentContainer` 负责装备槽位、equipable 校验，以及装备 item 对 owner actor 的 Ability grant/revoke 同步。
- `HexActorEquipmentContainer` 需要持有运行时映射 `item_id -> granted ability_instance_id[]`，用于精确 revoke。
- `HexActorEquipmentContainer` 创建时默认只保存 `owner_actor_id`。不要保存 `Actor` / `AbilitySet` / `game_state_provider` 引用；grant/revoke 时通过 `GameWorld.get_actor(owner_actor_id)` 查询当前 actor，再取 `ability_set`。
- `HexItemDomain.can_move_item` / `HexActorEquipmentContainer.can_add_item` 必须把 equipment grant 所需的 `AbilityConfig` 解析失败视为 move reject；callback 阶段只执行已验证过的 grant/revoke，不处理半成功补救。
- V1 装备 grant/revoke 默认不需要查询 `SkillPreviewWorldGI`，也不保存 `owner_instance_id`。只有未来装备授予的 ability 需要在 grant 当下触发 `ABILITY_GRANTED_EVENT` / `TriggerConfig.GRANTED_SELF` self-trigger 时，container 才额外保存 `owner_instance_id`，并用 `GameWorld.get_instance_by_id(owner_instance_id)` 取 provider 后传给 `grant_ability(ability, provider)`。不要在 container 内按 `type == "skill_preview_world"` 搜单例，也不要通过 actor 再取 world。
- grant 时创建 `Ability.new(ability_config, owner_actor_id)`；写 runtime attribution 前必须先复制 metadata：`ability.metadata = ability.metadata.duplicate(true)`，再写入 `source = equipment`、`item_id`、`item_config_id`。不要 mutate 共享的 `AbilityConfig.metadata`。
- `HexPlayerInventory` 继续只管 player bag 与 actor equipment container lifecycle；不维护第二份 Ability 权威状态。

示例：

```text
Morbid Mask
装备后 grant VampiricTraining passive。
VampiricTraining 给 owner +20% attack_lifesteal_pct。
HexBattleGeneralPassive 在 owner 普攻命中后按 actual_life_damage * 0.2 治疗 owner。
```

边界：

- 如果装备本身没有可被外部系统动态修改的战斗属性，先不提升为独立 `Actor`。
- 如果未来出现“装备也能被 aura 修改属性 / 装备自身有 HP 或 cooldown / 装备可被战斗事件直接命中”，再重新讨论是否 actor 化。
- 装备授予出来的是普通 passive ability；Break 等禁用规则按现有 passive 通用规则处理，不按 `source = equipment` 单独分支。

## Attack Effect Example

讨论目标：证明普攻触发效果不需要改 `Strike` 本体。

Phase G V1 已按“代达罗斯之殇 / Daedalus-like critical strike”落地：

```text
Daedalus Charm
装备后 grant passive_daedalus_critical_strike。
owner 普攻按倍率放大本次普攻伤害；V1 dev scene / scenario 默认 100% chance / 2.25x damage，生产数值可通过 config 下调 chance。
普通技能伤害不触发。
```

这个样例不是“命中后再补一段独立伤害”，也不是给目标施加 buff。它应当进入普攻伤害结算本身：先决定这次普攻是否暴击，再把倍率应用到本次普攻的 attack damage，之后继续走标准 `DamageEvent` / `BasicAttackLandedEvent`。

建议 contract：

- `Strike` 只负责造成普攻伤害并发出攻击命中事件。
- 属性驱动效果由 `HexBattleGeneralPassive` 统一消费。
- critical strike 这种攻击特效由 equipment-granted passive ability 注册 `PreBasicAttackEvent` handler，不通过 `BasicAttackLandedEvent` 后置补伤害，也不挂在通用 `PreDamageEvent` 上。
- on-hit slow / bonus damage 这类后置攻击特效才监听 `BasicAttackLandedEvent`。
- 装备移除只 revoke owner 身上的 equipment-granted passive ability，停止未来触发；已经施加到目标身上的 buff / status 不跟随装备清理，按自身 duration 自然结束。
- 多个攻击特效的叠加、互斥、优先级先不做完整系统；V1 只定义一个效果。
- 如果后续多个攻击特效需要互斥或优先级，再专门设计 `AttackEffectPolicy`。
- “暴击规则来源”指能让一次普攻暴击的某个 ability/effect instance，例如装备授予的 Daedalus passive。它不是新 runtime object，只是讨论多个 passive / buff / 装备同时提供暴击规则时的策略边界。
- 多个暴击规则来源的叠加先不做完整 Dota 规则；V1 只保证单一 equipment-granted Daedalus passive，后续再设计“按最高倍率优先 roll / 命中后停止 weaker rule roll”等策略。

实现含义：

- 旧的 `HexBattleDamageAction` 隐藏全局暴击规则已移除；Phase G 改成由 `PreBasicAttackEvent` 决定本次普攻的最终 `attack_damage` 与 `is_critical`。
- `Strike` / basic attack action 在进入 `DamageAction` 前先发 `PreBasicAttackEvent`，再把 final `attack_damage` 和 `is_critical` 传给通用伤害链路。
- Daedalus passive 通过 `PreEventConfig` 过滤 owner outgoing basic attack，roll 成功后返回 `Modification.multiply("attack_damage", 2.25)` 与 `Modification.set_value("is_critical", 1.0)`。
- `DamageEvent.is_critical` 和 `on_critical` callback 继续作为输出合同；普通 active skill、reflected、periodic、Fire Tile、Totem damage 默认不读取这条 equipment crit rule。

## 验收建议

装备属性：

- 装备 grant passive 后，owner 属性生效。
- 装备 revoke 后，owner 属性恢复。
- 装备属性能被 `HexBattleGeneralPassive` 消费，例如 `attack_lifesteal_pct`。

装备攻击特效：

- 装备 grant passive 后，普攻伤害结算能读取 equipment-granted crit rule。
- crit rule 命中时，本次普攻 `DamageEvent.is_critical == true`，伤害按倍率放大。
- 普通 active skill damage 不触发攻击特效。
- reflected / periodic / Fire Tile / Totem passive damage 不触发攻击特效。
- 装备 revoke 后，攻击特效不再触发。
- 装备 revoke 不清理已经施加到目标身上的 buff / status；目标已有状态按自己的 duration 结束。

事件与 replay：

- `BasicAttackLandedEvent` 能追踪 `attacker`、`target`、`source_ability_id`、`actual_life_damage`。
- critical strike 产生标准 `DamageEvent`，并通过 `is_critical` 暴露结果，不走隐藏状态修改。
- 后置攻击特效产生标准 buff / damage / stage cue event，不走隐藏状态修改。

## V2+ 路线图 / 未来扩展记录

本节只记录 Phase G V1 之外的扩展方向，类似 `shield-system.md` 里的 Ward 后续路线。除非某项被后续 goal 明确选中，否则不要把这些策略塞进 Daedalus V1。

### 🟠 P1 — Daedalus V1 后的自然补强

- [ ] **后置 on-hit 样例**：新增一个监听 `BasicAttackLandedEvent` 的装备 passive，用于验证“命中后上 buff / 后置追加标准 damage / stage cue event”的路径。Daedalus 不覆盖这类路径，因为它在 `PreBasicAttackEvent` 阶段改本次普攻伤害。
- [ ] **DevAgent / replay 可观测字段**：在 SkillPreview 验收里能看到 `PreBasicAttackEvent` 修改记录、最终 `DamageEvent.is_critical`、以及 `BasicAttackLandedEvent` 的来源 ability 信息。

### 🟡 P2 — 多攻击特效策略

- [ ] **多个暴击规则来源叠加策略**：当同一 actor 同时拥有多个能让普攻暴击的 ability/effect instance 时，再设计规则。候选包括“只允许一个来源”“按 priority 选最高优先级”“按最高倍率先 roll，命中后停止低优先级 roll”。Phase G 不实现。
- [ ] **后置攻击特效互斥 / 优先级**：如果多个 `BasicAttackLandedEvent` listener 不能同时生效，再设计 `AttackEffectPolicy`。不要提前把互斥规则塞进 item config 或 passive config。
- [ ] **`PreBasicAttackEvent` 字段扩展**：只有出现真实需求时才补 `damage_type`、`can_crit`、`guaranteed_crit`、`proc_group` 等字段。Phase G 的最小字段只服务 Daedalus。
- [ ] **触发顺序审计**：如果未来有“暴击前触发 / 暴击后触发 / 护盾后触发”的装备效果，必须补完整流程图和 scenario，明确它位于 `PreBasicAttackEvent`、`DamageAction` 内部、还是 `BasicAttackLandedEvent` 之后。

### 🔵 P3 — 长期演化

- [ ] **上提到 LGF 框架层**：只有当多个 example 都需要“普攻前事件 + 普攻命中事件 + 攻击特效策略”这套能力时，才考虑把接口上提到 framework。Phase G 仍保持 hex-atb-battle 项目层事件。
- [ ] **完整装备战斗实体化**：当装备自身有 HP / cooldown / aura-modified stats / 可被战斗事件命中时，再讨论把装备提升为 Actor 或 actor-like runtime entity。当前装备只是 item + granted passive。

## 设计决策记录

### Q: 为什么不用 `PreDamageEvent` 做 Daedalus？

**A:** `PreDamageEvent` 是 `DamageAction` 内部的通用伤害修改点，会覆盖 active skill、DOT、反伤、Fire Tile、Totem 等所有伤害。Daedalus 是“普攻本身的暴击规则”，应在进入 `DamageAction` 前通过 `PreBasicAttackEvent` 改本次普攻参数，再让通用伤害链路正常执行。

### Q: 为什么不新增独立 `CriticalResolver`？

**A:** 项目已有 `PreEventConfig` / `EventProcessor` / `Modification`，Daedalus 可以作为 equipment-granted passive 注册 `PreBasicAttackEvent` handler。新增 resolver 会形成旁路系统，未来 buff / 装备 / 职业 passive 的顺序和禁用规则反而更难统一。

### Q: “暴击规则来源”是什么？

**A:** 它只是讨论用语，指能让一次普攻暴击的某个 ability/effect instance，例如装备授予的 Daedalus passive。它不是新 runtime object。Phase G V1 只保证单一 equipment-granted Daedalus passive；多个来源的叠加策略留到 P2。

## Resolved Decisions

- 事件迁移已全量收口到 `BasicAttackLandedEvent`；不把旧事件名作为新接口继续传播。
- Daedalus V1 使用 `chance = 1.0` 的确定性配置做 scenario / dev scene 验收，避免暴击概率造成 flaky；后续生产数值可通过 config 下调 chance。
