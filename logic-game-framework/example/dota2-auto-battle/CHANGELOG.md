# Changelog — dota2-auto-battle

Keep a Changelog 格式。本 example 的变更入口；架构推理长文见 `docs/design-notes/`。

## [Unreleased] — 2026-05-18 M1: Minimal Visible Lane Battle Vertical Slice

从纯文档骨架推进到可运行 + F6 可视的最小 ARAM 单中路自动战斗垂直切片。

### Added

- **Core**：`Dota2WorldGameplayInstance`、`Dota2AutoBattleProcedure`（单线程固定
  30Hz tick，7 步固定相位：cooldown/duration → cleanup → targeting → controller
  decision → movement+ability advance → controller result → death cleanup+出帧），
  `Dota2LogicFrame`（只读快照帧），`core/events/dota2_battle_events.gd`（canonical
  事件词汇，logic-view-contract.md 为准）。Procedure 用独立方法 `advance_tick(dt_ms)
  -> Dota2LogicFrame`（**不**覆写基类 `tick_once() -> void`，签名不兼容；设计文档
  里的 `tick_once(LOGIC_DT_MS)` 即指此）。
- **Logic**：`Dota2BattleActor`（基类，`get_attribute_set()` 公共视图）/
  `Dota2UnitActor`（强类型 `attribute_set`）；`Dota2UnitController` /
  `Dota2LaneCreepController`（march/aggro/chase/attack 显式状态机）/
  `Dota2DecisionResult` / `Dota2Intent` / `Dota2IntentStepResult` /
  `Dota2IntentStatus`，持久 `current_intent` + `next_decision_tick`，决策不每 tick
  跑（aggro 复扫每 5 tick + `spawn_index % 3` 错峰，AttackTarget latch 不抖）；
  `Dota2BasicAttackAbility`（首版即 LGF Ability + 最小 Timeline：attack point=
  TimelineTags.HIT@250ms / END@400ms）+ `Dota2DamageAction` + `Dota2AttackStartedAction`
  + `Dota2AttackCooldown`（cooldown 走 Ability condition+cost，非 controller
  ad-hoc）；`Dota2UnitTypeConfig`（lane melee/ranged）+ `Dota2LaneConfig`（ARAM
  中路 + 队伍常量 + 波次）；`Dota2WaveSpawner` / `Dota2TargetingSystem`；
  `Dota2MovementAdapter`（intent → sim-nav `dota2-rts-pathfinding-lab` 移动原语，
  controller/ability 永不直接动 pathfinding/motion 内部）。
- **Frontend**：`frontend/scene/dota2_lane_battle.tscn` + 场景脚本内私有 logic
  clock block（accumulator + `MAX_LOGIC_STEPS_PER_RENDER_FRAME=2` 有限 catch-up，
  catch-up/debt-drop 帧 `Log.warning` 含 real_delta/accumulator_before/steps/
  dropped_debt/tick_index 遥测）；live world view + HP 条 + 攻击/死亡视觉反馈 +
  lane camera + 富 debug 面板（tick/catch-up、actor id/team/type、HP、intent
  kind/status/target/next_decision、movement state/block、attack state、recent
  events）。**不**建独立 `Dota2SimulationDriver` 类。
- **Tests**：`tests/battle/smoke_lane_wave_engage.tscn`（两波 spawn→march(sim-nav)
  →aggro→attack(Ability)→damage→death，`SMOKE_TEST_RESULT` + 退出码）；
  `tests/frontend/smoke_frontend_main.tscn`（场景加载 + view/clock/debug 断言）；
  `tests/test_groups.json` namespace `dota2autobattle` 组 `smoke` + `regression`
  (required)，`./tools/run_tests.ps1 dota2autobattle/smoke` 可用。

### Technical Debt（待迁出，显式记录）

- **共享 AttributeSet generator 耦合**：M1 走 route 3 —— DOTA2 前缀定义加进共享
  `addons/logic-game-framework/example/attributes/attributes_config.gd` 并产出到
  共享 `example/attributes/generated/`（`dota2_battle_actor_attribute_set.gd` /
  `dota2_unit_attribute_set.gd`）。这把 hex/rts/dota2 三个 example 通过一份 config +
  一个生成目录耦合在一起，是已知设计债。长期目标 = example-local
  `example/dota2-auto-battle/logic/attributes/{attributes_config.gd,generated/}`。
  债务不变量：DOTA2 前缀；**未改**任何 hex/rts 生成名或语义；**未迁移**现有 hex
  生成文件。详见 `logic/attributes/README.md` 与 `docs/design-notes/actor-attributes.md`。

### Notes

- DOTA2 战斗 / 移动策略只在本 example 层，LGF core 与 `sim-nav-map` core 零改动。
- 项目约定：UI/场景改动需编辑器 F6 人工确认；headless `smoke_frontend_main`
  是其可自动化代理（场景加载 + logic clock 推进 + view/debug 断言），已绿。
