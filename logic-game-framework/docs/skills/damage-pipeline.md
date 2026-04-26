# Damage Pipeline — 项目层伤害流程

## 状态

🔵 **已落地** — 当前实现的 hex-atb-battle 伤害管线事实记录。

> 本文档**描述既有流程**，是流程参考而非系统设计。新增"插入式步骤"（格挡 / 招架 / 转伤 / 分摊...）时回来更新这里 + 加一行清单。

---

## 🎯 定位

**`HexBattleDamageUtils.apply_damage` 是项目层唯一的伤害集中点**。所有产生伤害的 Action（`DamageAction` / `ReflectDamageAction` / 中毒 / 反伤 / 未来的 AoE...）都走它，不要绕开。

源码：[`addons/.../hex-atb-battle/utils/hex_battle_damage_utils.gd`](../../addons/logic-game-framework/example/hex-atb-battle/utils/hex_battle_damage_utils.gd)

---

## 🔄 完整流程

```
原始伤害产生（攻击 / 中毒 / 反伤 / ...）
  ↓
① EventProcessor.process_pre_event
       易伤 / 减伤 / 免疫等 SET / ADD / MULTIPLY 修正
  ↓
② 命中特有修正
       暴击倍率等（由发起 Action 自身负责，不在 apply_damage 内）
  ↓
③ HexBattleShieldResolver.resolve(actor, modified, damage_type)
       按规则消耗护盾，提交 ShieldComponent.current 变更
       返回 (life_damage, shield_absorbed, consumption_records[])
       【纯结算，不 push 事件、不扣 hp、不触发回调】
  ↓
④ 把吸收信息写回 damage_event
       shield_absorbed / actual_life_damage / consumption_records
  ↓
⑤ event_collector.push(damage_event)
       ← 回放从此处看到 damage 事件
  ↓
⑥ actor.attribute_set.set_hp_base(hp - actual_life_damage)
       ← 真正扣血，按穿透护盾后的值
  ↓
⑦ 对每个 broken=true 的消耗记录：
       push shield_broken event
       call ShieldComponent.on_break(record, ctx, battle)   ← 爆炸 / 治疗 / ...
       ability.expire(EXPIRE_REASON_BROKEN)
  ↓
⑧ 死亡检测
       check_death() → push death_event
                     → process_post_event(death_event)
                     → remove_actor
  ↓
⑨ EventProcessor.process_post_event(damage_event)
       反伤 / 吸血 / 受击 buff 在这里触发，过滤条件读 actual_life_damage
```

---

## 🔒 关键顺序约束

| 约束 | 为什么 | 违反后果 |
|---|---|---|
| **③ 护盾结算** 在 **⑥ 扣血** 之前 | 没有"吸收"语义可言 | 护盾形同虚设 |
| **⑦ on_break 回调** 在 **⑧ remove_actor** 之前 | 爆炸类盾（Aphotic）回调时需要 owner actor 上下文 | 拿不到位置 / 状态 / ability，回调静默失败 |
| **⑨ post_event** 在 **⑧ remove_actor** 之后 | 死亡相关 post 反应（如"队友死亡触发狂暴"）需要尸体已不在战场 | 死亡判定干扰 post handler |
| **③ resolver 不产生副作用事件** | resolver 是纯结算，事件序由 apply_damage 控制 | 事件顺序错乱、回放分叉 |
| **⑦ on_break 只能 push 新事件，不能回写本次伤害** | 因果链应是"伤害 → 护盾破 → 新事件"，不是"护盾破回头改本次伤害" | 亚巴顿盾爆炸反向放大打破它的那次伤害 |

---

## 🏷️ damage event schema 字段语义

