# LGF 框架优化 Backlog

外部评审（codex）+ 内部扫码后归纳出的"设计未完全收敛"清单。本文只**陈述事实 + 给出选项**，不做最终决断——逐项与 owner 对齐后再落地。

每条结构：**现状 / 证据 / 影响 / 候选方向 / 待决断**。

> 注：标"⏸ 不视为问题"的条目保留在文档里只是为了留痕，避免下一轮再重新捞一遍。

---

## 1. WorldGameplayInstance 把 hex 概念塞进 core ⏸ 当前路线图下不修

### 现状
`core/entity/world_gameplay_instance.gd` 直接 import `HexCoord` / `GridMapConfig` / `GridMapModel`：

```gdscript
signal actor_position_changed(actor_id: String, old_coord: HexCoord, new_coord: HexCoord)  # L29
signal grid_configured(config: GridMapConfig)                                              # L30
var grid: GridMapModel = null                                                              # L37
func configure_grid(config: GridMapConfig) -> void:                                        # L67
```

### codex 的论据
"概念倒挂、违反层次"——按"通用框架洁癖"看 core 不该知道 hex。

### owner 的反论据（已采纳）
> 规划是基于框架实现**多个不同类型 game 的 example**。core 适度耦合 hex/grid 是当前 example 系列共享的基线。

这是合理的 YAGNI 判断：在没有第二个**非 hex** example 真的落地之前，把 grid 抽成 `ISpatialBackend` 是过度工程。框架的边界由路线图决定，不是由"理论上的最大泛化"决定。

### 评估
当前路线图下 **不是问题**。否决合理。codex 的评审视角是"通用框架洁癖"，没考虑路线图——owner 视角更准。

### 触发重审条件
出现以下任一情况再回来看：
- 立项一个**完全脱离 grid** 的 example（纯卡牌 / 文字冒险 / 横版动作）；
- 出现需要把 LGF core 单独发布给外部用户的需求（届时通用性会成为约束）；
- `WorldGameplayInstance` 子类数量增加到 3+，且其中超过一个不用 grid。

### 处理
不修。等触发条件出现再评估"拆基类"或"承认就是 grid 框架"。

---

## 2. core → stdlib 反向依赖（BattleRecorder）

### 现状
按 `CLAUDE.md` 依赖图，stdlib 建在 core 之上（`Replay → Events`）。但 core 直接持有并构造 stdlib 的类：

```gdscript
# core/entity/battle_procedure.gd
var _recorder: BattleRecorder = null                                       # L21
_recorder = BattleRecorder.new({"tickInterval": int(_tick_interval)})      # L45
func get_recorder() -> BattleRecorder:                                     # L94
```

`Actor.gd` 注释里也多处出现 "BattleRecorder 兼容属性"、"BattleRecorder 调用" 等字样（L109/121/128/162）。

### 影响
- 单向依赖图被破坏：core 装载时若 stdlib 还没就位，类型不在；
- 未来想把 LGF 拆成两个 addon（core 单独可用），这个引用会卡死；
- 反过来想替换 recorder 实现（比如做个 NoopRecorder / NetworkRecorder）必须改 core。

### 候选方向
| 方案 | 描述 | 代价 |
|---|---|---|
| A | core 定义 `IRecorder` interface，`BattleProcedure` 持有 interface，stdlib 提供具体 `BattleRecorder` 实现 | 加一层 interface，构造点上移到调用方 |
| B | `BattleProcedure` 整体下放到 stdlib（core 只剩 `WorldGameplayInstance` 调度逻辑，battle 由 stdlib 提供） | 改动面较大，但层次最干净 |
| C | 维持现状，把 stdlib/replay 的 BattleRecorder 物理移进 core | 最省事，等于承认"录像就是 core 一部分" |

### 待决断
recorder 是否属于 core 概念？

---

## 3. ProjectileActor 在 core

### 现状
`core/entity/projectile_actor.gd` 整个文件在 core，且：
- 硬编码玩法风味常量 `PROJECTILE_TYPE_BULLET / HITSCAN / MOBA`；
- 注释里引用 `ProjectileSystem._update_projectile()`（该类在 `stdlib/systems/`），又是一处反向引用；
- `core/events/projectile_events.gd` 同理在 core。

### 影响
- 不做投射物的 example（比如纯回合卡牌）继承 core 时白带这个类型；
- "投射物"是相当具体的玩法概念，按粒度看更适合 stdlib 或 example。

### 候选方向
| 方案 | 描述 |
|---|---|
| A | 整体迁到 `stdlib/projectile/`，core 完全不知投射物 |
| B | core 只保留 `Actor` 基类的 `position` 抽象，投射物全迁到 stdlib |
| C | 不迁，承认"投射物是 LGF 当前定位（ATB/Hex/RPG）的一等公民" |

### 待决断
投射物算 core 还是 stdlib？取决于"通用 Actor 之外的特化 Actor"放哪一层。

---

## 4. Replay / Playback / Director 命名混用

### 现状
同一概念在不同层用三套词，且交叉：

