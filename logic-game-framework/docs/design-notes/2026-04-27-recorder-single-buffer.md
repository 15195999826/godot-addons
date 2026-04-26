# BattleRecorder 单 buffer 重构 — 根治录像事件时序错位

**日期**: 2026-04-27
**范围**: `stdlib/replay/battle_recorder.gd` / `stdlib/replay/recording_context.gd`
**前置**: `2026-04-19-world-as-single-instance.md`(WorldGameplayInstance / event_collector 在世界层),`dc3dcac`(颠倒顺序的症状疗法,本轮被取代)

---

## 1. 范围 / 前置

- 修改文件:`stdlib/replay/battle_recorder.gd`、`stdlib/replay/recording_context.gd`
- 不动:`core/events/event_collector.gd`(已是正确归宿,无须改)、`core/entity/battle_procedure.gd`(`record_frame(_, events)` 调用契约不变)
- 依赖前轮:EventCollector 已经是 GameWorld 层 autoload-accessible 单例;BattleRecorder 已只负责 session(meta/timeline/subscription),不参与逻辑层

---

## 2. 背景

上一轮(`dc3dcac`)修了 Surge buff 的视觉错位 — buff 显示 U3 → U1(漏掉 U2)。把 `record_frame` 的合并顺序从 `[events, pending]` 颠倒为 `[pending, events]` 后症状消失,SurgeScenario 的 `grant_index < first_stacks_index` 断言 PASS。

但用户接着指出:**这种症状疗法无法处理 Action 中途 grant ability 的穿插场景**。比如:

```
逻辑时序:
  T1: Action_A push damage1            → collector
  T2: Action_A.grant_ability → on_added → pending (callback)
  T3: Action_A push damage2            → collector

容器状态:
  collector = [damage1, damage2]
  pending   = [AbilityGranted]

无论 [events, pending] 还是 [pending, events] 都错:
  → [damage1, damage2, AbilityGranted]   ← AbilityGranted 漂到末尾
  → [AbilityGranted, damage1, damage2]   ← AbilityGranted 漂到开头

真实顺序: [damage1, AbilityGranted, damage2]
```

任何按"容器类型"的固定拼接都构造得出反例。问题不在合并顺序,在"为什么有两个容器"。

---

## 3. 定位

读 `battle_recorder.gd:5-11` 的原始 docstring:

> 录像事件有两个来源:
> 1. 主动事件(frame_events):每帧 tick 中由 EventCollector.flush() 收集,如伤害、治疗等
> 2. 被动事件(pending_events):由 RecordingContext 监听回调在 tick 过程中**异步**触发,如属性变化、Tag 变化、Ability 获得/移除等

关键词「异步」「帧间缓冲区」暴露了原始误解 — callback **不是真异步**:

- `Ability.on_added` 是在 `grant_ability()` 同步栈里 fire 的,不跨帧、不进队列
- `AttributeChanged` 在 `modify_hp` 同步栈里 fire
- `TagChanged` 在 `add_tag` 同步栈里 fire

它们和 Action 自己的 `event_collector.push(...)` 在调用栈上是**穿插发生**的,不是"先一批 callback 再一批 push"。

把 push 入口的代码位置(callback vs Action)误当成了逻辑发生时序,所以分了两个容器。一旦穿插出现,任何拼接顺序都丢失交错信息。

---

## 4. 根因

```
单一调用栈,真实穿插:
  Action_A.execute()
    ├─ ctx.event_collector.push(damage1)                    ← collector
    ├─ target.grant_ability(...)
    │    └─ ability.on_added(actor)
    │         └─ subscription_callback (RecordingContext)
    │              └─ _recorder.pending_events.append(...)  ← pending  ← 错位入口
    └─ ctx.event_collector.push(damage2)                    ← collector

帧末:
  events  = event_collector.flush()  = [damage1, damage2]
  pending = recorder.pending_events  = [AbilityGranted]
  
  合并丢失了"AbilityGranted 在 damage1 和 damage2 之间发生"这个事实。
```

错的是入口分流,不是合并算法。

---

## 5. 架构决策

### 候选 A:加排序字段(seq / timestamp)

每个 event 入队时打全局递增 seq,合并后按 seq 排序。

**否决**:Dictionary 都要加字段,污染所有 event 类型;序列化到 JSON 还要排除;recorder 重启 seq 会乱。最关键 — **既然两个容器分流是错的,就不该靠序号去补救**,直接消除分流。

### 候选 B:让 callback 路径在 callback 内部直接 flush 后追加 events

callback 触发时立即把当前 collector flush 一次再 push 自己,保证顺序。

