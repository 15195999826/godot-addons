# View ↔ Logic 终态对账系统

战斗结束后跑一次 oracle, 比对**逻辑层 actor 终态**与**表演层 view 终态**. 任一字段不一致 → 报告 mismatch (`actor_id` + `field` + 详情). 用来抓"漏 visualizer / visualizer 翻译错"这类**漂移类**回归.

**不**抓: 动画过程中是否流畅、特效粒子参数对不对、单帧渲染像素对不对. 这是 end-state oracle, 不是 frame-perfect 校验.

---

## 背景: 为什么要做这件事

逻辑层 (Action / event_processor) 改 actor 状态, 通过 events 进入 timeline; 表演层 visualizer 翻译 events 成 visual actions, 由 director 维护 `FrontendActorRenderState` 喂给 view. 任何**新 event 没人接** / **接了但翻错**, view 终态就和 logic 终态漂开.

具体触发本系统的事件: 击退机制 (Tier 1 #4 KnockbackPunch) 的 `ActorDisplacedEvent` 没有对应 visualizer, logic 层正确改了 `actor.hex_position`, view 仍渲染在原位. 现有回归网漏掉了:
- Logic smoke 只断言 events / hp / hex_position
- Frontend smoke 只断言不崩 + view 实例化
- 中间层"view 渲染态 == logic 终态"无人验证

oracle 不绑某个 ability — 只要某场战斗跑过, 终态对账自然能抓到所有此类漂移.

---

## 架构

### 双源对账模型

```
logic side  =  HexWorldGameplayInstance.battle_final_state_ready(final_state)
                  └─ snapshot 来自 HexBattleActor.get_*_snapshot()
view side   =  FrontendBattleAnimator.get_actors_snapshot()        ← visual_hp / max_hp / is_alive / buffs / shields
            +  FrontendWorldView.get_unit_view(id).global_position ← 实际渲染位置
```

逻辑层是 ground truth. 不一致一律视为表演层漂.

### 时序

```
Logic tick 末尾                                   View / Animator
─────────────────                                  ──────────────
WorldGI.tick: battle_finished.emit(timeline)
  ├─ HexWorldGI._emit_final_state_if_debug          [demo._on_battle_finished]
  │    (debug only)                                  ├─ animator.load(timeline, unit_views)
  │    └─ battle_final_state_ready.emit(final_state) │
  │         └─ smoke / oracle 缓存到 _final_state    └─ user / smoke 触发 animator.play()
  └─ demo._on_battle_finished                                          │
       (子类后跑, 此时 final_state 已发送)                              │
                                                                       ▼
                                                        animator playback ... 数百帧
                                                                       │
                                                                       ▼
                                                         playback_ended signal
                                                                       │
                                                                       ▼
                                                         oracle.reconcile(final_state, ...)
                                                           ├─ settle loop (view 位置 lerp 收敛)
                                                           └─ 字段 diff → ReconcileReport
```

**connect 顺序保证**: `HexWorldGameplayInstance._init` 在 `super._init` 之后立刻 connect `_emit_final_state_if_debug`, 子类 (`HexDemoWorldGameplayInstance` / `SkillPreviewWorldGI`) 在 super 调用返回后才 connect 自己的 handler. emit 时按 connect 顺序同步执行 → base handler 先 fire → snapshot 在子类 `end()` / `_save_replay` 之前抓取, 数据干净.

### 数据契约 (final_state schema)

```gdscript
{
  "actors": {
    "<actor_id>": {
      "id":           String,
      "type":         String,        # "Character" / "Environment"
      "is_dead":      bool,
      "hex_position": Dictionary,    # {q, r}; 未放置时 {}
      "attribute":    Dictionary,    # 子类 get_attribute_snapshot() 决定字段
                                     #   character: {hp, max_hp, atk, def, speed}
                                     #   environment: {hp, max_hp}
      "abilities":    Array[Dictionary],  # [{instance_id, config_id}, ...]
      "tags":         Dictionary,    # ability_set.tag_container 全量
    }
  }
}
```

字段集来源 = `HexBattleActor.get_attribute_snapshot()` + `get_ability_snapshot()` + `get_tag_snapshot()`. 不用 `serialize()` (那是录像格式, 字段未必和 view 对齐).

---

## 字段对账契约

**当前覆盖** (本轮范围):

| 字段 | logic source | view source | 容差 | 死者 |
|---|---|---|---|---|
| `position` | `actors[id].hex_position` → `world_view.hex_to_world(coord)` | `world_view.get_unit_view(id).global_position` | `length < 0.01` (settle 后) | **跳过** |
| `is_alive` | `not actors[id].is_dead` | `animator.get_actors_snapshot()[id].is_alive` | 严格相等 | 查 |
| `hp` | `actors[id].attribute.hp` | `view_state.visual_hp` | `abs < 0.5` (settle 后) | 查 |
| `max_hp` | `actors[id].attribute.max_hp` | `view_state.max_hp` | `abs < 0.5` | 查 |

**presence**: 若 logic 有 actor 但 view 没 RenderState → 单独报 `presence` mismatch.

**未覆盖** (扩展点, 见下文):
- `buffs` / `shields` 列表对账 (需先解耦 BuffVisualizer 白名单)
- `atk` / `def` / `speed` (不参与可视化, 无 view 端字段)
- `tags` (双方都有但形态不同, 未来如有 tag 驱动的 view 元素再加)

---

## 死者特殊处理 (重要)

**简短规则**: 死者**只**跳 `position` 字段, 其余字段照查.

### 为什么跳 position

`FrontendUnitView.play_death()` ([unit_view.gd](../frontend/scene/unit_view.gd)) 跑 0.5s tween:
- `scale → (0.1, 0.1, 0.1)`
- `position.y -= 0.5`

这是**纯视觉装饰**, logic 端不知道、不会发任何事件去校正. tween 跑完后再设 `visible = false`. 因此死者 view 的 `global_position` 永远会和 `logic.hex_position` 投影差 ~0.5m, 这不是 bug.

### 为什么 buff / hp / is_alive 照查

**logic 侧**: 死亡时**没有**主动清理 buff/shield 的代码. `HexBattleActor` 没死亡 hook, `CharacterActor` / `EnvironmentActor` 也没. 死者的 `ability_set` 上 buff abilities (Poison/Surge/Ward 等) 仍在, stacks/shield 不动.

**view 侧**: `FrontendBuffVisualizer` REMOVE op 只在 `ABILITY_REMOVED_EVENT` 触发, 不主动因 `death` event 清 BuffSummary. 所以死者 view 也保留 buff_row.

→ 双方对称, 死者 buff 自然对得上, **不需要特判**.

### 为什么 hp 仍要查

死者 hp 应该 ≤ 0, view 侧 `visual_hp` 经 lerp 收敛到 target_hp 也应该到 0. 如果有人在 visualizer / damage 翻译里把死亡那刻的最终扣血写错, 死者 hp 对账能抓到.

### 为什么 is_alive 严格查

二者对账抓的是 "death event 没翻 / 翻错"——比如 visualizer 漏接 `death` 但 logic 已 dead, view 仍 `is_alive=true`. 严格相等不容差.

### Edge: post-death buff tick

`HexBattleActor.is_pre_event_responsive() = not _is_dead` ([hex_battle_actor.gd:56](../logic/hex_battle_actor.gd)) 决定死者**不响应** PreEvent handler. Poison / Vitality 这类 tick 在死者身上停止. 不是被动 expire — buff 仍挂着, stacks 冻结. 双方依然对称.

→ 唯一需要警惕的: **如果未来加了"死亡时主动 expire 某 buff"的 ability** (例如某个 buff 设计 = "死亡时移除"), 必须同时让 BuffVisualizer 接住对应 ABILITY_REMOVED, 否则双方不对称, oracle 会抓出来. 这是 oracle 帮你提醒的设计完整性, 不是要回避它.

---

## Settle loop

**问题**: animator `playback_ended` 时, director scheduler 已空, 但 `FrontendUnitView._process` 仍每帧 `position.lerp(_target_position, delta * 15.0)`. 直接读 `unit_view.global_position` 拿不到收敛值, 会被报"position drift" 假阳性.

**方案**: oracle 启动 settle loop, 每帧算 max alive position drift, 收敛到 `< position_epsilon` 即跳出; 否则等到 `settle_timeout_sec` (默认 1.0s) 上限再退出 (后续 position diff 自然报 fail).

```gdscript
while true:
    max_drift = _max_alive_drift(...)
    if max_drift < position_epsilon: break
    if Time.get_ticks_msec() >= deadline_ms: break
    await tree.process_frame
```

Settle 只针对 alive — 死者 view 永远不会收敛 (play_death 改 transform), 等也是浪费, 直接跳过.

---

## Debug-only protocol

`HexWorldGameplayInstance._emit_final_state_if_debug` 用 `OS.has_feature("debug")` gate:
- **debug build / 编辑器 / headless smoke**: emit final_state, oracle 工作
- **release build / web export 给玩家**: signal 不 emit, snapshot 不算, **零开销**

oracle `reconcile()` 收到空 `final_state` → 返回 `ReconcileReport` 标 `skipped: true`, 调方根据约定决定:
- smoke 路径: skipped 视作 PASS (不会因 release 跑 smoke 而 false fail)
- 交互场景 (skill-preview): skipped 静默 (release 包就是不该有对账)

---

## 接入新 smoke 的步骤清单

1. 在 smoke `_ready` 处缓存 oracle 用的 reference:
   ```gdscript
   var _final_state: Dictionary = {}
   _battle.battle_final_state_ready.connect(func(state: Dictionary) -> void:
       _final_state = state
   )
   ```
2. animator `playback_ended` handler 末尾跑 reconciler:
   ```gdscript
   var rec := HexBattleViewLogicReconciler.new()
   var report := await rec.reconcile(_final_state, _animator, _world_view, get_tree())
   if not report.passed and not report.skipped:
       _fail(report.to_human_string())
   ```
3. 失败方式:
   - smoke headless 路径: `_fail` → exit 1
   - 交互场景 (skill-preview): `push_warning` + UI hint, 不退出 (用户日常 F6 一眼能看到, 不阻塞操作)
4. release 包跑该 smoke 时, `_final_state` 始终空 → reconciler skipped → smoke 继续走原 PASS 路径

---

## 扩展点 (follow-up, 不在本轮范围)

### Buff / Shield 列表对账
当前不查. 需先把 `FrontendBuffVisualizer.BUFF_REGISTRY` ([buff_visualizer.gd:27](../frontend/visualizers/buff_visualizer.gd)) 的白名单从 visualizer 内部抽出来, 让 oracle 能问"哪些 ability config_id 应该出现在 buffs[]"—— 否则 oracle 不知道该期望多少个 BuffSummary, 容易误报.

最小做法: 单向检查 — view 显示出来的每个 `BuffSummary.id` 在 logic `actors[id].abilities` 里能找到对应 `instance_id`; 反向 (logic 有 ability 但 view 没显示) 不查 (可能是不显示的 buff).

### `tags` 对账
两端字段形态不一: logic `tag_container` 是 `{tag_id: stacks}`, view 没等价字段 (tag 驱动的 view 元素如 `flash_progress` / `tint_color` 是派生量). 暂不做.

### ATB / mp / 自定义 attribute
view 当前不显示这些 — `FrontendActorRenderState` 不持. 若未来加 ATB 进度条, 同步加对账.

### 推广到其它 example
当前 hex-atb-battle 特化. RTS (rts-auto-battle) 用实时连续坐标 + 自研 grid, 没有 hex 投影概念, 同款 oracle 要用 `Vector2 (x, z)` 直接对账, 复用 `Reconciler` 思路但不复用代码.

---

## 目录速查

| 关注 | 路径 |
|---|---|
| signal 定义 + handler | [`core/hex_world_gameplay_instance.gd`](../core/hex_world_gameplay_instance.gd) `battle_final_state_ready` / `_emit_final_state_if_debug` / `_build_final_state_snapshot` |
| reconciler 主体 | [`tests/frontend/view_logic_reconciler.gd`](../tests/frontend/view_logic_reconciler.gd) |
| 接入示例 (headless smoke) | [`tests/frontend/smoke_frontend_main.gd`](../tests/frontend/smoke_frontend_main.gd) |
| 接入示例 (交互场景) | [`skill-preview/skill_preview.gd`](../skill-preview/skill_preview.gd) (待 Phase 4 加) |
| view 派生数据来源 | [`frontend/core/actor_render_state.gd`](../frontend/core/actor_render_state.gd) (`FrontendActorRenderState`) |
| view 位置投影 | [`frontend/world_view.gd`](../frontend/world_view.gd) (`hex_to_world`) |

---

## 设计原则总结

1. **logic 是 ground truth** — view 漂就是 view 错, oracle 不容许 view 端的"看上去对就行"
2. **end-state only** — 不查动画中间帧, 不污染 production code path
3. **debug-only emit** — release 包零开销, 不让对账系统污染线上路径
4. **不引入框架级抽象** — 当前在 hex-atb-battle 示例内, 框架不知道有这事, 别的 example 自己决定要不要做
5. **不 short-circuit diff** — 一次对账报全部 mismatch, 调方一次看清全景, 不需要反复跑
6. **死者跳位置但保其他** — 视觉装饰是装饰 (跳), 状态是状态 (查), 二者不混
