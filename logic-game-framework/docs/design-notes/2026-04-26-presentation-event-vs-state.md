# 2026-04-26 — 表演层 Event vs State 边界（动画系统约定）

## 范围 / 前置

涉及文件：

- `example/hex-atb-battle-frontend/core/render_world.gd` — `actor_died` emit 收紧
- `example/hex-atb-battle-frontend/battle_animator.gd` — wire `actor_died` event；`reset()` 遍历 view revive
- `example/hex-atb-battle-frontend/scene/unit_view.gd` — 拆 `play_death()` / `revive()` 公共方法，`update_state` 只管 state sync

依赖前轮：
- [2026-04-20-world-view.md](2026-04-20-world-view.md) — Animator + WorldView 分层落地
- [2026-04-26-playback-old-path-retirement.md](2026-04-26-playback-old-path-retirement.md) — A 层老路径下线

## 背景：bug 暴露的架构问题

用户实测：单位被普攻打死（死亡动画起播），0.3s 后亡语伤害命中同一单位，**死亡动画明显播了两次** —— 两个 tween 并行作用 `scale` / `position.y`，缩得更小、沉得更深。

第一轮 patch（`Tween.is_running()` guard） / 第二轮 patch（`_death_played` flag）都只解决死亡这一个 case。用户提出：**本质问题是动画重复播放**。任何"一次性动画"在 reactive snapshot 模式下都会落同样的坑（受击抖、命中闪、暴击大字、治疗光环 …），每个都得在 view 里加自己的 transition flag。

## 病根：`update_state(snapshot)` 把两类信息混了

`unit_view.update_state` 是 **state snapshot 同步**模式 —— Director 每帧推完整 actor 状态，view 拉到目标。这个模式适合**持续态**（值赋值，每帧覆盖天然幂等），但被错误地用来推断**一次性动画 transition**：

| 类别 | 例子 | snapshot 推送幂等？ |
|---|---|---|
| **State** — 可覆盖事实 | hp 条高度、闪白进度、染色、位置 | ✅ 每帧赋值，重复无害 |
| **Event / Transition** — 一次性命令 | 死亡动画、复活、受击抖、暴击大字、治疗光环 | ❌ 每帧重复触发会重复创建 tween / 节点 / 音效 / 粒子 |

`alive=false` 在持续态里是"一直推"的 — view 看不到"翻转那一刻"和"已经死着"的区别。

## 决策：Event vs State 分流

**判断标准（来自跟 Codex 的讨论）**：

> 能每帧重复执行且结果幂等的放 snapshot；重复执行会创建节点、启动 tween、播音效、发粒子的放 event。

### 落地形态

```
RenderWorld
├── actor_state_changed(id, state)   ← State snapshot (continuous)
│                                       hp / flash / tint / position
└── actor_died(id)                   ← Event (transition-only)
                                       was_alive && now_dead 那帧 emit 一次
                                       (未来可加 actor_revived / actor_damaged 等同形态)

BattleAnimator
├── _on_actor_state_changed → view.update_state(state)   ← state sync
└── _on_actor_died          → view.play_death()          ← event trigger
└── reset()                 → for view: view.revive()    ← session control(非 event)

UnitView
├── update_state(state)  ← 纯 state sync(hp / flash / tint),不触发任何 tween
├── play_death()         ← once 策略,内部 _death_played flag 挡重入
└── revive()             ← reset/replay 复活,清 flag + visible/scale
```

## 关键约定（写进代码注释，长期遵守）

> **Director / Animator 只负责转发 event；重复触发时 ignore / retrigger / queue 由具体 view 方法定义。**

每个一次性动画 view 公共方法显式声明触发策略：

| 策略 | 语义 | 实现 | 适用 |
|---|---|---|---|
| **once** | 已播过就忽略后续 | view 内 `_xxx_played` flag | 死亡（只死一次）/ 复活 |
| **retrigger** | 已在播也强制 kill 旧 tween 从头播 | `_xxx_tween.kill()` + 新建 | 受击抖动 / 闪白 / 暴击大字 |
| **queue** | 排队顺序播完 | view 内 tween chain | 暂未需要 |