| 层 | 用词 | 文件 / 符号 |
|---|---|---|
| stdlib 数据类 | **Replay** | `ReplayData.BattleRecord` / `replay_data.gd` / `replay_log_printer.gd` |
| stdlib 写入器 | **Recorder** | `BattleRecorder` / `recording_context.gd` / `recording_utils.gd` |
| frontend signal | **playback** | `battle_animator.gd::playback_started/ended/state_changed`、`battle_director.gd::playback_*` |
| frontend API | **replay (动词)** | `battle_director.gd::load_replay(record)` / `_replay_data` |
| frontend UI | **Playback** | `ui/playback_controls.gd` |
| frontend 执行 | **Director** | `battle_director.gd` |

### 立场（owner，已记入 memory）
A 层 = **Playback**（录像播放，现役）；B 层 = **Replay**（确定性回放，未来不一定做）。

### 影响
当前混用让"现役 = A 层"这个事实在代码里看不出来——`ReplayData` / `load_replay()` 这些命名容易误导新读者以为已经是 B 层。

### 候选方向
| 方案 | 描述 |
|---|---|
| A | 一次性把现役全部改成 Playback 口径：`ReplayData → PlaybackData`、`load_replay → load_playback`；B 层做的时候再引入 `ReplayXxx` | 改动面大但一次到位 |
| B | 划清边界：只把 `frontend/` 内的命名收敛到 Playback，stdlib 保留 Replay 词义但 docstring 注明"现役只用 A 层" | 改动小，命名仍混 |
| C | 等 A 层整合那轮一并 rename | 维持现状，欠条挂账 |

### 待决断
什么时候做 rename？随哪一轮改动捎带？

---

## 5. 强类型事件最后仍大量落回 Dictionary

### 现状
`core/events/game_event.gd` 定义了 ~12 个强类型 class（`ActorSpawned` / `AttributeChanged` / `AbilityActivated` / `AbilityStacksChanged` / `ProjectileHit` ...），每个都有 `to_dict()` / `from_dict()` / `is_match()`。

但所有消费路径仍是 Dictionary：

```gdscript
# core/events/event_processor.gd
func process_pre_event(event_dict: Dictionary, ...) -> MutableEvent           # L122
func process_post_event(event_dict: Dictionary, ...) -> void                  # L216

# core/events/mutable_event.gd
var original: Dictionary                                                       # L11
func to_final_event() -> Dictionary                                            # L47

# core/abilities/core/ability.gd
func receive_event(event_dict: Dictionary, ...) -> void                       # L137

# core/events/event_collector.gd
func push(event_dict: Dictionary) -> Dictionary                                # L47

# 所有 component 的 on_event / _check_conditions / _check_costs / matches_event 全吃 Dictionary
```

强类型类只活在两个端点：构造时 `XEvent.create(...).to_dict()`、反序列化时 `XEvent.from_dict(d)`。中间所有 handler / condition / cost / modifier / processor / collector 都靠 `event.get("xxx", default)` 字符串 key 读字段。

### 影响
- 强类型 = 纯文档：编译器不强制，运行时不校验，handler 拼错 field 名只能等 KeyError；
- 每次 emit 一个事件要 `.to_dict()` 一次，每次读字段还是 `event.get("xxx")`，**强类型完全没节省手指**；
- `MutableEvent` 在 Dictionary 的 numeric field 上跑 SET/ADD/MULTIPLY，没办法靠类型推断校验某 field 是不是数字，只能 `typeof()` 运行时判。

### 候选方向
| 方案 | 描述 | 代价 |
|---|---|---|
| A 贯通强类型 | `EventProcessor` / `MutableEvent` / handler 签名全切 `GameEvent.Base`，Dictionary 只在序列化端点（写录像、JS bridge）出现 | 改动面非常大，所有 ability / condition / handler 都要改签名 |
| B 删强类型 | 承认 Dictionary 是事实标准，删掉 `game_event.gd` 里的 12 个 class，只保留 kind 常量 | 失去文档价值，但代码更诚实 |
| C 半贯通 | 关键 hot path（damage / attribute_changed）切强类型，其余按需 | 维持现状的折中 |
| D 代码生成 | 保留强类型 + Dictionary 双轨，但用脚本/宏生成 dict access wrapper（`event.actor_id` 而不是 `event.get("actorId")`） | Godot 没好的代码生成路径 |

### 待决断
强类型事件这层是要的还是不要的？拍板后才能决定全切还是全删。

---

## 优先级建议（待 owner 确认）

| # | 项 | 严重度 | 推荐动作 |
|---|---|---|---|
| 1 | hex 进 core | ⏸ 不视为问题 | 不修 |
| 2 | core → stdlib（recorder） | 🟡 中 | 拍 IRecorder 方向后再做 |
| 3 | ProjectileActor 位置 | 🟡 中 | 与 #2 同批讨论"core 边界"时一起拍 |
| 4 | Replay/Playback 命名 | 🟢 低 | A 层整合那轮捎带 rename |
| 5 | 强类型事件 | 🟡 中 | 优先讨论：决定贯通还是删，否则越拖越尴尬 |

---

## 元结构

逐项讨论时建议按这个流程更新本文：

1. 在该项标题旁加 ✅ 已决断 / ⏸ 暂不修 / 🚧 进行中
2. 把决议写进"待决断"段下
3. 实施后在条目末尾加 → `docs/design-notes/YYYY-MM-DD-xxx.md` 指向具体的设计长文
4. 完成的条目移到本文末尾的"已收敛"段，保留索引但不再占顶部位置