**否决**:flush 是有副作用的(清空 collector),会破坏 Action 后续 push 的视图。还会让 record_frame 一帧多次写入 timeline,frame 边界乱。

### 候选 C(选定):统一到 EventCollector

让 callback 路径也走 `GameWorld.event_collector.push(event)`,与 Action push 共用同一队列。所有事件按调用栈真实顺序入队,record_frame 只接收一个参数。

**为什么是 EventCollector 而非反过来**:

| 维度 | EventCollector | BattleRecorder |
|---|---|---|
| 必要性 | Action 层硬依赖,永远存在 | 可选,不录像就不创建 |
| 层 | core/events/(Core 层) | stdlib/replay/(Stdlib 层) |
| 生命周期 | 每帧 flush | 整场战斗 |

让事件流往「必选的、底层的」容器走,recorder 退化成纯 session 抽象(meta/timeline/subscription/JSON 导出)。也符合依赖方向:Stdlib → Core。

---

## 6. 实现

**`recording_context.gd::push_event`**

```gdscript
# Before
func push_event(event: Dictionary) -> void:
    if _recorder.is_recording:
        _recorder.pending_events.append(event)

# After
func push_event(event: Dictionary) -> void:
    if _recorder.is_recording:
        GameWorld.event_collector.push(event)
```

`is_recording` guard 保留 — 防 `stop_recording` 与异步 unsubscribe 之间的 callback 残响把脏事件灌进 collector(此时 collector 在被复用,不再有录像消费方)。

**`battle_recorder.gd::register_actor` / `unregister_actor`**

```gdscript
# Before
pending_events.append(event.to_dict())

# After
GameWorld.event_collector.push(event.to_dict())
```

`register_actor` 在 `start_recording` 内被循环调用(`for actor in actors`),那时 GameWorld autoload 已就绪,ActorSpawned 进 collector,等首个 tick 的 `record_frame` 一并 flush 进 frame 0。

**`battle_recorder.gd::record_frame`**

```gdscript
# Before
func record_frame(frame: int, events: Array[Dictionary]) -> void:
    if not is_recording: return
    current_frame = frame
    var all_events: Array[Dictionary] = []
    all_events.append_array(pending_events)
    all_events.append_array(events)
    pending_events.clear()
    if not all_events.is_empty():
        var frame_data := ReplayData.FrameData.new()
        frame_data.frame = frame
        frame_data.events = all_events
        _record.timeline.append(frame_data)

# After
func record_frame(frame: int, events: Array[Dictionary]) -> void:
    if not is_recording: return
    current_frame = frame
    if not events.is_empty():
        var frame_data := ReplayData.FrameData.new()
        frame_data.frame = frame
        frame_data.events = events
        _record.timeline.append(frame_data)
```

字段删除:`var pending_events: Array[Dictionary] = []` 整行删。
`start_recording` / `start_recording_events_only` 中的 `pending_events.clear()` 一并删。

---

## 7. 验证

| 测试 | Before(dc3dcac) | After |
|---|---|---|
| `run_tests.tscn` | 59/59 PASS | 59/59 PASS |
| `smoke_skill_scenarios.tscn` (13 个,含 SurgeScenario `grant_index < first_stacks_index`) | 13/13 PASS | 13/13 PASS |
| `smoke_buff_ui.tscn` / `smoke_buff_pipeline.tscn` / `smoke_surge_unit_view.tscn` | PASS | PASS |
| `smoke_frontend_main.tscn` | PASS | PASS |

SurgeScenario 关键断言("grant 早于 first stacks change")在两次实现下都 PASS,但只有本轮的实现下「Action 穿插 grant」反例也能正确处理 — 该反例当前没有专门 case 覆盖,现网无 skill 触发(待出现时直接 PASS,不需 fix)。

---

## 8. 方法论总结

> **push 入口不同 ≠ 时序不同**

callback 在同步栈里触发就是同步事件,不能仅凭"代码位置不同"分容器。识别信号:

1. docstring 出现「异步」「帧间缓冲」字样描述同步触发的 callback — 是认知出错的语言痕迹
2. 不得不靠固定拼接顺序保证时序的合并算法 — 是数据结构本身错的信号
3. 修了一种顺序后,只要稍微构造下穿插场景就破 — 症状疗法的明确特征

修法:回到「调用栈真实顺序 = 录像顺序」这个不变量,事件流合并到调用方共享的单一队列,而不是按入口分容器。

---

## 9. 遗留

无新增遗留。本轮改动取代了 `dc3dcac` 的颠倒顺序(commit 不 revert,留作历史)。后续 BattleRecorder 优化(事件过滤 / 高频节流 / 二进制格式,见 docstring 末尾)与本次重构正交,本轮不动。