```gdscript
class DamageEvent extends GameEvent.Base:
    target_actor_id: String
    source_actor_id: String
    damage_type: DamageType            # PHYSICAL / MAGICAL / PURE
    is_critical: bool
    is_reflected: bool

    damage: float                      # ① 修正后但未扣护盾 的总伤害
    shield_absorbed: float             # ② 本次被护盾吸收的总量
    actual_life_damage: float          # ③ 真正打到生命的伤害 = damage - shield_absorbed
    consumption_records: Array         # ④ 消耗的护盾记录（按消耗顺序）
```

**「我该读哪个字段？」对照表**：

| 消费场景 | 读什么 | 备注 |
|---|---|---|
| HP 实际下降值 | `actual_life_damage` | 与 `hp` 下降值一致 |
| 反伤 / 吸血触发条件 | `actual_life_damage > 0` | 默认不响应纯吸收 |
| 反伤 / 吸血计算基数 | `actual_life_damage`（默认）or `damage`（特殊） | thorn 用前者 |
| 飘字 / 血条 / 闪白 | `actual_life_damage` | 额外飘 "护盾 -shield_absorbed" |
| "本次攻击造成多少修正后伤害"统计 | `damage` | 含被吸收部分 |
| "本次攻击让护盾吸了多少" | `shield_absorbed` | |
| 哪些护盾消耗了 / 破了 | `consumption_records` | 每条带 `broken: bool` |

⚠️ **`damage` 字段语义在 V1 改过**：原来是"实际造成的伤害"，现在是"修正后但未扣护盾的总伤害"。所有读 damage event 的消费者都要意识到 HP 实际损失是 `actual_life_damage`。新增同类消费者时同步对齐。

---

## 🧩 当前的"插入式步骤"清单

按在流程中出现的位置排列：

| # | 步骤 | 实现位置 | 是否可叠加多个 |
|---|---|---|---|
| ① | pre_event 修正 | `EventProcessor` 注册的 PreHandler（易伤 / 减伤 / 免疫 buff） | ✅ 多个并行，按 `SET → ADD → MULTIPLY` 收敛 |
| ② | 暴击 | 各 DamageAction 自身 | 每次伤害最多一次暴击判定 |
| ③ | 护盾结算 | `HexBattleShieldResolver.resolve` | ✅ 多盾按 priority + LIFO + id 排序消耗 |
| ⑦ | on_break 回调 | `ShieldComponent.on_break: Callable` | ✅ 每个破裂盾各自触发一次 |
| ⑨ | post_event 反应 | `EventProcessor` 注册的 PostHandler（反伤 / 吸血 / 受击 buff） | ✅ 多个并行，独立 push 新事件 |

---

## 🪜 未来扩展点

新增"伤害流程中间步骤"（格挡 / 招架 / 转伤 / 分摊 / 护盾外的额外护甲层...）时，复用护盾的模式：

1. 写一个 **纯结算 Resolver**（无副作用事件，只改自身状态）
2. 在 `apply_damage` 流程合适位置插入调用
3. 给 damage_event 加新字段（如 `blocked_amount` / `parry_records`）
4. 更新本文档的流程图 + 字段表 + 插入式步骤清单

**何时上提到 LGF 框架层**：当格挡 / 招架 / 转伤 / 分摊都重复同一个"`apply_damage` 中间一步 + 消耗记录"模式时，证明这是通用能力，再上提。届时考虑给 `MutableEvent` 加 `metadata: Dictionary` 通道。在那之前不预先抽象。

---

## 📚 相关文档

- [shield-system.md](shield-system.md) — 护盾系统的设计、消耗顺序、叠加策略
- LGF 事件系统：[`addons/logic-game-framework/core/events/`](../../addons/logic-game-framework/core/events/)
- LGF 架构总览：[`addons/logic-game-framework/CLAUDE.md`](../../addons/logic-game-framework/CLAUDE.md)
- 伤害事件定义：[`addons/.../hex-atb-battle-core/events/battle_events.gd`](../../addons/logic-game-framework/example/hex-atb-battle-core/events/battle_events.gd)
