# Equipment Attack Effects Next Stage

> 下一阶段目标。本文承接装备系统接入 + 装备法球 / 攻击特效讨论，不纳入当前 `GeneralPassive + Cone AoE` 批次。
> 前置依赖：当前批次需要先稳定 `AttackLandedEvent`、`HexBattleGeneralPassive`、普攻吸血属性，以及普攻/普通技能的触发边界。

## Scope

下一阶段只验证“装备如何给角色提供攻击触发效果”，不先做完整装备系统大重构。

目标：

- 装备可以给 owner grant passive ability。
- 装备可以提供属性，例如 `attack_lifesteal_pct`。
- 装备可以提供 on-hit / orb / attack effect。
- 装备移除后，相关属性和监听效果随 ability 生命周期撤销。

明确不做：

- 不把装备提升为 `Actor`，除非后续出现装备可被战斗事件直接命中、装备自身有 HP / cooldown / aura-modified stats 等需求。
- 不在第一个样例里实现完整 Dota-like orb stacking policy。
- 不修改 `Strike` 本体去硬编码具体装备效果。

## Baseline From Current Batch

当前批次应先提供这些基础能力：

```text
Strike Ability
  -> DamageAction
  -> DamageEvent(actual_life_damage, ...)
  -> AttackLandedEvent(attacker, target, source_ability_id, actual_life_damage, damage_event payload)
```

消费者边界：

- 属性驱动效果由 `HexBattleGeneralPassive` 消费，例如 `attack_lifesteal_pct`。
- 装备 on-hit / 法球效果由装备 grant 的 passive ability 消费。
- 普通技能伤害继续只依赖 `DamageEvent`，不触发普攻装备效果。

## Equipment Integration

建议 V1：

- 装备作为 actor 持有的数据项或 container item，不直接成为 battle actor。
- 装备 grant 被动 ability 给 owner。
- 被动 ability 负责：
  - 修改属性，例如 `attack_lifesteal_pct`。
  - 或注册/响应攻击命中事件，例如 on-hit slow、bonus damage。
- 移除装备时 revoke 对应 ability，属性和监听效果随 ability 生命周期撤销。

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
- 装备提供的 passive 是否会被 Break 禁用，需要单独定义 item/stat source policy。

## Orb / Attack Effect Example

讨论目标：证明普攻触发效果不需要改 `Strike` 本体。

建议 V1 只做一个清晰样例：

```text
Frost Orb
普攻命中敌人后，给目标施加 short slow / action lock / atk debuff 之一。
只由 AttackLandedEvent 触发。
普通技能伤害不触发。
```

建议 contract：

- `Strike` 只负责造成普攻伤害并发出攻击命中事件。
- 属性驱动效果由 `HexBattleGeneralPassive` 统一消费。
- 法球效果由 equipment-granted passive ability 监听 `AttackLandedEvent`。
- 多个攻击特效的叠加、互斥、优先级先不做完整系统；V1 只定义一个效果。
- 如果后续需要 Dota-like orb stacking，再专门设计 `AttackEffectPolicy` 或 `OrbPriority`。

## 验收建议

装备属性：

- 装备 grant passive 后，owner 属性生效。
- 装备 revoke 后，owner 属性恢复。
- 装备属性能被 `HexBattleGeneralPassive` 消费，例如 `attack_lifesteal_pct`。

装备法球：

- 装备 grant passive 后，普攻命中触发法球效果。
- 普通 active skill damage 不触发法球效果。
- reflected / periodic / Fire Tile / Totem passive damage 不触发法球效果。
- 装备 revoke 后，法球效果消失。

事件与 replay：

- `AttackLandedEvent` 能追踪 `attacker`、`target`、`source_ability_id`、`actual_life_damage`。
- 法球效果产生标准 buff / damage / stage cue event，不走隐藏状态修改。

## Open Questions

- 装备提供的属性来源是否会被 Break 禁用，还是需要 item/stat source policy？
- 法球/攻击特效是否允许多个同时触发，还是 V1 只保证一个样例？
- 多个法球如果互斥，优先级写在装备、passive ability，还是单独 `AttackEffectPolicy`？
- 装备本身是否需要 ability id / instance id，用于 replay attribution？
- 装备移除时，已施加在目标身上的 buff 是否跟随装备 revoke，还是按 buff 自身 duration 继续存在？