策略写在 view 方法体内，**Animator 一律 wire event signal，不关心策略**。

## 收紧 `actor_died` 语义

`RenderWorld.actor_died` 之前两处 emit：

| 位置 | 语义 | 修后 |
|---|---|---|
| `_apply_death_action`（progress >= 1.0） | 死亡动画完成态通知 | 删直接 emit，走 `_set_actor_alive` 内的 transition guard |
| `set_actor_dead` | 强制设态 | 同上 |
| `set_actor_hp`（hp ≤ 0 时） | 间接翻转 | 同上 |

新增 helper `_set_actor_alive(actor, alive)`：
- 收口所有 `is_alive` 写入
- `was_alive && not alive` 那一刻 emit 一次 `actor_died`
- 重复设 false / 设回 true 不再触发

→ `actor_died` 现在是 **transition-only event**，下游 wire 干净。

## Reset 复活：走 Animator Y 路径，不走 Director event

战斗内复活（如复活技能）和 reset/replay 复活是**两类语义**：

- 战斗内复活：未来若加复活技能，`RenderWorld` emit `actor_revived(id)`（同样 transition-only：`was_dead && now_alive`），Animator wire → `view.revive()`
- Reset / Replay 复活：playback session control，**不是战斗事件**。Animator 自己持有 `_unit_views`，`reset()` 内遍历调 `view.revive()`

Director 信号集合保持精简，session control 不污染战斗事件总线。

## 未来扩展：受击事件命名建议

Codex 建议：未来加受击事件时，**用 `actor_damaged(actor_id, amount, source_id, is_critical)` 而不是 `actor_hurt`**。

理由：「hp 下降」不一定等于要播同一种受击动画，DOT / 自伤 / 反伤 / 护盾吸收 / 暴击都可能需要不同表现。Event 携带必要 metadata 让 view 自己分支，比"按事件类型分成 N 个 signal"更可扩展。

`view.play_damaged(amount, is_critical)` 对应 retrigger 策略：每次 kill 旧 tween 后从头播。

## 实现细节摘要

### `RenderWorld._set_actor_alive`

```gdscript
func _set_actor_alive(actor: FrontendActorRenderState, alive: bool) -> void:
    var was_alive := actor.is_alive
    actor.is_alive = alive
    if was_alive and not alive:
        actor_died.emit(actor.id)
```

3 处改动统一走这个 helper：`_apply_death_action` / `set_actor_hp` / `set_actor_dead`。删两处直接 `actor_died.emit`。

### `BattleAnimator._on_actor_died`

```gdscript
func _on_actor_died(actor_id: String) -> void:
    if not _unit_views.has(actor_id):
        return
    var view: FrontendUnitView = _unit_views[actor_id]
    if is_instance_valid(view):
        view.play_death()
```

### `BattleAnimator.reset`

```gdscript
func reset() -> void:
    if _director != null:
        _director.reset()
    _clear_effects()
    for view in _unit_views.values():
        if is_instance_valid(view):
            view.revive()
```

### `UnitView.play_death` / `revive`

```gdscript
func play_death() -> void:
    if _death_played:
        return
    _death_played = true
    _death_tween = create_tween()
    _death_tween.tween_property(self, "scale", Vector3(0.1, 0.1, 0.1), 0.5)
    _death_tween.parallel().tween_property(self, "position:y", position.y - 0.5, 0.5)
    _death_tween.tween_callback(_on_death_animation_finished)


func revive() -> void:
    if _death_tween != null and _death_tween.is_valid():
        _death_tween.kill()
    visible = true
    scale = Vector3.ONE
    _death_played = false
```

