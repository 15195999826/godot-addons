# Changelog — dota2-auto-battle

Keep a Changelog 格式。本 example 的变更入口；架构契约见 `README.md`，框架级变更见 `../../CHANGELOG.md`。

- **Added** / **Changed** / **Fixed** / **Removed** / **Deprecated**

新变更追加到 `[Unreleased]`。

---

## [Unreleased]

_（暂无）_

---

## [Baseline] — 2026-05-31

文档 baseline 重置。此前逐阶段记录（M1 vertical slice 各步）已归档为快照——完整轨迹见 git 历史与框架 CHANGELOG。当前能力快照：

- **M1 vertical slice 已落地**：ARAM 单中路实时自动战斗（30 Hz 定长 tick）。
- **core/**：`Dota2WorldGameplayInstance` / `Dota2AutoBattleProcedure`（fixed tick）/ `Dota2LogicFrame` / 共享 `dota2_battle_events.gd`。
- **logic/**：`Dota2BattleActor` + `Dota2UnitActor`、controller-intent 模型（`Dota2UnitController` / `Dota2LaneCreepController` / `Dota2Intent` 等）、`Dota2BasicAttackAbility` + cooldown、`Dota2DamageAction`、`Dota2TargetSelectors`、`Dota2WaveSpawner` / `Dota2TargetingSystem`、`Dota2MovementAdapter`、AttributeSet family（route-3 共享生成，临时债）。
- **frontend/**：`scene/dota2_lane_battle.tscn`（F6）+ 私有 logic clock + debug 面板（只读）。
- **tests/**：`battle/smoke_lane_wave_engage` + `frontend/smoke_frontend_main`，namespace `dota2autobattle`。

> 架构契约（Tick / Controller-Intent / Actor-属性 / Logic-View / LGF Skill / M1 / 未来规划）全部见 `README.md`。
