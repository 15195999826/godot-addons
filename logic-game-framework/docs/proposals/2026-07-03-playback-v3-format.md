# 录像 v3 格式提案：world_snapshot 归位 + 单路径录像

> ✅ **已执行完成（2026-07-03，单轮，用户批准后落地）**。全量验证：hex/all + inkmon/all + dota2autobattle/all 50/50 绿 + all-required 15/15 绿（含 LGF 73 单元、68 scenario 契约）；golden 重烤——ticks/frames/result 与旧基线逐项一致 = 逻辑行为零漂移，仅指纹载体变化。双 review：V1 一致性核对（提案 §3 逐条零遗漏）+ codex exec review（submodule P1 + 主仓 P2 = 同一 finding，见偏差 ⑧，已修复复绿）。
>
> **执行偏差记录（相对本提案）**：
> ① recorder 的 actor 变化**订阅保留**，签名定为 `start_recording(world_snapshot, actors)` 两参——执行时查证 `attributeChanged` 有真实回放消费者（inkmon render2d `apply_event_side_effects`），订阅是这些事件的唯一产生管道；原 events-only 注释"这些由 event_collector 的事件承载"系误导（这也解释了该路径为何从未有人敢用）。
> ② `_recording_enabled` 开关上提 `BattleProcedure` 基类，inkmon override 连薄开关都不留——**三处 override 全删**（提案原计划 inkmon 留一行）。
> ③ InkMonWorldGI **不补** `_get_position_formats`——inkmon render2d 不消费 positionFormats，不养无消费数据（与砍 abilities/tags 同一取舍逻辑）。
> ④ 中途 spawn 补录连接 `_on_world_actor_added` + `finish()` disconnect 上提基类（消灭 hex/skill-preview 双份实现；hex 原版漏 disconnect 的泄漏顺手根治）；基类版不带 participants 去重 guard——`register_actor` 的订阅表前置检查已覆盖去重语义。
> ⑤ `smoke_mid_spawn_production_replay` 删 4 条白带快照断言（actorSpawned payload 的 abilities 字段），补 2 条真管道断言（TotemLifetime / FireTileLifetime 的 abilityGranted）。
> ⑥ inkmon animator 对 `configs.animation` 的死读（recorder 侧从未写过该 key，永空）改 `create_default()`。
> ⑦ golden smoke 顺修 key 拼错潜伏 bug（`"initial_actors"` ≠ 实际 `"initialActors"`——v2 时代快照从未真正入过指纹锁），v3 起 world_snapshot 真入锁并重烤基线。
> ⑧ **codex finding 修复**：快照范围"全体 registry"在常驻世界是盲区——InkMonWorldGI 的 registry 常驻 overworld 玩家/NPC（`add_actor` 双写 registry + world_actors dict），全量快照会让 2D 回放画出非战斗实体。修复 = 基类 `should_record_actor()` 录像范围钩子（快照/订阅/中途补录三处同语义），InkMonWorldGI override 为 `actor is InkMonUnitActor`。
> ⑨ 文档同步扩展：enforcing-lgf skill（stdlib.md/entity.md v3 增量 + `.agents/` 镜像整体重同步——上午校准漏了镜像）、LGF docs/README.md §(c) 重写、CHANGELOG 双条目、hex frontend/README JSON 示例 v3 化、SimulationManager 欠账注释、adr/0005 修订行。
>
> 任务来源：主仓 `docs/future/task-queue.md` 3b（2026-07-03 用户点名）。
> 决策方式：grill 会话逐项拍板（2026-07-03，用户 + fable），本文 = 拍板的固化 + 执行清单。
> 关联：主仓 `docs/adr/0005-presentation-true-2d-isometric-hex.md`（inkmon 全量录像的原始决策，本轮兑现其意志并更新措辞）。

---

## 0. 拍板记录（TL;DR）

| # | 决策点 | 拍板 |
|---|---|---|
| 1 | 档位 | **全套 v3**：JSON 字段搬家（world_snapshot 独立字段），代码结构与数据结构双归位 |
| 2 | web 桥 JS 端解析器 | **不管**（外部仓）。记欠账：web 发布启用时同步 |
| 3 | version 字段 | **删除**（连同 `PROTOCOL_VERSION` 常量）。理由：单一底层架构、录像是短命数据（打完→播完→丢）、无存量资产（`user://Replays/` 仅 hex demo 测试产物）、无多版本共存需求。防呆改为必需字段检查（§2.3） |
| 4 | 快照范围 | **全体 registry actor**（含 Environment/障碍物），中途 spawn 继续走 ActorSpawned 事件。三个使用方的范围差异（hex 仅 Character / skill-preview 全体 / inkmon 全体参战）消失 |
| 5 | ActorInitData 白带字段 | **砍 abilities/tags**，快照七字段（§2.2）。Actor 上的 `get_ability_snapshot()/get_tag_snapshot()` **保留**——录像外有消费者（hex GI 观察快照 `hex_world_gameplay_instance.gd:164-166`、skill_preview tags 面板 `skill_preview.gd:1667`） |
| 6 | 旧模式去留（task-queue 3b 议题 2） | **彻底删除，只有一种模式**：`start_recording(actors, configs, map_config)`（recorder 自己抄 actor）删除；`start_recording_events_only()` 演化为唯一路径 + world_snapshot 由世界侧注入。双路径 / 「基类默认指向零使用者死路」的半吊子状态消灭 |
| 7 | 录像大小优化三方案 | **不搭车**（事件过滤/高频节流/二进制格式与 v3 结构正交，继续挂账，等真痛再立项） |