`update_state` 删 `was_dead` 推断、删死亡分支、删 `_revive_visual_state`，只留 hp / flash / tint sync。

## 验证

| 测试 | 结果 |
|---|---|
| LGF run_tests | 59/59 ✅ |
| smoke_skill_preview_reactive（3 场连续 + reset 归 0） | PASS |
| smoke_frontend_main | PASS（139 frames，6 views） |
| smoke_world_view（bind + remove + animation） | PASS |
| smoke_skill_scenarios | 12/12 ✅ |

用户场景手验：F6 main.tscn → 普攻 + 亡语双击致死 → 死亡动画只播一次 ✅；按 Reset → 死掉的棋子回到初始态 ✅。

## 方法论总结（架构 KB 候选）

1. **Event vs State 是表演层的根边界**。Snapshot 同步只管"可覆盖事实"，一次性动画必须走独立 event signal。
2. **Transition-only event 是 emit 端的契约**，不是消费端的责任。emit 端用 prev-state 对比保证一次只 emit 一次，下游 wire 不需要做幂等。
3. **触发策略是 view 方法的本地决定**，不污染 event bus。once / retrigger / queue 在 view 公共方法体内体现，Animator 平行转发。
4. **Session control（reset / replay）走 Animator 自己的 wire，不污染 Director event bus**。战斗内复活（未来）才走 `actor_revived` event。
5. **Patch 累积是 false economy 的信号**：当第二次 patch 形态相似（`_xxx_played` flag），就该评估是不是边界没立住。

## 遗留

- `actor_revived` event：未来真有战斗内复活技能时再加，同样 transition-only（`was_dead && now_alive`）
- `actor_damaged(id, amount, source_id, is_critical)` event：未来受击表现需要时落地，view 端 retrigger 策略
- 暴击大字 / 治疗光环 / buff proc 等：套用同模板（Director emit transition event → Animator wire → view 公共方法 + 显式策略）

---

## 2026-04-26 补章：血条迁移到 state（贯彻边界）

### 背景

本文档主体落地了 **death animation** 的 event/state 拆分（`actor_died` transition-only event + view once 策略），但 `damage` / `heal` 这一支没跟着迁——`damage_visualizer.gd` 仍生成 `FrontendUpdateHPAction(from_hp, to_hp, duration)`，走 `ActionScheduler` 并行 lerp。第 27 行表格里"hp 条高度"明确归在 State 一列，**代码却在走 Event 路径**。

### Bug 现象（用户报告）

> 血条动画 bug：多次伤害，不是从当前进度继续变化。

两种典型场景：

1. **同帧多次伤害**：`damage_visualizer.translate()` 取 `context.get_actor_hp()`（= `visual_hp`），同一逻辑帧的多个 damage event 依次 translate 时 visual_hp 还没被 tick 推进，两次都拿到同一起点，生成 `(100→80)` 和 `(100→60)`，并行 lerp 互相覆盖 → 视觉直接跳。
2. **跨帧但旧动画未完**：第二次 translate 拿到中间值 90，新 action `(90→70)` 没问题，但旧 action `(100→80)` 还在跑，每帧把 visual_hp 拉回 lerp(100,80,p) → 两条曲线打架。

根因是**两个并行的 UpdateHPAction 同时写 visual_hp**——README 的"全部并行"策略对持续 lerp action 没有互斥保证，而血条天然是单一连续值的跟踪问题。

### 决策：把血条彻底从 Event 路径搬到 State 路径

按本文档第 27 行表格的分类落地。引入 `target_hp` 作为 RenderWorld 的状态字段：

```
ActorRenderState
├── visual_hp        ← View 实际显示值,每 tick 朝 target_hp 收敛 lerp
└── target_hp        ← damage / heal event apply 后立即累到此处
```

伤害/治疗事件不再生成"持续 lerp action"，而是生成**瞬时指令** `FrontendApplyHPDeltaAction(actor_id, delta, delay)`：

