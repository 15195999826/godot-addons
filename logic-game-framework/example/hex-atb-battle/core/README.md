# Hex ATB Battle Core

## 目录用途

六边形 ATB 战斗系统的**共享数据层**——只放跨 logic / frontend 的纯数据定义:

- **共享事件**:`events/battle_events.gd` — 强类型事件定义(11 个 `extends GameEvent.Base` 的战斗事件 + DamageType 枚举),frontend 的订阅契约。

World / Procedure 两个 hex 特化类(`hex_world_gameplay_instance.gd` / `hex_battle_procedure.gd`)自 2026-07(线 3 轮 A)起物理归位 `../logic/`——它们的方法签名依赖 logic 层类型(`CharacterActor` / `BattleAbilitySet` / `HexBattleSkillMetaKeys`),按「单向依赖 frontend → logic → core」应属 logic 层;本目录不再承载任何引用上层类型的代码,旧「阶段 5 把 Actor 下沉 core 消除倒挂」路线随之作废(下沉会把职业 config / 技能 / 装备整条链拖进 core)。

设计背景见 `addons/logic-game-framework/docs/README.md`(World owns Battle + 响应式前端 节)。

## 三层架构

```
hex-atb-battle/frontend   表演层(Node3D / 动画 / UI)
        ↓ 依赖 logic 与 core(只读订阅 event / signal)
hex-atb-battle/logic      逻辑层(WorldGI / Procedure / 技能 / AI 策略 / Actor 子类)
        ↓ 只依赖共享事件
hex-atb-battle/core       共享数据层(本目录) ← 强类型事件
        ↓
LGF core / stdlib         框架层
```

## 目录清单

- `events/` — 强类型事件定义 (BattleEvents)

## 设计原则

- **本目录只放纯数据定义**:事件 class 只依赖 LGF core 的 `GameEvent.Base`,不引用 hex logic / frontend 的任何类型。新增内容前先问「它引用上层类型吗」——引用则归 `../logic/`。
- **World 持久,Procedure 短命**(实现在 `../logic/`):world 贯穿一整局游戏,procedure 只在单场战斗内存在,结束即 GC。
- **Signal 只由显式 mutation 触发**:`add_actor` / `remove_actor` / `configure_grid` 等 API emit signal,供非战斗期 frontend 订阅 view lifecycle。