## 1. 事实链（反直觉结论，防未来困惑重蹈）

本轮调研推翻了三个直觉预设，未来读者（包括未来的 AI）看到 v3 时的第一反应大概率也是这三个错觉，故显著记录：

1. **快照是回放的必需品，v3 不会让文件变小。** 战斗在一个 world tick 内 blocking 跑完（`WorldGameplayInstance.tick`），回放开始时世界里的 actor 已是**终态**（残血/死亡），而回放要从**开战初态**播——初态只存在于快照里。`battle_recorder.gd` 旧头注释「录像回放时……或复用现有 world」的设想对战后回放**不成立**，本轮作废该设想。真正能瘦文件的是大小优化三方案（挂账），与 v3 无关。
2. **不能拿存档序列化当快照。** inkmon 存档切片（`InkMonUnitActor.to_dict`，adr/0001）是最小持久态——派生六维（maxHp/ad/…）读档时重算；而回放器（inkmon render2d、未来 JS 端）**没有规则引擎**，需要含派生值的自足快照（render2d 实际消费 `hp/maxHp/facing_direction`）。存档序列化与录像快照是**两套各有正当语义的 actor→dict**，不是重复建设，不合并。
3. **abilities/tags 字段零消费是架构必然，不是暂时没人用。** A 层铁律「Playback 不重建逻辑层」（LGF docs/README.md 设计铁律）——回放只 spawn 视觉替身，画替身只需要「长什么样」（位置/血条/朝向），不需要「能干什么」；B 层 Replay（deterministic 重算）若未来真做，需要的是「初始配置 + 种子」，abilities 从 configId 查配置重建，也不消费实例快照。两层都永远不会有消费者。
4. **双路径半吊子的根源是 v3 未立项，不是执行偷懒。** hex override 注释明言「v3 落地时再切」、inkmon 是 adr/0005 显式决策、skill-preview 有 positionFormats 需求——三个 override 皆有意。坏味道只有一个：基类默认（`events_only`）指向一条零生产使用者的路。本轮了断。

## 2. 格式定义

### 2.1 文件结构 before / after

```jsonc
// ===== v2（现状）=====
{
  "version": "2.0",              // 删除
  "meta": { "battleId": "...", "recordedAt": 0, "tickInterval": 100, "totalFrames": 0, "result": "" },
  "configs": { "positionFormats": {"Character": "hex"} },   // 顶层字段消失，唯一内容迁入 world_snapshot
  "mapConfig": { ... },          // 迁入 world_snapshot
  "initialActors": [ ... ],      // 迁入 world_snapshot.actors
  "timeline": [ {"frame": 0, "events": [...]}, ... ]
}

// ===== v3（目标）=====
{
  "meta": { "battleId": "...", "recordedAt": 0, "tickInterval": 100, "totalFrames": 0, "result": "" },
  "world_snapshot": {                          // 世界侧状态，泾渭分明
    "actors": [ ... ],                         // §2.2 七字段
    "mapConfig": { ... },
    "positionFormats": { "Character": "hex" }
  },
  "timeline": [ {"frame": 0, "events": [...]}, ... ]   // 战斗过程，recorder 唯一职责
}
```

`meta` 不动（录像自述数据，均有消费者）。

### 2.2 world_snapshot.actors 单条（七字段）

```jsonc
{
  "id": "1:3",
  "type": "Character",
  "configId": "warrior",
  "displayName": "左方 1",
  "team": 0,
  "position": [-3, -1],                        // 按 positionFormats 解释
  "attributes": { "hp": 100, "maxHp": 100, "facing_direction": 0, ... }   // 子类 get_attribute_snapshot 决定字段
}
```

删除 `abilities` / `tags`（拍板 #5）。

### 2.3 防呆（替代 version 字段）

播放入口（`PlaybackData.BattleRecord.from_dict` 或各 load 侧）对缺失 `world_snapshot` / `timeline` 的 dict **`Log.assert_crash`**——坏文件/旧格式文件喂进来要炸得响，不允许静默播空场。防呆靠必需字段检查，不靠版本号。

## 3. 代码改造清单

### 3.1 core/playback

