# Hex ATB Battle Core

## 目录用途

六边形 ATB 战斗系统的 **核心层 (world + procedure + events)**。配合 LGF core 的 `WorldGameplayInstance` / `BattleProcedure` 两条抽象,给 hex-atb 提供:

- **World 特化**:`hex_world_gameplay_instance.gd` — 接 UGridMap autoload 做 grid backend,actor/格子清理,`can_use_skill_on` 等 hex 查询。
- **Procedure 特化**:`hex_battle_procedure.gd` — ATB 累积、AI 决策、投射物事件广播、胜负判定、MAX_TICKS 安全上限。
- **共享事件**:`events/battle_events.gd` — 强类型事件定义,frontend 订阅点。

设计背景见 `addons/logic-game-framework/docs/design-notes/2026-04-19-world-as-single-instance.md`。

## 三层架构(2026-04-20 调整)

```
hex-atb-battle-frontend   表演层(Node3D / 动画 / UI)
        ↓ 只读订阅 event / signal
hex-atb-battle            逻辑扩展层(技能 / AI 策略 / Actor 子类)
        ↓ 类型依赖 (CharacterActor / BattleAbilitySet / HexBattleSkillMetaKeys)
hex-atb-battle-core       核心层(本目录) ← WorldGI / Procedure / 事件
        ↓
LGF core / stdlib         框架层
```

**注意**:阶段 1 改造后,`hex-atb-battle-core` 的 World / Procedure 类引用了上层 `hex-atb-battle` 的 `CharacterActor` / `BattleAbilitySet` / `HexBattleSkillMetaKeys`,严格的"下层不依赖上层"层向在 GDScript 全局 class_name 体系下未真正违反编译(GDScript 全局解析),但在概念上有倒挂。阶段 5 若把 Actor 类型也下沉到 core 层可消除此倒挂;短期不动。

## 目录清单

- `events/` — 强类型事件定义 (BattleEvents)
- `hex_world_gameplay_instance.gd` — hex 特化 World instance
- `hex_battle_procedure.gd` — hex ATB 战斗过程

## 设计原则

- **World 持久,Procedure 短命**:world 贯穿一整局游戏,procedure 只在单场战斗内存在,结束即 GC。
- **状态直写**:procedure tick 期间直接改 world 里 actor 的属性/tag,不经 signal;战斗期视觉由 `BattleAnimator` 消费 event_timeline 回放。
- **Signal 只由显式 mutation 触发**:`add_actor` / `remove_actor` / `configure_grid` 等 API emit signal,供非战斗期 frontend 订阅 view lifecycle。