- duration=0,delay 结束当帧 progress=1 立即完成
- apply 时 `actor.target_hp = clamp(target_hp + delta, 0, max_hp)`,`_set_actor_alive` 收口（target ≤ 0 那一帧 emit `actor_died`，跟原 transition guard 完全一致）

`RenderWorld.tick_hp_lerp(delta_ms)` 在 `BattleDirector._tick` 末尾每帧调一次，与 ActionScheduler 解耦：

```gdscript
func tick_hp_lerp(delta_ms: float) -> void:
    var dt: float = delta_ms / 1000.0
    var rate: float = _animation_config.hp_lerp_rate  # 默认 8.0 / s
    var t: float = 1.0 - exp(-rate * dt) if rate > 0.0 else 1.0
    for actor_id in _actors.keys():
        var actor: FrontendActorRenderState = _actors[actor_id]
        if is_equal_approx(actor.visual_hp, actor.target_hp):
            continue
        var diff := actor.target_hp - actor.visual_hp
        if absf(diff) < 0.5:
            actor.visual_hp = actor.target_hp
        else:
            actor.visual_hp += diff * t
        _dirty_actors[actor_id] = true
```

指数衰减 `1 - exp(-rate*dt)` 跟原"线性 lerp 300ms"在主观感知上接近，但天然处理「目标变更」——多次伤害进来只是把 target_hp 拉得更低，visual_hp 始终从当前位置追赶，**不需要 action 互斥也不会跳变**。

### 落地范围

| 文件 | 改动 |
|---|---|
| `actions/visual_action.gd` | 枚举 `UPDATE_HP` → `APPLY_HP_DELTA` |
| `actions/apply_hp_delta_action.gd` | 新建（替代 `update_hp_action.gd`，后者删除） |
| `core/actor_render_state.gd` | 加 `target_hp` 字段 |
| `core/render_world.gd` | 删 `_apply_update_hp_action`；加 `_apply_apply_hp_delta_action` + `tick_hp_lerp`；`set_actor_hp` / `set_actor_dead` / `_apply_death_action` 同步 `target_hp` |
| `core/battle_director.gd` | `_tick` 末尾调 `_world.tick_hp_lerp(delta_ms)` |
| `core/animation_config.gd` | 加 `hp_lerp_rate: float = 8.0`；删 `damage_hp_bar_duration` / `heal_hp_bar_duration`（duration 概念在 state 路径下不存在） |
| `visualizers/damage_visualizer.gd` | 生成 `FrontendApplyHPDeltaAction(target_id, -actual_life_damage, hp_bar_delay)` |
| `visualizers/heal_visualizer.gd` | 生成 `FrontendApplyHPDeltaAction(target_id, +heal_amount)` |
| `example/hex-atb-battle-frontend/README.md` | 更新 ActionType 枚举、damage 生命周期例子、目录结构 |

### 方法论补充（架构 KB 候选）

6. **「持续值跟踪」是 State 路径的本质特征**——任何场景下「单一连续浮点 + 来自上游的瞬时变更指令 + 视觉平滑追赶」都应该是 state，不是 event。位置(`_target_position` lerp)是这个范式的先驱，血条只是迁过来而已。判断标准：「这个值在任何时刻都有"当前正确目标"吗？」如果是，就是 state。
7. **Action.duration 的存在不必然代表持续 lerp**——Action 可以是「瞬时指令 + 仅 delay 用于节奏控制」（`ApplyHPDelta` 就是 duration=0 + delay=200ms）。这样既能复用 ActionScheduler 的延迟机制提供"飘字先飞、扣血后跟"的节奏感，又不进入并行 lerp 写状态的反模式。
8. **本文档主体（death）和补章（hp）的差异是教训本身**——立完边界要一次性贯彻所有同形态 case，否则会在不同时间点被同样的 bug 二次暴露。Patch 累积是边界没立住的信号；**边界立完贯彻不彻底，是边界立得不够明确的信号**。