- **`playback_data.gd`**：删 `PROTOCOL_VERSION` 与 `BattleRecord.version`；`BattleRecord` 重构为 `{meta, world_snapshot: WorldSnapshot, timeline}`；新增内部类 `WorldSnapshot {actors: Array[ActorInitData], map_config: Dictionary, position_formats: Dictionary}` + to_dict/from_dict；`ActorInitData` 删 abilities/tags 字段及 `create()` 内两行（类名保留，smoke 类型标注波及最小）；`from_dict` 加 §2.3 防呆。
- **`battle_recorder.gd`**：删旧 `start_recording(actors, configs, map_config)`；`start_recording_events_only()` 转正为唯一 `start_recording(world_snapshot: PlaybackData.WorldSnapshot)`——**快照必传**（「每场可回放的战斗必须有快照」编码进签名；不录像的战斗根本不建 recorder）。actor 订阅生命周期（register/unregister → ActorSpawned/Destroyed 事件）不变。头注释：「已知问题：文件大小」段保留；v3 设想段改写为现状描述（含「复用现有 world 不成立」结论，防设想复活）。
- **`playback_log_printer.gd`**：`initial_actors` → `world_snapshot.actors`。

### 3.2 core/entity（快照产出者归位）

- **`world_gameplay_instance.gd`**：新增 `capture_world_snapshot() -> PlaybackData.WorldSnapshot`——全体 registry actor 七字段快照 + `grid != null ? grid.to_config_dict() : {}` + `_get_position_formats()` 虚钩子（基类默认 `{}`，坐标系解释是子类知识）。
- **`battle_procedure.gd`**：`_start_recorder()` 基类默认实现改为「`_get_world().capture_world_snapshot()` 注入 + 启动」；头注释「子类可 override 走旧版」段删除。
- **`Actor.gd`**：`get_ability_snapshot()/get_tag_snapshot()` **保留**（拍板 #5 查证：录像外有消费者）。

### 3.3 三个 override 的处置

| 使用方 | 处置 |
|---|---|
| `hex_battle_procedure.gd:69` | override **删除**（回归基类默认）；positionFormats 移至 `HexWorldGameplayInstance._get_position_formats()`（`{KIND_CHARACTER: "hex", KIND_ENVIRONMENT: "hex"}`）；`actor_added → _on_world_actor_added` 中途补录连接保留 |
| `skill_preview_procedure.gd:65` | override **删除**（同上，SkillPreview 所属 GI 提供 position formats） |
| `ink_mon_battle_procedure.gd:34` | override 瘦身为纯开关：`if _recording_enabled: super._start_recorder()`；adr/0005 注释措辞更新（全量录像 → world_snapshot 承载开战阵容，意志不变、载体正名）；`InkMonWorldGI._get_position_formats()` 补 override |

### 3.4 消费方

- **inkmon render2d** `render_world.gd:44-52`：`initialize_from_replay` 读 `record.world_snapshot.actors`。
- **hex frontend** `render_world.gd:114-128`：positionFormats 从 `world_snapshot` 读；`initial_actors` → `world_snapshot.actors`。`battle_animator.gd:84/373` 同步（含头注释 v2 措辞）。
- **主仓 adr/0005**：补一行修订记录（initial_actors → world_snapshot，2026-07-03 v3）。
- **web 桥 `SimulationManager`**：代码不动；文件头或 run_battle 注释记欠账「返回 JSON 已升 v3 形状，JS 解析器同步延后至 web 发布启用（2026-07-03 拍板）」。

### 3.5 测试面（机械适配）

- 直调 `recorder.start_recording(...)` 的：`skill_scenario_harness.gd:645`（**68 scenario 的底座，优先改**）、`smoke_summon_spike.gd:162`。
- 手工构造录像 dict/fixture 的 frontend smoke：hex 6 个（facing_indicator / regeneration_visualizer / surge_unit_view / buff_ui / buff_pipeline / shield_ui）+ inkmon `smoke_battle_2d_replay` / `shot_battle_baked`。
- 断言录像形状的：`smoke_skill_preview_environment`（initialActors 断言路径）、`smoke_random_frontend_20_runs`（initialActors 计数）、`smoke_battle_golden`（**golden 基线含 initial_actors key，格式变更后需重烤基线**，重烤理由写进该 smoke 注释）。

### 3.6 明确不动

- 「录像顺序 = 调用栈真实顺序」铁律与 EventCollector 单队列机制。
- A 层 Playback 不重建逻辑层铁律；B 层 Replay 继续不做（命名占位维持）。
- `meta` 结构、事件 dict 形状、`assert_replay` 测试 DSL 族、`BattleRecorder` 类名。
- 大小优化三方案（拍板 #7，继续挂账于 `battle_recorder.gd` 头注释）。

## 4. 验收

1. 全量 `run_tests.ps1 -Required hex/all dota2autobattle/smoke inkmon/all` + LGF 单元 73 tests（改 core 波及全域）。
2. golden 基线重烤后 `inkmon/regression` 复绿。
3. hex demo F6 回放 + inkmon training battle 2D 回放（DevAgent 场景驱动，pause/step 定格验证开战阵容与 v2 视觉一致）。
4. `grep -r "initialActors\|initial_actors\|PROTOCOL_VERSION\|start_recording_events_only"` 全仓归零（注释中的历史提及除外）。

## 5. 执行切分

单轮完成（量级 ≈ 线 3 轮 C+D 之和：core 4 文件 + 使用方/消费方 ~8 文件 + 测试 ~10 文件），submodule commit + 主仓 bump 同批联动。沿用线 3 纪律：实现 → 全量测试 → V1 一致性 review（agent 对照本提案核对 diff）→ codex review → commit。
