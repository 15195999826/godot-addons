# Changelog

本文件记录 Logic Game Framework 的重要变更。格式参考 [Keep a Changelog](https://keepachangelog.com/)。

- **Added** — 新增能力
- **Changed** — 行为或 API 变化
- **Fixed** — Bug 修复
- **Removed** — 移除
- **Deprecated** — 即将废弃

对于有架构推理的重大变更，在 `docs/design-notes/` 下会有对应长文，行末以链接引用。

---

## [Unreleased] — 2026-04-27 SkillPreview 多 actor 时间轴模型

### Changed

- **`SkillPreviewWorldGI.queue_preview`** 改签名: 从 `(caster_id, ability, target_id, passives)` 改为 `(actor_setups: Array[Dictionary], allow_empty_track: bool = false)`。每个 setup 携带 `{actor_id, passives: Array[AbilityConfig], track: Array[Keyframe]}`,`Keyframe = {time_ms, ability_config, target_id}`。旧调用全部需要迁移 (改造前 baseline = caster 单条 t=0 keyframe)。
- **`SkillPreviewProcedure._init`** 改签名: 接收 `actor_setups` 替换原 `caster_id / ability_config / target_id / passives`。`start()` 末尾立即 drain `time_ms <= 0` 的 keyframe (保留改造前"第 0 帧 activate"行为, event `logicTime=0.0`)。`tick_once` 在 `world.base_tick` 后按 `world.get_logic_time()` 调度后续 keyframe。结束判定加 `_pending_keyframes.is_empty()`。
- **`SkillPreviewBattle.run_with_actions`** (主仓 helper): `actions[i]` 增加可选 `time_ms: int` 字段 (默认 0)。`t<=0` 在 grant 阶段立即 activate (与改造前一致),`t>0` 进 pending 队列,每帧 `battle.tick` 后 drain 已到时项。
- **`SkillPreview` 工具 UI**: 删除全局 `Skill` / `Target` tab。Actors detail panel 内每个 actor 自己挂 passives + skill track (keyframe 列表 `[time_ms] [skill] [target_mode + index/q/r]`)。同 actor 同 `time_ms` 在 UI 阻止 (push 到下一个 100 边界)。

### Removed

- 旧 preset 文件 (`01_strike_basic.json` ~ `09_surge_self_buff.json`) 全删,替换为 v2 schema 的 3 个示例 (`01_caster_strike` / `02_combo_caster_3hit` / `03_thorns_reflect`)。preset JSON 加 `version: 2`,旧版被 `_is_preset_v2` 拒绝加载。

### 验证

| 场景 | 改造前 | 改造后 |
|---|---|---|
| caster t=0 Strike → enemy_0 (smoke_skill_preview_reactive) | PASS | PASS |
| caster t=0 + enemy_0 t=500 双 Strike (smoke_skill_preview_timeline) | N/A | PASS — caster damage @ frame 3, enemy damage @ frame 8, 间隔 5 帧 |

---

## [Unreleased] — 2026-04-27 录像: BattleRecorder 单 buffer 重构 (根治时序错位)

`BattleRecorder.pending_events` 字段删除。所有录像事件 (Action 显式 push 的 damage/heal/StacksChanged + Actor lifecycle callback push 的 AbilityGranted/AttributeChanged/ActorSpawned/Destroyed) 统一进 `GameWorld.event_collector`。`record_frame(frame, events)` 简化为只写入参数 events,不再合并第二容器。

→ [docs/design-notes/2026-04-27-recorder-single-buffer.md](docs/design-notes/2026-04-27-recorder-single-buffer.md)

### Bug

之前用两个并行容器: Action push 的事件进 `EventCollector._events`,callback 的事件进 `BattleRecorder.pending_events`。`record_frame` 合并时按"容器类型"拼接,无论 `[events, pending]` 还是 `[pending, events]` 都构造得出反例 — Action_A 中途 grant ability 触发 callback 这种调用栈穿插的场景下,真实时序是 `[damage1, AbilityGranted, damage2]`,任何固定拼接顺序都会错位。

之前 commit `dc3dcac` 颠倒为 `[pending, events]` 是症状疗法,只在 Surge (grant + first tick same frame) 这种"callback 全在 push 之前"的简单场景下 PASS,无法处理穿插。

### Changed

- **`RecordingContext.push_event`**: `_recorder.pending_events.append(event)` → `GameWorld.event_collector.push(event)`。`is_recording` guard 保留,防 `stop_recording` 与 unsubscribe 之间的 callback 残响灌脏事件。
- **`BattleRecorder.register_actor` / `unregister_actor`**: ActorSpawned/Destroyed event 改 push 进 `GameWorld.event_collector`,不再持有自己的 buffer。
- **`BattleRecorder.record_frame(frame, events)`**: 删除 `all_events.append_array(pending_events)` 合并逻辑,`pending_events.clear()` 也一并删除,`frame_data.events = events` 直接写入。
- **`BattleRecorder` 顶部 docstring**: 重写,去掉「两个来源 / 帧间缓冲区」叙述。

### Removed

- **`BattleRecorder.pending_events`** 字段。
- **`start_recording` / `start_recording_events_only`** 中的 `pending_events.clear()` 调用。

### 关键设计决策

- **为什么是 EventCollector 而非反过来**: EventCollector 是 Action 层的硬依赖 (永远存在),BattleRecorder 是可选的 session 抽象 (录像才创建)。让事件流统一往必选的 collector 走,recorder 退化为「session 元数据 + subscription 生命周期 + 写 timeline」职责。
- **`is_recording` guard 保留**: 录像 callback 可能在 `stop_recording` 与异步 unsubscribe 之间触发一次,此时 `event_collector` 仍在被复用 (下场战斗或主流程消费),不能让残响污染。
- **`dc3dcac` 不 revert**: 留作历史。新 commit message 标注 "supersedes dc3dcac"。

### 验证

| 测试 | 结果 |
|---|---|
| `addons/logic-game-framework/tests/run_tests.tscn` | 59/59 ✅ |
| `tests/smoke_skill_scenarios.tscn` (含 SurgeScenario `grant_index < first_stacks_index` 断言) | PASS |
| `tests/smoke_buff_ui.tscn` / `smoke_buff_pipeline.tscn` / `smoke_surge_unit_view.tscn` | PASS |
| `tests/smoke_frontend_main.tscn` | PASS |

---

## [Unreleased] — 2026-04-26 表演层: 血条迁移到 state 路径(贯彻 event/state 边界)

补完 `2026-04-26-presentation-event-vs-state.md` 边界 — 该 design-note 已把"hp 条高度"明确划入 State,但代码侧 `damage` / `heal` 一直走 `FrontendUpdateHPAction(from, to, duration)` 进 `ActionScheduler` 并行 lerp(Event 路径)。本轮把血条彻底迁到 state:visual_hp 每 tick 朝 target_hp 收敛,delta 只是把 target 拉低。

→ [docs/design-notes/2026-04-26-presentation-event-vs-state.md](docs/design-notes/2026-04-26-presentation-event-vs-state.md) 末尾「血条迁移到 state」补章节

### Bug

用户报告:多次伤害,血条不是从当前进度继续变化(同帧多伤害 → 多个 UpdateHPAction 并行写 visual_hp 互相覆盖 → 视觉跳变)。

### Added

- **`FrontendApplyHPDeltaAction`** (`example/hex-atb-battle-frontend/actions/apply_hp_delta_action.gd`): 瞬时指令(duration=0,delay 结束当帧 progress=1 立即完成),apply 时 `actor.target_hp = clamp(target_hp + delta, 0, max)`。
- **`FrontendActorRenderState.target_hp`** 字段:damage / heal apply 累在这里;visual_hp 由 RenderWorld 异步追赶。
- **`FrontendRenderWorld.tick_hp_lerp(delta_ms)`**: 每 tick 调一次,指数衰减 `1 - exp(-rate * dt)` 让 visual_hp 朝 target_hp 收敛。`FrontendBattleDirector._tick` 末尾 wire。
- **`FrontendAnimationConfig.hp_lerp_rate`** = 8.0(单位 1/秒,默认约 125ms 收敛 63%)。

### Changed

- **`FrontendVisualAction.ActionType`**: `UPDATE_HP` → `APPLY_HP_DELTA`。
- **`damage_visualizer.gd`**: 不再读 `context.get_actor_hp` snapshot,改生成 `FrontendApplyHPDeltaAction(target_id, -actual_life_damage, hp_bar_delay)`。`damage_hp_bar_delay` 仍然有用 — 飘字 / 闪白先飞,扣血后跟,节奏感保留。
- **`heal_visualizer.gd`**: 同上,`FrontendApplyHPDeltaAction(target_id, +heal_amount)`。
- **`render_world.gd`**: 删 `_apply_update_hp_action`,加 `_apply_apply_hp_delta_action` + `tick_hp_lerp`。`set_actor_hp` / `set_actor_dead` / `_apply_death_action` 同步 snap target_hp。`_initialize_actor_from_init_data` 初始化 target_hp = visual_hp。
- **`battle_director.gd::_tick`**: 末尾 `_world.tick_hp_lerp(delta_ms)` — 与 ActionScheduler 解耦,即使无 action 活跃也每帧推进 lerp。

### Removed

- **`FrontendUpdateHPAction`** (`actions/update_hp_action.gd` + `.uid`) 物理删除 — duration-driven 持续 lerp 是 Event 路径,血条作为 State 不再适用。
- **`FrontendAnimationConfig.damage_hp_bar_duration`** / **`heal_hp_bar_duration`**: state 路径下"动画时长"概念由 `hp_lerp_rate` 替代。

### 关键设计决策

- **delta-action 而非 set-target-action**: 候选「`SetTargetHPAction(actor_id, target_hp)`」被否决 — visualizer 是 stateless,从 context 读 visual_hp snapshot 再算 target,会重新引入「同帧多 event 拿到同一起点」的 bug。delta 表达「相对变化」,与 logic 层 damage event 的 `actual_life_damage` 字段语义对齐,RenderWorld 累加自然连续。
- **hp_lerp_rate 配合指数衰减**(`1 - exp(-rate * dt)`)而非线性 lerp:目标变更时不需要重置进度,任何时刻都从「当前 visual_hp」朝「target_hp」收敛,主观感知与原 300ms 线性 lerp 接近,但天然处理多次叠加。
- **方法论**:本文档主体只迁了 death 一个 case,bug 暴露后才补血条 — 边界立完贯彻不彻底是边界没立够明确的信号(见 design-note 第 8 条总结)。

### 验证

| 测试 | 结果 |
|---|---|
| `addons/logic-game-framework/tests/run_tests.tscn` | 59/59 ✅ |
| `tests/smoke_frontend_main.tscn` | PASS |
| `tests/smoke_world_view.tscn` | PASS |
| `tests/smoke_skill_preview_reactive.tscn` | PASS |
| `tests/smoke_skill_scenarios.tscn` | 12/12 ✅ |

---

## [Unreleased] — 2026-04-26 文档归属:`docs/skills/` 从主仓迁回 LGF submodule

主仓 `docs/skills/`(`damage-pipeline.md` / `shield-system.md` / `skill-implementation-progress.md` / `README.md`)4 份文档全部 `git mv` 到 `addons/logic-game-framework/docs/skills/`。原因:这些文档描述的实现代码全部在 LGF submodule 内(`hex-atb-battle-core/apply_damage` / `Shield*` 组件 / `example/hex-atb-battle/skills/` 进度卡),文档归属应跟随实现仓库以保证版本一致性 — 主仓 bump submodule pointer 时,代码 + 文档同步快进,避免「shield V1 文档 + shield V2 代码」错版风险。

主仓 `docs/` 整个目录清空(plan-docs/ 不在范围)。

---

## [Unreleased] — 2026-04-26 阶段 5 完工: 拆 HexBattle thin 门面, 引入 HexDemoWorldGameplayInstance

「世界 owns 战斗」重构计划阶段 5 落地: 物理删除 `HexBattle` thin 兼容门面, 把它原本封装的 6v6 demo 战斗启动行为(默认 grid + 6 character 硬编码 + inspire buff + 队伍随机放置 + start_battle + replay save)搬到新建的 `HexDemoWorldGameplayInstance`。每个独立场景拥有自己的 `HexWorldGameplayInstance` 子类(demo / skill-preview / 将来真游戏战斗), 框架类 `HexWorldGameplayInstance` 保持通用不被 demo hardcode 污染。
→ [design-notes/2026-04-26-phase-5-hex-demo-world-gi.md](docs/design-notes/2026-04-26-phase-5-hex-demo-world-gi.md)

### Added

- **`HexDemoWorldGameplayInstance`** (`example/hex-atb-battle/hex_demo_world_gameplay_instance.gd`): 新建。`extends HexWorldGameplayInstance`, 收编原 `HexBattle` 全部内容 — `start(config)` / `_create_battle_procedure` / `_on_battle_finished` / `_save_replay` / `_build_default_grid_config` / `_create_team_actor` / `_place_team_randomly` / `_apply_inspire_buff_to_all` / `_print_battle_info` / `tick(dt)` / `get_all_actors` / `get_alive_actors` / `get_replay_data` / `get_log_dir`。id 前缀 `IdGenerator.generate("demo")`(actor id 形如 `demo_001:hero_001`), `type = "hex_demo"`。
- **`HexWorldGameplayInstance.get_alive_actors()`** (`example/hex-atb-battle-core/hex_world_gameplay_instance.gd`): 上抬。返回 `Array[CharacterActor]`, 与 `get_alive_actor_ids()` 并列, 解耦 AI strategy 对 thin facade 的依赖。

### Changed

- **AI strategy 类型签名**(`example/hex-atb-battle/ai/ai_strategy.gd` + 3 个具体策略): `battle: HexBattle` → `battle: HexWorldGameplayInstance` 共 7 处。配合 `get_alive_actors` 上抬, AI 不再 IS-A 偶合具体子类。
- **`scripts/SimulationManager.gd`**: `HexBattle.new()` → `HexDemoWorldGameplayInstance.new()`, cast 类型同步。Web 桥接 `godot_run_battle` 跑的是 demo 路径。
- **`scripts/SkillPreviewBattle.gd`**: `_PreviewInstance` 从 `extends HexBattle` 改为 `extends HexWorldGameplayInstance`。自管 `left_team` / `right_team` / `recorder` 字段(原本借父类), 自带 `get_all_actors()` 走 staging 拼接。id 前缀 `preview` (actor id 形如 `preview_001:caster`)。
- **`tests/smoke_world_view.gd`**: `var _world: HexBattle` + `HexBattle.new()` → `HexDemoWorldGameplayInstance`。
- **`example/hex-atb-battle/main.gd`** / **`example/hex-atb-battle-frontend/main.gd`**: 同步切到 `HexDemoWorldGameplayInstance`。`HexBattle.MAX_TICKS` → `HexBattleProcedure.MAX_TICKS`(唯一来源)。
- **`example/hex-atb-battle/utils/hex_battle_game_state_utils.gd`** / **`example/hex-atb-battle-core/hex_battle_procedure.gd`** / **`core/events/handler_context.gd`**: 注释里的 `HexBattle` 字面量更新为 `HexWorldGameplayInstance` / `HexDemoWorldGameplayInstance` 按语义。
- **`CLAUDE.md`** mermaid 图: `HexBattle` 节点改名 `HexDemo`(对应新类), 关系箭头不变。

### Removed

- **`example/hex-atb-battle/hex_battle.gd`** 物理删除(原 268 行)。`HexBattle.MAX_TICKS` / `HexBattle.recorder` 字段在 PR-1 已先去冗余, 物理删时调用方零阻塞。
- **`HexBattle` class_name** 和 `class_name HexBattle` 全局符号一并消失。所有调用方已切到 `HexDemoWorldGameplayInstance` 或 `HexWorldGameplayInstance`。

### 设计决策(本轮关键点)

- **不污染框架类**: 候选「demo 行为搬到 `HexWorldGameplayInstance`」被否决 — `HexWorldGameplayInstance` 是 framework 层通用 hex world, 写死「priest/warrior/archer 6 角色」「9x9 默认地图」「inspire buff」等 demo 行为会破坏「框架/实例」分层。
- **不冗余 inline 到 3 个 main**: 候选「demo 启动逻辑 inline 到 frontend/main + addon/main + SimulationManager」被否决 — 同套行为出现 3 份, 未来加角色/调整地图要同步 3 处。
- **选定: 与 `SkillPreviewWorldGI` 范式对齐**: 每个独立场景拥有自己的 `HexWorldGameplayInstance` 子类。3 个 demo main 共享一个 `HexDemoWorldGameplayInstance`(单一来源), skill-preview 走自己的 `SkillPreviewWorldGI`(已存在), 将来真游戏战斗加 `HexGameplayInstance` 之类。框架/场景边界清晰。

### 验证

| 测试 | 结果 |
|---|---|
| `addons/logic-game-framework/tests/run_tests.tscn` | 59/59 ✅ |
| `tests/smoke_frontend_main.tscn` | PASS |
| `tests/smoke_world_view.tscn` | PASS (views 6→5) |
| `tests/smoke_skill_preview_reactive.tscn` | PASS (3 场连续 + reset) |
| `tests/smoke_skill_scenarios.tscn` | 12/12 ✅ |

### 跨阶段成果

至此「世界 owns 战斗」整个重构计划阶段 0–5 全部落地(阶段 4 作废)。`GameplayInstance` 抽象现在有 3 个 ergonomic 实现:
- `HexWorldGameplayInstance`(框架基类, 通用 hex world)
- `HexDemoWorldGameplayInstance`(6v6 demo 场景, 服务 3 个 demo entry)
- `SkillPreviewWorldGI`(skill-preview 编辑器场景, 含 reset / queue_preview)

`HexBattle` thin 门面消亡, actor id 前缀根据场景自然区分: `demo_*` / `preview_*` / `skill_preview_*`。

---

## [Unreleased] — 2026-04-26 表演层 Event vs State 边界

用户实测 bug:单位被普攻打死后亡语紧接命中,死亡动画并行播了两次。第一/二轮 patch(`Tween.is_running()` guard / `_death_played` flag) 都只解决死亡这一个 case。跟 Codex 讨论后定下表演层根边界:**State 是可覆盖事实(snapshot 同步无害),Event 是一次性命令(必须 transition-only)**。死亡动画从 snapshot 推断改成 event 触发。
→ [design-notes/2026-04-26-presentation-event-vs-state.md](docs/design-notes/2026-04-26-presentation-event-vs-state.md)

### Changed

- **`RenderWorld.actor_died`** (`example/hex-atb-battle-frontend/core/render_world.gd`) emit 语义收紧为 transition-only:新增私有 helper `_set_actor_alive(actor, alive)` 收口所有 `is_alive` 写入,只在 `was_alive && not alive` 那帧 emit 一次。`_apply_death_action`(progress >= 1.0)/ `set_actor_dead` 直接 emit 删除,`set_actor_hp`(hp ≤ 0)走同一 helper。重复设 false / 设回 true 不再触发。
- **`FrontendBattleAnimator`** wire `_director.actor_died` → `_unit_views[id].play_death()`(event-driven),不再依赖 `actor_state_changed` snapshot 推断死亡。`reset()` 内遍历 view 调 `revive()` — Reset 是 playback session control,不走 Director event。
- **`FrontendUnitView`** 拆 API:`update_state` 删死亡 / 复活分支,只管 hp / flash / tint state sync;新增公共方法 `play_death()`(once 策略,内部 `_death_played` flag 挡重入)和 `revive()`(清 flag + visible/scale 恢复)。删私有 `_play_death_animation` / `_revive_visual_state`。

### 触发策略约定(写进 design note,长期遵守)

每个一次性动画 view 公共方法显式声明触发策略:
- **once**:已播过就忽略(死亡 / 复活)
- **retrigger**:已在播也强制 kill 旧 tween 从头播(未来:受击抖 / 闪白 / 暴击大字)
- **queue**:排队顺序播完(暂未需要)

Animator 一律 wire event signal,**不关心策略**;策略写在 view 方法体内。

### 未来扩展(本期不做)

- `actor_revived(id)`:战斗内复活技能落地时再加,同样 transition-only
- `actor_damaged(id, amount, source_id, is_critical)`:受击表现需要时落地,view 端 retrigger 策略

### 验证

| 测试 | 结果 |
|---|---|
| `addons/logic-game-framework/tests/run_tests.tscn` | 59/59 ✅ |
| `tests/smoke_skill_preview_reactive.tscn` | PASS(3 场连续 + reset 归 0) |
| `tests/smoke_frontend_main.tscn` | PASS(139 frames, 6 views) |
| `tests/smoke_world_view.tscn` | PASS |
| `tests/smoke_skill_scenarios.tscn` | 12/12 ✅ |

用户场景:F6 main.tscn → 普攻 + 亡语双击致死 → 死亡动画只播一次 ✅;Reset → 死掉的棋子回到初始态 ✅。

---

## [Unreleased] — 2026-04-26 A 层"录像播放"老路径下线

阶段 2/3 引入响应式 `WorldView + BattleAnimator` 后, destructive `FrontendBattleReplayScene.load_replay` 老路径只剩 `main.tscn` 一个生产调用方 + `tests/smoke_frontend_main` 一个 smoke 间接依赖。本轮一次性下线: `main.gd` 切到 `HexBattle (WorldGameplayInstance) + WorldView.bind_world + BattleAnimator.play(timeline, view.get_unit_views())` 响应式 wire(参考 skill_preview 同形态), smoke 节点路径同步换, 删 ReplayScene + 3 个孤儿 frontend 测试, ReplayControls 顺手改名 PlaybackControls 对齐命名约定。
→ [design-notes/2026-04-26-playback-old-path-retirement.md](docs/design-notes/2026-04-26-playback-old-path-retirement.md)

### Removed

- **`FrontendBattleReplayScene`** (`example/hex-atb-battle-frontend/scene/battle_replay_scene.gd`): destructive `load_replay(record)` 路径整体下线。视觉入口由 `main.gd` 自己 wire `WorldView + BattleAnimator` 替代。
- **3 个孤儿 frontend 测试** (`tests/frontend/test_replay_flow.gd` / `test_3d_visualization.gd` / `test_compilation.gd`): 不在 `run_tests.gd::TEST_PATHS` 里, 没人跑过, 全部移除。`tests/frontend/` 目录一并清掉。

### Changed

- **`example/hex-atb-battle-frontend/main.gd`**: 完全重写为响应式 wire。流程: 用户按 Start Battle → 创建 `HexBattle` → `WorldView.bind_world(battle)` → `battle.start(config)` 触发 `add_actor` signal → view spawn → tick 跑完战斗 → `battle_finished(timeline)` signal → `animator.play(timeline, view.get_unit_views())`。camera / lighting / WorldEnvironment / player_controller 由 main.gd 自管(从被删的 ReplayScene 搬出来)。
- **`tests/smoke_frontend_main.gd`** (主仓): 节点路径换成 `get_node("WorldView")` / `get_node("BattleAnimator")`。4 条 invariants 保持: `is_ended` / `current_frame == total_frames` / unit view count > 0 / `visual_hp ∈ [0, max_hp]`。
- **`FrontendReplayControls` → `FrontendPlaybackControls`** (`example/hex-atb-battle-frontend/ui/replay_controls.gd` → `ui/playback_controls.gd`): 顺手对齐 Playback 命名约定。功能 / 信号 / 公共方法不变, 仅 class_name + 文件名 + 节点 name。
- **`FrontendBattleAnimator`** API 增补(`example/hex-atb-battle-frontend/battle_animator.gd`): `pause()` / `resume()` / `reset()` / `get_total_frames()` / `get_current_frame()` / `get_actors_snapshot()` / `is_ended()` 全部转发到内部 `_director`; signal `playback_state_changed(is_playing)` / `frame_changed(current, total)` 转发自 director, 供 main.gd UI 同步进度 / 按钮态。

### 外部调用点兼容性

- 录像格式未变化(仍是 ReplayData v2 平铺 `{mapConfig, initialActors, timeline}`)。
- `SimulationManager.gd` 的 Web 桥接 (`godot_run_battle` / `godot_preview_skill`) 不在范围内 — 它们只产出录像 JSON 给 JS 端, Godot 内部不渲染。
- 主仓 `Simulation.tscn` (autoload SimulationManager) 不动。

### 验证

| 测试 | 结果 |
|---|---|
| `addons/logic-game-framework/tests/run_tests.tscn` | 59/59 ✅ |
| `tests/smoke_skill_preview_reactive.tscn` | PASS(3 场连续) |
| `tests/smoke_frontend_main.tscn` | PASS(131 frames / 6 views) |
| `tests/smoke_skill_scenarios.tscn` | 12/12 ✅ |

`main.tscn` F6 编辑器手动验证由用户接手。

### 遗留

- B 层"回放(Replay)"逻辑重算未落地。命名占位 `BattleReplayPlayer` / `BattleReplaySession` 保留, 视未来需求再做。
- AI 目录 `example/hex-atb-battle/ai/*.gd` 5 个文件 `battle: HexBattle` 类型偏窄但 IS-A 兼容当前不报错, 单独一笔做。
- `stdlib/replay/` 目录命名暂未变。它持有 `BattleRecorder + ReplayData + ReplayLogPrinter` 都是录像数据生产/消费侧, 没有"录像播放表演"成分。如果 `Recording` 命名更合适, 留到那时一起做。

---

## [Unreleased] — 2026-04-26 死亡不再 remove_actor(阶段 3 D5 收尾)

阶段 3 遗留的 D5"skill_preview 战斗期死亡角色 view 立刻消失,死亡动画来不及播"问题。回归阶段 0 design note (2026-04-19-world-as-single-instance.md line 247) 原则:**死亡是行为禁止,不是 actor 离开 world**。`damage_utils.apply_damage` 在 hp ≤ 0 时不再调 `world.remove_actor`,改为只清 grid 占用 / 预订;actor 留在 registry 里 `is_dead()=true`,WorldView 不回收 view,后续 `actor_state_changed(is_alive=false)` signal 能找到 view 触发死亡 tween(缩小 + 下沉 + visible=false)。
→ [design-notes/2026-04-26-death-keeps-actor-in-world.md](docs/design-notes/2026-04-26-death-keeps-actor-in-world.md)

### Changed
- `HexBattleDamageUtils.apply_damage`(`example/hex-atb-battle/utils/hex_battle_damage_utils.gd`):死亡分支删除 `battle.remove_actor(target_id)` 调用,新增私有静态方法 `_clear_grid_footprint(battle, dead_actor)` 单独清掉死者的 grid occupant + reservation。语义切分:**死亡 = 行为禁止 + 清格子 + 留 view + 留逻辑实例**;**离开 world = 玩家编辑删除 / 重启战斗 / 投射物完成**。
  
  正交性已查证:`get_alive_actor_ids` / `_check_battle_end` / AI 候选 / `process_post_event` 广播范围全部走 `actor.is_dead()`(基于 `_is_dead` flag, hp 一次性 ≤ 0 翻),不依赖 `world.has_actor()`,留尸体不污染战斗逻辑。`apply_move_action` 的 `grid.move_occupant` 由 `_clear_grid_footprint` 兜底防止活人撞死尸格触发 UNEXPECTED `push_error`。
  
  当前剩余的 `world.remove_actor` 运行时调用点:`stdlib/systems/projectile_system.gd:131`(投射物离场)、`example/skill-preview/skill_preview.gd:315/562`(编辑态删 / 切 class),`SkillPreviewWorldGI.reset()` 走 `_actors.clear()` + emit。四条都是"actor 永久离开 world"正当语义,与"死亡留尸体"原则不冲突。

### 命名约定(本轮对齐)

| 中文 | 英文 | 含义 |
|---|---|---|
| **录像播放**(A 层, 现状) | **Playback** | 表演层视觉播放:`FrontendBattleReplayScene` / `FrontendBattleAnimator` 当前做的事 —— 从录像 dict 读 actor 配置和事件流, spawn 一组视觉 view, 按 frame 推动画 / 飘字 / VFX, **不重建逻辑 actor**。 |
| **回放**(B 层, 未来可能做) | **Replay** | 逻辑层重新跑一遍战斗: 反序列化真 Actor / AbilitySet / AttributeSet, 按 timeline 命令重计算战斗状态, 支持时间轴拖动 / 撤销 / 跳到第 N 帧。**当前不做, 没规划**。 |

英文层借 playback ≠ replay 的语感分层(playback = DVR 预录播放, replay = War3/Dota 类 deterministic 重算)钉死两层。

- 后续文档 / 讨论里出现"录像 / playback"词, **默认指 A 层**; "回放 / replay"词在 B 层落地前**避免使用**, 防止误读。
- 当前代码里的 `BattleRecorder` / `ReplayData` / `FrontendBattleReplayScene` / `FrontendBattleAnimator` / `tests/frontend/test_replay_flow.gd` 等 A 层类**仍叫 Replay***, 重命名留到 A 层老路径整合那一轮工作一并做。
- 未来 B 层入口预定: `BattleReplayPlayer` / `BattleReplaySession`。
- 阶段 0 design note 草拟的"ReplayPlayer hydrate 真 Actor"路径(形态 B)字面像 B 层但实际只是 A 层包装, **该方向作废**。

### 外部调用点兼容性
- 录像格式未变化(仍是 ReplayData v2 平铺 `{mapConfig, initialActors, timeline}`)。
- `FrontendBattleReplayScene` / `BattleAnimator` / `Director.load_replay` 全部未动。
- `main.tscn` / Web 桥接 / scenario runner 路径全部未动。

### 待处理
- A 层老路径整合:`FrontendBattleReplayScene.load_replay` destructive 路径未来一轮独立工作清理, 换成 `WorldView + BattleAnimator` 直接 bind(用户表示"接下来一定会做")。
- 死者 view 期间(0.5s 死亡 tween) 活人 move 到死尸格的视觉穿过感:本期不修, 视觉违和明显时再说。
- AI 走位 / 寻路目前不感知 view 还在(逻辑层 grid 已清),无影响 —— 视觉残留是 view 层的事。

### 验证

| 测试 | 结果 |
|---|---|
| `addons/logic-game-framework/tests/run_tests.tscn` | 59/59 ✅ |
| `tests/smoke_skill_preview_reactive.tscn` | PASS(3 场连续) |
| `tests/smoke_frontend_main.tscn` | PASS |
| `tests/smoke_skill_scenarios.tscn` | 12/12 ✅ |

skill_preview F6 编辑器手动验证(死亡 tween 视觉)由用户接手。

---

## [Unreleased] — 2026-04-20 阶段 3:skill_preview 响应式切换

阶段 1/2 把 core/frontend 拆到 "World 持久 + Procedure 短命 + WorldView/Animator 叠加层" 后, 阶段 3 让 skill_preview 这个编辑器工具吃到这套新架构: 常驻一个 `SkillPreviewWorldGI` + 常驻 `FrontendWorldView` + 常驻 `FrontendBattleAnimator`, 编辑态增删 actor 走 `world.add_actor/remove_actor` 触发 signal → view 响应式刷新(不再 destructive 重建场景)。START 走 `world.queue_preview + start_battle` → 新增的 `SkillPreviewProcedure` 承接 grant+activate+tick-until-done 语义, 战斗结束后 `battle_finished` signal 把 timeline 喂给 Animator 叠加 VFX/飘字/死亡动画。
→ [design-notes/2026-04-20-skill-preview-reactive.md](docs/design-notes/2026-04-20-skill-preview-reactive.md)

### Added
- `SkillPreviewProcedure extends BattleProcedure`(`example/skill-preview/skill_preview_procedure.gd`):skill_preview 特化的战斗过程。不跑 ATB/AI/胜负判定, 只承接"caster 施放指定 ability, tick 到所有技能无 executing instance + 无飞行投射物 + POST_EXECUTION_TICKS 缓冲"这条终止链。`tick_once` 合并 ability tick 与 "executing 探测" 同一循环(省掉一次全量 actor 扫描); `_any_projectile_flying` 单独扫投射物。`_start_recorder` override 走旧版 `start_recording(actors, configs, map_config)` 保留 initial_actors, 供 Animator `ReplayData.BattleRecord.from_dict` 消费。`MAX_TICKS=500 / POST_EXECUTION_TICKS=10` 与旧版一致; passives 构造时 `duplicate()` 防御调方数组外部 mutate。
- `SkillPreviewWorldGI extends HexWorldGameplayInstance`(`example/skill-preview/skill_preview_world.gd`):编辑器常驻 WorldGI。`reset()` 清空 `_actors / _actor_id_2_actor_dic / _systems / grid / _logic_time`, emit `actor_removed` 让 `FrontendWorldView` 响应式回收 unit view。`queue_preview(caster_id, ability_config, target_id, passives)` 预存下一次 start_battle 的 preview 参数(passives `duplicate()` 防御), `_create_battle_procedure` override 消费参数构造 `SkillPreviewProcedure`(消费后清空防止跨场误用, 加 `Log.assert_crash(ability_config != null)` 防 "忘 queue_preview 直接 start_battle" 静默 null)。
- `HexWorldGameplayInstance.broadcast_projectile_events()`(`example/hex-atb-battle-core/hex_world_gameplay_instance.gd`):把 projectile HIT/MISS 事件的 collect+match+process_post_event 下沉为 world 公共 method。`HexBattleProcedure` / `SkillPreviewProcedure` 的 tick_once 都调这一方法, 消除同段逻辑两处内联。
- `tests/smoke_skill_preview_reactive.tscn/gd`(主仓库):连续跑 3 场战斗断言 WorldView/Animator 节点引用复用(直接比较 Node 引用, 不靠 instance_id) + reset 归 0 + battle_finished 产出非空 timeline + animator 跑到 playback_ended。

### Changed
- `skill_preview.gd`(`example/skill-preview/skill_preview.gd`)从 "每次 START 调 `SkillPreviewBattle.run_with_config` destructive 重建临时 instance + `FrontendBattleReplayScene.load_replay`" 切到响应式栈:`_ready` 里 `GameWorld.init()` + 常驻 `SkillPreviewWorldGI` + `FrontendWorldView.bind_world` + `FrontendBattleAnimator`。编辑态的 `_rebuild_editor_preview`(旧)替换为 `_rebuild_world_from_model`(新)走 `world.reset() / configure_grid / add_actor / place_occupant` 的显式 mutation API, `FrontendBattleReplayScene / FrontendBattleDirector / _replay_events_by_frame / _last_logged_frame` 等字段全部删除。相机 / 光照 / 环境从原先委托 replay_scene 改为场景自己搭(`_setup_camera_and_env` 沿袭原参数)。console event log 退化为 `battle_finished` 后从 timeline 一次性 dump(不再按 frame 同步推进, UX 遗留记在 handoff)。
- `HexWorldGameplayInstance.logger: HexBattleLogger = null`(`example/hex-atb-battle-core/hex_world_gameplay_instance.gd`):把原先仅存在于 `HexBattle` 上的 `logger` 字段下沉到父类, 默认 null。动机 —— `damage_utils / heal_action` 用 `if battle.logger != null` 判空访问, 当 `game_state_provider` 是 `SkillPreviewWorldGI` 等 HexBattle 的姊妹子类时触发 `Invalid access to property 'logger'` 报错。下沉后任何 `HexWorldGameplayInstance` 子类都合法共享字段, HexBattle 上原有声明删除以避免 shadowing。
- `HexBattle` 在 `hex_battle.gd` 上的 `var logger: HexBattleLogger = null` 声明移除(下沉到 HexWorldGameplayInstance, 见上), `_on_battle_finished` 里 `logger = _hex_procedure.logger` 语义不变。
- `HexBattleProcedure._broadcast_projectile_events` 下沉并删除本地 method, `tick_once` 改调 `world.broadcast_projectile_events()`; 顺带移除原实现里的 `print("  [投射物] ...")` debug 行(调试 print 不属于框架职责, 要 log 走 HexBattleLogger)。
- 所有 `var battle: HexBattle = ctx.game_state_provider` 的静态类型标注改为 `var battle: HexWorldGameplayInstance = ctx.game_state_provider`:`actions/apply_move_action.gd` / `actions/apply_buff_action.gd` / `actions/damage_action.gd` / `actions/poison_tick_action.gd` / `actions/heal_action.gd` (×2) / `actions/reflect_damage_action.gd` / `actions/start_move_action.gd` / `target_selectors.gd`, 以及 `utils/hex_battle_damage_utils.gd` (×2) / `utils/hex_battle_game_state_utils.gd` (×2)。  
  动机 —— 这些 action 访问的字段(`get_actor / get_alive_actor_ids / grid / remove_actor / get_actors / logger`)阶段 1 已全部下沉到 HexWorldGameplayInstance, 标注成具体子类 HexBattle 是历史残留, 且会让 SkillPreviewWorldGI / 未来其它姊妹子类触发"Trying to assign value of type X to a variable of type hex_battle.gd"。AI 目录(`ai/*.gd` 5 文件)的 `battle: HexBattle` 暂未改 —— SkillPreviewProcedure 不走 AI 路径, 且 HexBattle 跑 HexBattleProcedure 时 AI 签名仍兼容, 改动留给未来"WorldGI 直接驱动 AI"场景。

### Fixed
- `skill_preview.gd._do_rebuild_world_unguarded`:右键加 actor 后 view 永远落在 (0,0)。根因 —— `WorldView._hydrate_from_actor` 在 `actor_added` 信号里一次性读 actor 的 `team / hp / hex_position`, 但 core 层 `actor_position_changed` signal 尚未 emit(本段"外部调用点兼容性"已记录, D5 列为阶段 4 待办), 导致 add 之后再赋值的字段 view 收不到。修法把 `set_team_id / attribute_set.set_*_base / hex_position` 全部前置到 `_world.add_actor(cchar)` 之前, hydrate 时即可读到正确值; `place_occupant` 留在 add 之后(grid 占用登记必须等 actor 入 world)。属于 hydrate 时序兜底, 阶段 4 补 `actor_position_changed` emit 后可改回任意顺序。
- `skill_preview.gd` 编辑态走全量 rebuild 导致"加一个 actor 所有棋子从 (0,0) 移过来"。根因 —— `_add_actor / _remove_actor_at / _move_caster_to`, 以及 actor row 的 q/r/hp/class 修改全部调 `_rebuild_world_from_model` → `_world.reset()` + 整体重建 actor。每次 reset 触发 `actor_removed` × N → WorldView 销毁所有 view → 重 spawn → 新 view 初始 `position = (0,0,0)`, `_process` 内 `position.lerp(_target_position, delta * 15.0)` 平滑插值时视觉上就是"全部从原点滑到目标"。修法把编辑态拆成 5 条增量 mutation 路径: `_add_actor` 走单 `_spawn_one_actor(idx)`; `_remove_actor_at` 走 `_world.remove_actor(actor_id)` (HexWorldGameplayInstance.remove_actor 已自带 grid occupant 清理); 坐标改动走 `_apply_actor_position_change` (`grid.move_occupant` + 手动 `actor_position_changed.emit` 兜底, 因 core 仍未补 emit); hp 改动走 `_apply_actor_hp_change` (`attribute_set.set_*_base` + `view.initialize` re-hydrate); class 切换走 `_apply_actor_class_change` (CharacterActor class 是构造参数 → remove + spawn 同 idx)。引入并行 `_actor_ids: Array[String]` 与 `_actors` 同 idx 对齐, 解决 idx 重编号(删 enemy_2 后 enemy_3 → enemy_2)导致 role_id 反查错位的问题。
- `skill_preview.gd` map spinbox(radius / orientation / hex_size) value_changed 每步触发全量 rebuild, 拖动时抖。加 150ms one_shot debounce Timer, 短促拖动只在停下后 rebuild 一次。
- `skill_preview.gd` 编辑期 reset 路径泛滥, 违反"reset 只用于明确意图的场景重置, 面板/右键全部走 event→update"的原则。清掉 3 处违反原则的 reset 调用 + 把剩余 reset 函数语义收紧:
  - 删 `_on_start_pressed` 战前 `_do_rebuild_world_unguarded` —— 编辑期已经实时 mutation 同步到 world, 战前不需要 commit, 这行的存在反而暴露"UI 模型 / world state 异步两份"的错位认知。
  - 删 `_on_passive_toggled` 内 `if pressed: _rebuild_world_from_model()` —— passive 只在 `_collect_selected_passives()` 喂给 queue_preview, 编辑期 world 不感知 passive, 此处 rebuild 纯属无效调用(历史残留)。
  - 改 map spinbox debounce timeout 接到新增的 `_apply_grid_change`(走 `_world.configure_grid` emit `grid_configured` -> view 重渲网格 + 遍历 `_actor_ids` 重新 `place_occupant` + 用同坐标 emit `actor_position_changed` 让 view 按新 hex_size 重算 world_position 平滑过渡)。注意 UGridMap.configure 创建新 GridMapModel 旧 occupant 全丢, 必须重新 place; radius 改小后 actor coord 不在新网格内时跳过 place 但仍 emit position_changed (coord_to_world 是纯数学不依赖 has_tile)。
  - `_rebuild_world_from_model` / `_do_rebuild_world_unguarded` 改名 `_reset_world_to_model` / `_reset_world_to_model_unguarded`, 函数注释里明确列出"合法调用点只有 3 处", 编辑期面板 / 右键 / spinbox 全部走 event→update 增量 mutation。
- `skill_preview.gd._on_playback_ended` 不再自动 reset world —— 战斗回放结束后保留 world 当前状态(死者已 remove / 受伤者血条 < max), 让用户能观察战斗结果或重播。状态恢复改由用户主动按新增的 RESET 按钮触发(`_on_reset_pressed`: `_reset_world_to_model_unguarded` + 清 console log + 启用 START)。START 按钮在回放结束后保持 disabled, 强制走 RESET → START 流程, 避免基于残破状态(死者已 remove / hp 已损耗)再次战斗导致语义混乱。`skill_preview.tscn` 在 StartButton 后追加 `ResetButton` 节点; `_style_reset_button` 给次要操作样式(浅米底 + 深咖字, 阵仗低于 START 主 CTA)。合法 reset 调用点更新为:_ready 初始化 / _on_reset_pressed / _on_preset_load_selected。
- `skill_preview.gd` HexPopupMenu 显示时用户右键另一个 hex 没反应,要再点一次。根因 —— `PopupMenu` 是 modal Window, popup visible 时 `InputEventMouseButton` 被 popup 自身截获(主场景 `_input` 收不到), 同时这次右键也不触发 popup 的 click-outside-close (右键不算 click-outside 触发器), 所以 popup 既不关闭也不让主场景重弹。修法:连 `Window.window_input` signal (popup 自身收到的事件转发回我们) → 检测 `MOUSE_BUTTON_RIGHT pressed` → 关旧 popup + raycast 当前鼠标位置 + `call_deferred("_show_hex_popup")` 在新 hex 重弹(deferred 让 hide 真正完成再 show, 避免同帧 race)。同 hex 右键只关闭不重弹。左键 / ESC / 点菜单项的关闭路径不走这条, 由 popup 原生关闭流程处理。曾经尝试过 `popup_hide` signal + deferred reopen 方案,但 `popup_hide` 在点菜单项时也触发 → 误判成需要重弹 → 用户反馈"创建 actor 后冒出新菜单",已撤回。

### 外部调用点兼容性
- `SkillPreviewBattle`(`scripts/SkillPreviewBattle.gd`)未动 —— `tests/skill_scenarios/` scenario runner 继续走 headless `run_with_config/actions` 路径(`GameWorld.init → 临时 _PreviewInstance(HexBattle) → tick → GameWorld.destroy`), 未切到 SkillPreviewWorldGI。动机:scenario runner 的"每场独立 GameWorld 生命周期"断言简单且已稳; skill_preview UI 需要常驻 world 才能做到"无缝展开战斗", 二者的需求不同, 一条路径优化给一种场景更克制。
- `main.tscn` / `Simulation.tscn` / Web 桥接继续走 `HexBattle` 门面 + `FrontendBattleReplayScene.load_replay(record)` 老路径, 未动。
- `BattleRecord` 录像格式未变化(阶段 4 落地 v3), `FrontendBattleReplayScene` 未动。

### 待处理(下一阶段)
- 阶段 4:`BattleRecord` v3(split `world_snapshot` + `event_timeline`) + `ReplayPlayer`(临时 WorldGI + WorldView)。录像路径切到 ReplayPlayer 后 skill_preview 战斗期死亡动画问题可根治 —— 届时 skill_preview 可以 bind 到 ReplayPlayer 构造的临时 world 看完整死亡动画, 或继续走本阶段常驻 world(死者 view 响应式消失, 死亡动画 skip)的方案。
- 阶段 5:`main.tscn` / `Simulation.tscn` / Web 桥接切到 WorldGI 承载。
- AI 目录 `battle: HexBattle` 类型标注收束(等 "WorldGI 直接驱动 AI" 需求落地再改, 当前 `HexBattleProcedure._decide_action` 传 `_world_instance: HexWorldGameplayInstance` 进去,AI 静态类型虽偏窄但传入的 HexBattle 实例 IS-A 兼容,不报错)。
- skill_preview 战斗期 console event log 同步推进(现在 `battle_finished` 后一次性 dump, 不追帧)。需要 `FrontendBattleAnimator` 转发 director `frame_changed` signal 才能做同步, 阶段 3 不加以免扩 scope。

### 验证

| 测试 | 结果 |
|---|---|
| `addons/logic-game-framework/tests/run_tests.tscn` | 59/59 ✅ |
| `tests/smoke_frontend_main.tscn` | PASS(Logic battle completed in 156 ticks) |
| `tests/smoke_skill_scenarios.tscn` | 12/12 ✅ (含 Shield + Thorn 系统并入) |
| `tests/smoke_world_view.tscn` | PASS(views 1 → 0) |
| `tests/smoke_skill_preview_reactive.tscn` | PASS(3 场连续, view/animator 实例复用 + reset 归 0) |

编辑器手动验证(skill_preview UI 的"无缝展开战斗"视觉)由用户接手, 不在 headless 覆盖面内。

### 阶段 3 收尾确认 (2026-04-26)

用户 F6 编辑器实测通过, 以下行为全部符合预期:
- 增删 actor / 拖 q/r/hp / class 切换 → 只动目标棋子的 view, 已有棋子不抖
- 拖 map radius / orientation / hex_size → 拖动期不抖, 松手后 150ms 平滑过渡(actor 跟新 hex_size 重算位置, 不是从 (0,0) 滑回)
- 战斗 START → 回放 → 状态保留 → 用户主动按 RESET 才回战前态
- popup visible 时右键另一个 hex → 旧 popup 关闭, 新 hex 重弹 popup; 点菜单项 / ESC / 左键关闭都不会误触发"反弹"
- 触发"reset 全部从 (0,0) 滑回"的入口已收敛到 3 处明确意图的合法路径(`_ready` / `_on_reset_pressed` / `_on_preset_load_selected`)

---

## [Unreleased] — 2026-04-20 阶段 2:Frontend 订阅器(WorldView + BattleAnimator)

阶段 1 把 core 拆成"World 持久 + Procedure 短命"两层后,frontend 仍停留在"被动消费录像 dict"范式。阶段 2 新增响应式订阅层:`WorldView` 订阅 WorldGI 的显式 mutation signal 维护 unit view 生命周期(非战斗期);`BattleAnimator` 复用 `FrontendBattleDirector` 消费 event_timeline,在 WorldView 提供的已有 view 上叠加 VFX / 飘字 / 死亡动画,不拥有 view。录像格式 / `FrontendBattleReplayScene` / `main.tscn` / scenario runner / Web 桥接全部未动 —— 阶段 2 纯加 API,现有路径继续走 HexBattle 门面 + replay scene。  
→ [design-notes/2026-04-20-world-view.md](docs/design-notes/2026-04-20-world-view.md)

### Added
- `FrontendWorldView extends Node3D`(`example/hex-atb-battle-frontend/world_view.gd`):`bind_world(world)` hydrate 当前 actor + 订阅 `actor_added` / `actor_removed` / `actor_position_changed` / `grid_configured` / `grid_cell_changed` signal。view 生命周期完全由 signal 驱动(reactive projection);没有 destructive `load_replay` 等价物。内部挂 `UnitsRoot` + `GridMapRenderer3D`;上层通过 `get_unit_views()` / `get_unit_view(id)` / `get_unit_view_count()` 抓取 view 引用。只为 `CharacterActor` 建 view,ProjectileActor 等非可视单位由 BattleAnimator 自行管 VFX 节点。
- `FrontendBattleAnimator extends Node3D`(`example/hex-atb-battle-frontend/battle_animator.gd`):`play(record_dict, unit_views)` 复用 `FrontendBattleDirector` 的 timeline 解码 / `FrontendActionScheduler` / `FrontendVisualizerRegistry`,把 Director 的状态变更 signal(`actor_state_changed` / `floating_text_created` / `attack_vfx_*` / `projectile_*`)转发到外部传入的 unit view 字典(`actor_died` 由 Director 经 `actor_state_changed.is_alive=false` 统一推入,不需单独转发);自己只承载 VFX / 投射物 / 飘字节点(挂在内部 `EffectsRoot`)。`playback_started` / `playback_ended` signal + `set_speed()` / `stop()` / `is_playing()` 兼容现有测试加速需求。
- `tests/smoke_world_view.tscn/gd`:阶段 2 主验证 —— bind 前 0 view → HexBattle.start 触发 signal 把 view 补齐 → WorldGI.tick 推进战斗 → BattleAnimator 消费 timeline 到 `playback_ended` → 显式 `world.remove_actor` 让剩余 view 响应式减少。

### Deprecated
- `FrontendBattleReplayScene`(`example/hex-atb-battle-frontend/scene/battle_replay_scene.gd`)收缩为"录像回放专用"路径 —— 仍由 `main.tscn` / Web 桥接使用,但不再是新战斗场景的视觉入口。阶段 4 录像格式 v3 落地后考虑用 `ReplayPlayer`(临时 WorldGI + WorldView)替换,彻底去掉 destructive `load_replay`。

### 外部调用点兼容性
- `main.tscn` / `SkillPreviewBattle` / scenario runner / Web 桥接均未调整,继续走 `HexBattle` 门面 + `FrontendBattleReplayScene.load_replay(record)` 老路径。WorldView / BattleAnimator 是"可选接入",需要响应式更新的场景才用。
- WorldGI 的 `actor_position_changed` / `grid_cell_changed` signal 已由 WorldView 订阅但 core 层尚未 emit 任何调用点 —— 预留钩子,后续移动动画 / 地形破坏技能按需补 emit。

### 验证

| 测试 | 结果 |
|---|---|
| `addons/logic-game-framework/tests/run_tests.tscn` | 59/59 ✅ |
| `tests/smoke_frontend_main.tscn` | PASS |
| `tests/smoke_skill_scenarios.tscn` | 9/9 ✅ |
| `tests/smoke_world_view.tscn` | PASS(bind + signal spawn + timeline 动画 + remove_actor) |

---

## [Unreleased] — 2026-04-20 阶段 1：WorldGameplayInstance + BattleProcedure 核心拆分

"世界 owns 战斗"架构第一步。把 HexBattle 身上的 instance(actor registry / grid / systems)与 procedure(ATB loop / teams / recorder)两条职责拆开,为后续 frontend 响应式 view + skill_preview 无缝展开战斗 + replay 格式 v3 奠基。阶段 1 只改 core / hex-atb-battle-core 层,调用端(`SkillPreviewBattle` / `main.tscn` / `scenes/Simulation.tscn` / scenario runner)通过 `HexBattle` 兼容门面不动一行。  
→ [design-notes/2026-04-19-world-as-single-instance.md](docs/design-notes/2026-04-19-world-as-single-instance.md)

### Added
- `WorldGameplayInstance extends GameplayInstance`(`core/entity/world_gameplay_instance.gd`):显式 mutation API `add_actor` / `remove_actor` / `configure_grid`,每个 emit 对应 signal(`actor_added` / `actor_removed` / `actor_position_changed` / `grid_configured` / `grid_cell_changed` / `battle_finished`);`start_battle(participants: Array[Actor])` 入口配合工厂钩子 `_create_battle_procedure`,`tick(dt)` 战斗优先,分帧吞吐由常数 `BATTLE_TICKS_PER_WORLD_FRAME`(默认 INT_MAX,一帧跑完)控制。Signal 只由显式 mutation 触发,战斗期间 actor 属性/tag 直接改内存,不发 signal(view 由 BattleAnimator 消费 event_timeline 回放)。
- `BattleProcedure extends RefCounted`(`core/entity/battle_procedure.gd`):抽象骨架。Public API `start` / `tick_once` / `should_end` / `finish`(被 WorldGI.tick 调用,不加下划线)。生命周期管理 in_combat tag(`_mark_in_combat` 虚钩子,基类 no-op,子类按 tag 容器实现)+ recorder(`_start_recorder` 虚钩子,默认走 events-only,子类可 override 回退旧版 `start_recording(actors,...)`)。
- `BattleRecorder.start_recording_events_only()`(`stdlib/replay/battle_recorder.gd`):仅记录 event timeline,不带 initial_actors / map_config。为新架构下"world 已常驻持有状态,录像只记过程事件"服务;旧版 `start_recording()` 保留未动,向后兼容。
- `HexBattleProcedure extends BattleProcedure`(`example/hex-atb-battle-core/hex_battle_procedure.gd`):hex 特化。承接原 `HexBattle.tick` 里的 ATB 累积、AI 决策、技能施放、投射物事件广播、MAX_TICKS 安全上限、胜负判定(某方全灭 → `mark_finished` + `_result` 设置为 `left_win / right_win / timeout`)。`_start_recorder` override 走旧版 `start_recording(actors, configs, map_config)` 路径,保留 initial_actors snapshot,阶段 1 不破坏 FrontendBattleReplayScene。
- `HexWorldGameplayInstance extends WorldGameplayInstance`(`example/hex-atb-battle-core/hex_world_gameplay_instance.gd`):actor registry + grid(UGridMap autoload 后端)+ system 管理。`configure_grid` 转发到 `UGridMap.configure`,保持 `grid` 字段指向 `UGridMap.model`。`remove_actor` 覆盖清理格子 occupant / reservation。`get_actor` 类型收窄 CharacterActor。提供 `get_alive_actor_ids` / `get_ability_set_for_actor` / `can_use_skill_on`。

### Changed
- `HexBattle extends HexWorldGameplayInstance`(`example/hex-atb-battle/hex_battle.gd`)从具体 instance 转为 thin 兼容门面。`start(config)` 走新架构:`configure_grid()` + 6 个 `add_actor()` + 队伍装备 + buff + timeline 注册 + `start_battle(...)` 创建 HexBattleProcedure。`tick(dt)` 委托父类 `WorldGI.tick`,由其驱动 procedure;每 tick 从 procedure 镜像 `tick_count`。战斗结束通过 `battle_finished` signal 回 `_on_battle_finished`,保留字段 `left_team / right_team / recorder / logger / _ended / _final_replay_data / MAX_TICKS`(= 10000)兼容旧调用。  
  原 HexBattle 上的 ATB loop / projectile 广播 / AI 决策 / `_check_battle_end` / `_start_actor_action` / `_create_action_use_event` 等全部迁至 HexBattleProcedure,不再在 HexBattle 里保留。

### 外部调用点兼容性
- `HexBattle.new().start(config)` / `battle.tick(dt)` / `battle.tick_count` / `battle.left_team` / `battle.right_team` / `battle.recorder` / `battle.logger` / `battle.get_replay_data()` / `battle.get_log_dir()` / `HexBattle.MAX_TICKS` / `battle.can_use_skill_on(...)` 全部保留;`main.tscn` / `SimulationManager` / `SkillPreviewBattle` / scenario runner / Web 桥接均未调整。
- 录像格式暂未变化(仍走旧版 `start_recording(actors, ...)` 保留 initial_actors),FrontendBattleReplayScene 不受影响。格式 v3(split `world_snapshot` + `event_timeline`)在阶段 4 再落地。

### 待处理(下一阶段)
- 阶段 2:`WorldView` 订阅 WorldGI signal 维护 unit view,`BattleAnimator` 消费 event_timeline 叠加飘字/特效。
- 阶段 3:`skill_preview` 切换到常驻 `SkillPreviewWorldGI` + `world.start_battle`,验证无缝展开战斗。
- 阶段 4:`BattleRecord` v3 格式落地 + `ReplayPlayer`(临时 WorldGI + WorldView)。
- 阶段 5:正式游戏场景(`main.tscn` / `Simulation.tscn` / Web 桥)切换到 WorldGI 承载。

### 验证

| 测试 | 结果 |
|---|---|
| `addons/logic-game-framework/tests/run_tests.tscn` | 59/59 ✅ |
| `tests/smoke_frontend_main.tscn` | PASS(Logic battle completed in 139 ticks) |
| `tests/smoke_skill_scenarios.tscn` | 9/9 ✅ (CrushingBlow / DeathrattleAoe / Fireball / HolyHeal / Poison / PreciseShot / Strike / SwiftStrike / Thorn) |

---

## [Unreleased] — 2026-04-19 后续：Ability 叠层一级化 + grant 事件化

围绕 Poison（DOT）技能实装,对外暴露两个 framework 缺口并一次性补齐:
(1) 叠层数据之前挂在 `StackComponent` 里,action 必须遍历 components 找它;
(2) `grant_ability` 只跑 local callback,buff 无法"挂上就自动 tick"。

### Added
- `Ability.stacks / max_stacks / overflow_policy` 提升为一级属性,配套 API `get_stacks() / is_stacks_full() / add_stacks(count) / remove_stacks(count) / set_stacks(count)`。溢出策略常量 `Ability.OVERFLOW_CAP / OVERFLOW_REFRESH / OVERFLOW_REJECT`。REFRESH 策略在叠层同时调用本 ability 上 `TimeDurationComponent.refresh()`(之前的 TODO 随一级化变成 3 行实现)。归 0 不自动 expire —— 清理由调用方决定(stacks 做纯计数器,与项目约定一致)。
- `AbilityConfig` 加 `initial_stacks / max_stacks / overflow_policy` 配置字段,`AbilityConfigBuilder.stacks(initial, max_val, policy)` 一级 API。不调默认 1/1/CAP(不可叠加 ability 调 add_stacks 一直 CAP 在 1,语义安全)。
- `AbilitySet.grant_ability(ability, game_state_provider = null)` 新增第二参数。传入后,grant 内部构造 `ABILITY_GRANTED_EVENT` 并同步调 `receive_event(event_dict, provider)` 广播给本 actor 的所有 ability。限本人 ability_set 广播,不走 event_processor 全局 post —— 跨 actor 监听由业务层自行决定。未传 provider(默认)则仅跑 local callback,保持与旧调用点兼容。
- `TriggerConfig.GRANTED_SELF` 静态 factory:匹配 `ABILITY_GRANTED_EVENT` 且 `event.actor_id == owner_id` 且 `event.ability.id == ctx.ability.id`(严格 instance id,同 actor 上多个同 config 实例不互激活)。典型用途:buff 挂 `ActivateInstanceConfig + GRANTED_SELF + loop timeline` 实现"挂上就自动 tick"(DOT/HOT/持续光环)。

### Removed
- `stdlib/components/stack_component.gd` 删除(对应 `stacks / max_stacks / overflow_policy` 已上移到 Ability 一级)。StackComponent 原本"组件化"但实际没有 hook/callback 也没有组件间交互接口,只是"一堆方法 + 状态"伪装成 component。外部 action 必须遍历 components 按 type 字符串找它才能读写层数,违反 component 封装。上移后:
  - Poison DOT 的 tick action 直接 `ctx.ability_ref.get_ability().get_stacks()`,零胶水
  - `Ability` 成为 stacks 的 facade(类比 `attribute_set.atk` / `actor.faction`),AbilityConfig 一级 API `.stacks(...)` 声明可叠加 ability

### Changed
- `Ability.serialize()` 增加 `stacks / maxStacks / overflowPolicy` 字段(replay/snapshot 携带层数信息)。

### 外部调用点同步
本次 addon 改动对现有业务代码**零调用点变更**:grant_ability 新参数默认 null;stacks 字段在所有未调 `.stacks(...)` 的 config 下默认 1/1/CAP,add/remove 对它们是 no-op。

### Added(上轮累积,保留)
- `Actor.is_pre_event_responsive() -> bool`（默认 true）虚函数。项目层子类覆盖以表达"此刻不响应 PreEvent 分发"的状态（如死亡、沉默、眩晕）。框架在 `PreEventComponent` handler 触发时查询，返回 false 则 handler 自动降级为 `pass_intent()`。  
  → [design-notes/2026-04-19-ability-lifecycle-decoupling.md](docs/design-notes/2026-04-19-ability-lifecycle-decoupling.md)
- `GameplayInstance.end()` 末尾自动调 `EventProcessor.remove_handlers_by_owner_id(actor.get_id())` 清理所有 actor 的 PreEvent handler 注册，避免跨战斗累积孤儿。不 revoke ability，保留 `_abilities` 数组以支持复活等语义。

### Changed
- `Ability` 删除 `_lifecycle_context` 字段。`apply_effects(ctx)` 不再缓存 context，`remove_effects()` 内部通过新方法 `_build_remove_context()` 从 `owner_actor_id` + `GameWorld.get_actor` 按需重建精简 context（仅 `ability`/`attribute_set`/`ability_set` 三字段，`event_processor`/`owner_actor_id` 在 on_remove 路径上无消费者）。幂等性改由 `_effects_active: bool` 哨兵维护。  
  → [design-notes/2026-04-19-ability-lifecycle-decoupling.md](docs/design-notes/2026-04-19-ability-lifecycle-decoupling.md)
- `PreEventComponent` 删除 `_lifecycle_context` 字段。注册到 `EventProcessor._pre_handlers` 的 handler/filter lambda **只捕获 String ID 和用户 Callable**，不捕获 `self`（PreEventComponent 实例）；触发时通过静态方法 `_rebuild_context` 按需构造。重建包含三层 null 短路：
  1. `GameWorld.get_actor` 找不到 actor → `pass_intent()`
  2. `actor.is_pre_event_responsive()` 返回 false → `pass_intent()`
  3. `ability_set.find_ability_by_id` 找不到 ability → `pass_intent()`  
  这同时修复了潜在的"死者/已 revoke ability 的幽灵 handler 响应"问题。
- `DynamicStatModifierComponent` 删除 `_context: AbilityLifecycleContext` 缓存字段。`on_remove` 从参数收 context（签名本来就如此）。
- `tests/core/events/pre_event_component_test.gd` 重写测试 setup，通过 `GameWorld.create_instance` + `instance.add_actor` 注册真实 MockActor（继承 `Actor`），匹配生产代码"handler 重建需要 actor 在 GameWorld 里"的契约。

## [Unreleased] — 2026-04-19 后续轮：结构性循环根治

上一轮识别但未修的循环 C、调研发现的循环 D/E 本轮一次性处理。统一原则：**子对象回指所属 container 禁止强引用，一律用 WeakRef 或 String id**（此约定之前只由 `Actor._instance_id: String` 体现）。

### Changed
- `AbilityComponent._ability: Ability` → `_ability_ref: WeakRef`（循环 C）。`initialize()` 调 `weakref(ability)`；`get_ability() -> Ability` 新增，返回 `_ability_ref.get_ref() as Ability`（可能 null，调用方需短路）。子类不再允许直接访问 `_ability` 字段。  
  → 修复：`Ability._components[]` ↔ `AbilityComponent._ability` 互持强引用，GDScript RefCounted 无循环 GC，Ability 对象图永不释放。
- `TimeDurationComponent._trigger_expiration()` 使用 `var ability := get_ability(); if ability != null: ability.expire(...)` 替代直接字段访问。唯一的 stdlib 外部消费点。
- `AbilityExecutionInstance` 删除 `_game_state_provider: Variant` 字段（循环 D）。`tick(dt, provider)` / `fire_sync_actions(actions, tag, provider)` / `_build_execution_context(tag, provider)` / `_execute_actions_for_tag(tag, actions, provider)` 全部添加 `provider: Variant` 参数。`Ability.tick_executions(dt, provider)` / `AbilitySet.tick_executions(dt, provider)` 同步加参。`Ability.activate_new_execution_instance` 保留 `p_game_state_provider` 参数**仅用于 activate 瞬间 `fire_sync_actions(__timeline_start__)`**，不再传入 `AbilityExecutionInstance.new`。  
  → 修复：execution instance 缓存 provider（= battle）形成 `battle → actor → ability_set → ability → _execution_instances → _game_state_provider = battle` 循环。遵循既有"provider 是调用时参数流"约定（对齐 `HandlerContext.game_state` / `ExecutionContext.game_state_provider` / `Component.on_event`）。
- `System._instance: GameplayInstance` → `_instance_ref: WeakRef`（循环 E）。`on_register(instance)` / `on_unregister()` / 新增 `get_instance() -> GameplayInstance` 短路返回。`get_logic_time()` 走 getter。`ProjectileSystem._process_pending_removal` 唯一外部消费点改为局部 `var instance := get_instance()`。  
  → 修复：`GameplayInstance._systems[]` ↔ `System._instance` 互持强引用。虽然 `GameplayInstance.end()` 会调 `system.on_unregister()` 主动解链，但这是纪律防御（依赖 end 被正确调用）；WeakRef 把它变成结构性防御。

### 外部调用点同步
- `hex_battle.gd:343`、`scripts/SkillPreviewBattle.gd:98`、`tests/smoke_strike.gd:71`：`actor.ability_set.tick_executions(dt)` → `.tick_executions(dt, self/battle)`。
- `addons/logic-game-framework/tests/core/abilities/ability_execution_instance_test.gd` / `ability_test.gd` / `timeline_loop_test.gd`：补齐新签名。

### 验证（基线 → 本轮后）
| 测试 | Before | After |
|---|---|---|
| LGF 单元测试 (59/59) | 25 leaked | **14** |
| `smoke_strike.tscn` | 41 leaked | **38** |
| `smoke_frontend_main.tscn` | 57 leaked | **46** |

### 待处理
- **smoke_strike 剩余 38 泄漏的根源**：shutdown 时 battle 在 `_end_all_instances` + `_instances.clear()` 后仍有 1 个真实外部强引用。不是循环 C/D/E。可能的候选：Action 里某个 Callable / event 字典持对象引用 / `UGridMap.place_occupant` 缓存的 occupant 路径。独立问题，需要新一轮 probe 定位。
- 本轮本该带来的数字下降受到此残余循环压制，因此循环 D 的实际收益被低估了（frontend 降 11 是循环 D 的真实体现，smoke_strike 未能暴露）。

## [Unreleased] — 2026-04-19 第三轮：pre_change 闭包循环根治（config 驱动跨属性 clamp）

承接上一轮「smoke_strike 剩余 38 泄漏」待处理项。PREDELETE probe 定位到：
```
CharacterActor.attribute_set → HexBattleCharacterAttributeSet
HexBattleCharacterAttributeSet._pre_change_callback → Callable
Callable → (闭包捕获 self) → CharacterActor   ← 循环
```
即 `CharacterActor._setup_attribute_constraints` 注册的 lambda 在访问 `attribute_set.max_hp` 时隐式捕获 `self`，形成 actor ↔ attribute_set ↔ Callable 三角强引用。属于循环 C/D/E 同族（子对象存的 Callable 捕获 owner），但表层是「闭包捕获」而非「字段缓存」。

### 架构决策：pre_change callback → 声明式 config 驱动的 cross-attr clamp
`_pre_change_callback` 的实际能力只能改 `inout_value["value"]`（clamp），无法触发副作用 —— **唯一用例**是跨属性 clamp（hp ≤ max_hp）。收敛为声明式 API 后 Callable 彻底消失。

### Added
- `RawAttributeSet.register_cross_attr_clamp(target, bound, source)` + `clear_cross_attr_clamps()`。`bound` 取 `"max"` / `"min"`，`source` 属性的 current value 作为 target 的动态边界。构建期 assert target/source 必须在同 set 里定义。
- `BaseGeneratedAttributeSet.register_cross_attr_clamp` 转发。
- Attribute config schema 新增 `maxRef` / `minRef` 字段，值为同 set 内的属性名。生成器在 `_init()` 末尾自动产出 `_raw.register_cross_attr_clamp(...)` 调用，并在生成期 validate source 存在；缺失时 `push_error`。
- `example/attributes/attributes_config.gd` 的 `HexBattleCharacter.hp` 加 `"maxRef": "max_hp"`，生成文件同步重建。

### Removed
- `RawAttributeSet._pre_change_callback` 字段 + `set_pre_change(callback)` + `clear_pre_change()`。
- `BaseGeneratedAttributeSet.set_pre_change(callback)` 转发。
- `CharacterActor._setup_attribute_constraints()` 函数 + `_init()` 里的调用（约束语义已完全下沉到 config）。

### Changed
- `RawAttributeSet.get_breakdown()` 计算流程「步骤 2」从「调 `_pre_change_callback`」改为「遍历 `_cross_attr_clamps` 并走 `get_breakdown(source)`」。读 source 时复用已有 `_computing_set` 循环检测机制，语义一对一。
- `tests/core/attributes/attribute_set_test.gd` 两个 pre_change 测试改名为 `cross_attr_clamp_*`，API 切换为 `register_cross_attr_clamp("hp", "max", "max_hp")`，断言不变。

### 主仓库同步
- `character_actor.gd` 删 `_setup_attribute_constraints` 调用。项目级 `logic-game-framework-config/attributes/attributes_config.gd`（`Hero`/`Tower`）因不含 hp 属性，无需改动。

### 验证（基线 → 本轮后）
| 测试 | Before | After |
|---|---|---|
| LGF 单元测试 (59/59) | 33 leaked / 14 resources | **24 leaked / 11 resources** |
| `smoke_strike.tscn` | 112 leaked / 38 resources | **0 / 0** 🎯 |
| `smoke_frontend_main.tscn` | 46 resources | **0 / 0** 🎯 |

→ [design-notes/2026-04-19-attribute-cross-clamp-config-driven.md](docs/design-notes/2026-04-19-attribute-cross-clamp-config-driven.md)

### 待处理
- LGF 单元测试 24 leaked / 11 resources 是**测试框架层面**的泄漏（testframework 保留每个 `*_test.gd` 的 GDScript 引用），与生产代码无关，独立问题。
- `_listeners: Array[Callable]` 仍是潜在风险点：若业务代码向 `attribute_set.add_change_listener` 传入捕获 actor 的 lambda，会形成 actor ↔ attribute_set ↔ listener 循环。生成器产出的 wrapper 只捕获 `actor_id` String 和用户 Callable，自身安全；但用户侧 Callable 的闭包捕获需要审计（后续同类风险扫描）。
