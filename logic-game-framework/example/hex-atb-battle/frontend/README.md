# Hex ATB Battle Frontend (表演层)

> ⚠ **2026-04-26 — A 层老路径下线**:`FrontendBattleReplayScene.load_replay(record)` destructive 路径已删除。当前权威 wire 示例见 `main.gd::_on_start_battle_button_pressed`(响应式 `WorldView + BattleAnimator`)与 `example/hex-atb-battle/skill-preview/skill_preview.gd::_init_world_stack`。详见 `addons/logic-game-framework/CLAUDE.md`（World owns Battle 节）。

## 现状响应式 wire(2026-04-26 起)

```gdscript
# main.gd 简化版,完整版见 main.gd 源码
GameWorld.shutdown()                          # 清空 instance 注册表(退出时再调一次)

_world_view = FrontendWorldView.new()
add_child(_world_view)

_animator = FrontendBattleAnimator.new()
add_child(_animator)
_animator.playback_ended.connect(_on_playback_ended)

# 用户按 Start Battle:
_battle = HexBattle.new()
GameWorld.create_instance(_battle)            # 注册后再 start
_battle.battle_finished.connect(func(timeline: Dictionary) -> void:
    _animator.play(timeline, _world_view.get_unit_views())
)
_world_view.bind_world(_battle)               # 先 bind, add_actor signal 触发 view spawn
_battle.start({"map_config": map_config, "recording": true})
while GameWorld.has_running_instances():
    GameWorld.tick_all(100.0)                 # 同步跑完 → battle_finished → animator.play
```

UI 控件 `FrontendPlaybackControls` 提供 play/pause/reset/speed,信号转发到 `_animator.resume() / pause() / reset() / set_speed()`。

## 随机技能 Demo

- 场景入口: `frontend/demo_random_frontend.tscn`
- 目的: 不改 `demo_frontend.tscn` 测试基线, 复用相同 `WorldView + BattleAnimator` wire, 但用 `HexRandomDemoWorldGameplayInstance` 随机组装职业、主技能和额外 passive, 跑一场完整 production battle。
- UI 参数: `Seed (0=random)` / `Extra Passives`。随机战斗固定 3v3; 固定 seed 可复现同一组 loadout, seed 为 0 时每次 Start 生成新 seed。单位显示名使用 `左方 1` / `右方 1` 这类中性编号, 不暴露底层数值模板名称。
- Smoke: `./tools/run_tests.ps1 hex/random-frontend`

## 项目背景

本项目是 **inkmon** 战斗系统的 **Godot 3D 表演层**实现，用于将逻辑层产生的战斗事件可视化为 3D 动画。

### 设计目标

1. **逻辑表演分离**：逻辑层 (`hex-atb-battle`) 只负责计算，表演层只负责渲染
2. **声明式动画**：通过 `VisualAction` 描述"做什么"，而非"怎么做"
3. **可回放**：支持战斗录像的加载、播放、暂停、重置
4. **跨平台一致**：与 Web 端 (`inkmon-web/lib/battle-replay`) 保持架构一致

### 相关项目

| 项目 | 路径 | 说明 |
|------|------|------|
| **逻辑层** | `addons/logic-game-framework/example/hex-atb-battle/logic/` | 战斗逻辑计算、事件生成 |
| **Web 表演层** | `../inkmon-web/lib/battle-replay/` | TypeScript 实现的参考架构 |
| **本项目** | `hex-atb-battle/frontend/` | Godot 3D 表演层 |

---

## 框架设计

### 核心思路：录像回放驱动的声明式动画管线

表演层不实时响应逻辑层，而是消费逻辑层产出的**录像数据**（timeline of events），
通过四层管线将事件翻译为 3D 动画：

```
录像数据 --> 翻译层 --> 调度层 --> 状态层 --> 渲染层
```

### 四层管线架构

**1. 翻译层（Translator）** -- 事件到卡片的纯函数映射（框架件 `Translator` / `TranslatorRegistry`，住 LGF `presentation/`）

- `Translator` 定义 `can_handle()` + `translate()` 接口
- 每个翻译员是纯函数：只读 `VisualStateQuery`，不修改状态，返回声明式 `VisualAction[]`
- `TranslatorRegistry` 支持多对多：一个事件可被多个翻译员处理
  （如 damage 同时触发飘字 + 闪白 + 血条）
- hex 通过 `FrontendDefaultRegistry` 工厂统一注册 12 个 `Frontend*Translator`，用户可自由扩展

**2. 步进层（ActionStepper）** -- 时序管理（框架件）

- 所有 Action 入队后并行执行（非阻塞队列）
- 每个 Action 有 `delay`（延迟启动）和 `duration`（持续时间）
- `tick(delta_ms)` 推进所有活跃 Action 的进度（0->1），返回 `TickResult`
- 职责单一：只管"什么时候执行到什么进度"，不管"执行什么"（那是 VisualUpdater 的事）

**3. 账本 + 更新器（VisualState + VisualUpdater）** -- 状态（框架件）

- `VisualUpdater.apply_actions(state, active)` 接收 `TickResult`，按 `action.kind` 查 handler 表把卡片 × 进度记到 `VisualState`（位置、HP、一次性效果等）；内置 11 种 kind，项目私有卡片 `register_handler(kind, callable)`（hex 的 cone debug overlay 就是范例）
- `VisualUpdater.apply_event` 处理 actor_spawned / actor_destroyed / max_hp 这类事件直改，`tick_time` 做到期效果清理 + `visual_hp` 追赶
- `VisualState` 维护脏标记（`_dirty_actors`），批量触发信号，避免每帧频繁 emit；`as_query()` 给翻译员只读视图

**4. 渲染层（FrontendBattleAnimator + Views）** -- 信号驱动的 3D 场景（项目件）

- 监听 Director 转发的 7 条信号（`actor_state_changed` / `actor_spawned` / `actor_died` / `actor_despawned` + `effect_spawned` / `effect_updated` / `effect_removed`），一次性效果按 kind 分发到各 view
- `UnitView` 接收 `ActorVisualState`，更新网格颜色/血条/位置
- 特效（飘字、攻击 VFX、投射物）通过 spawn/update/remove 三段式生命周期管理

### 关键设计决策

| 决策 | 选择 | 原因 |
|------|------|------|
| 数据驱动 vs 命令式 | VisualAction 是纯数据对象，不持有 Node | 逻辑与渲染解耦，支持序列化/回放 |
| 并行 vs 串行动画 | 全部并行，通过 delay 控制时序 | 简化调度器，避免复杂的队列/阻塞逻辑 |
| 信号 vs 直接调用 | Director -> Scene 通过信号 | 层间松耦合，Scene 可替换 |
| 帧驱动 vs 事件驱动 | 逻辑帧累积器 + 动画 tick 分离 | 逻辑帧结束后动画可继续播放至完成 |
| 状态管理 | VisualState 集中管理，View 只读 | 单一数据源，避免状态不一致 |
| 跨平台 | 与 Web 端 TypeScript 实现保持 1:1 架构对应 | 两端行为一致，便于维护 |

### 扩展机制

扩展一种新的战斗表演只需 3 步：

1. **新建卡片子类**（如 `FrontendConeDebugOverlayAction extends VisualAction`，自定义 `kind`）-- 声明数据
2. **新建翻译员**（如 `FrontendProjectileTranslator extends Translator`）-- 翻译逻辑
3. **给卡片写记账函数并登记**（`static func apply(state, action, progress, id)` + `updater.register_handler(kind, apply)`）-- 状态应用；复用内置 11 种卡片时跳过这步

`FrontendDefaultRegistry.create()` 注册新翻译员即可生效，无需修改 Director 或 ActionStepper。

---

## 流程图

> ⚠ 阶段一为**历史示意**（`FrontendBattleReplayScene` / `HexBattle` 已删除，现行入口是响应式 wire + `FrontendBattleAnimator.load(record_data, unit_views)` → `play()`，见顶部）；阶段二/三描述的 Director → VisualUpdater / VisualState → view 播放机制仍是现行实现。

### 阶段一：加载录像

```
main.gd: _on_start_battle_button_pressed()
  |
  +-- _run_logic_battle(map_config)              <-- 同步跑完逻辑层战斗
  |     +-- GameWorld.create_instance(HexBattle)
  |     +-- loop: GameWorld.tick_all(100ms)       <-- 逐帧推进直到结束
  |     +-- return _battle.get_replay_data()      <-- Dictionary
  |
  v
ReplayData.BattleRecord.from_dict(replay_data)   <-- 解析为类型化结构体
  |
  v
_replay_scene.load_replay(record)                 <-- FrontendBattleReplayScene
  |
  +--[1] _director.load_playback(record)          <-- ReplayDirector（框架件）
  |    +-- 构建 _frame_data_map: { frame_number -> FrameData }
  |    +-- _state.initialize_from_replay(record)  <-- VisualState
  |    |     +-- 遍历 initialActors -> 每个 actor 一条 ActorVisualState
  |    |     |     { id, position(逻辑 Vector2), visual_hp, max_hp, is_alive,
  |    |     |       flash_progress, tint_color }
  |    |     +-- emit actor_state_changed() 给每个 actor（初始同步）
  |    +-- _analyze_event_coverage()              <-- 打印事件覆盖摘要
  |    +-- 重置: _current_frame=0, _accumulator=0
  |
  +--[2] _setup_hex_grid_from_replay(record)      <-- 创建六边形网格
  |    +-- GridMapModel.initialize(grid_config)
  |    +-- GridMapRenderer3D.render_grid()
  |
  +--[3] _spawn_units(record)                     <-- 创建 3D 单位
  |    +-- 遍历 initialActors:
  |          +-- FrontendUnitView.new()
  |          +-- unit_view.initialize(id, name, team, maxHp, hp)
  |          |     +-- 创建 SphereMesh + StandardMaterial3D
  |          |     +-- 创建 HPBar (BoxMesh)
  |          |     +-- 创建 Label3D (名称)
  |          +-- unit_view.set_world_position(hex -> world 坐标)
  |
  +--[4] _clear_effects()                         <-- 清理旧特效
```

### 阶段二：每帧播放循环（_process 驱动）

```
Godot Engine _process(delta)
  |
  v
ReplayDirector._process(delta)                       <-- 框架件（帧时钟）
  +-- _advance(delta * 1000 * _speed)
      |
      |  STEP 1: 帧时钟——攒 delta，每满一帧收下那帧的事件
      |  ================================================
      |  _accumulator += delta_ms
      |
      |  while _accumulator >= tick_ms（录像 meta.tick_interval，缺省 100）:
      |      _accumulator -= tick_ms
      |      _current_frame++
      |      events += _frame_data_map[current_frame].events
      |      emit frame_changed(current, total)
      |
      |  VisualDirector.pump(delta_ms, events)          <-- 共享 tick 体（live 项目自己攒事件调它）
      |      遍历本趟 events:
      |
      |          updater.apply_event(_state, event)
      |            事件直改: actor_spawned / actor_destroyed / max_hp 先落账本
      |
      |          query = _state.as_query()
      |            只读视图:
      |            - actors 状态
      |            - interpolated_positions
      |            - animation_config
      |
      |          actions = _registry.translate(event, query)
      |            遍历所有翻译员:
      |            +-- t.can_handle(event)?
      |            +-- t.translate(event, query)
      |                -> Array[VisualAction]
      |
      |          _stepper.enqueue(actions)
      |            -> 每个 action 包装为 ActiveAction
      |               { id, action, elapsed=0, progress=0 }
      |
      |  STEP 2: 推进账本时间
      |  ================================================
      |  _state.advance_time(delta_ms)
      |
      |  STEP 3: 步进器 tick（推进所有动画进度）
      |  ================================================
      |  result = _stepper.tick(delta_ms)
      |
      |    遍历所有 _active actions:
      |    +-- elapsed += delta_ms
      |    +-- if elapsed < delay -> 仍在等待
      |    +-- effective = elapsed - delay
      |    +-- progress = min(1.0, effective / duration)
      |    +-- if effective >= duration -> 标记完成
      |
      |    -> TickResult {
      |         active_actions:      还在播放的动作（带进度）
      |         completed_this_tick: 本帧刚完成的动作
      |         has_changes:         是否有任何变化
      |       }
      |
      |  STEP 4: 记账（if has_changes）
      |  ================================================
      |  updater.apply_actions(_state, result.active_actions)
      |  updater.apply_actions(_state, result.completed_this_tick)
      |
      |    对每个 ActiveAction, 按 action.kind 查 handler:
      |
      |    move:
      |      interpolated_pos = action.get_interpolated_position(progress)
      |      state.set_interpolated_position(actor_id, pos)
      |      if progress>=1: actor.position = to_position
      |
      |    hp_delta:                                    <-- 瞬时指令(state 路径)
      |      actor.target_hp = clamp(target_hp + delta, 0, max)
      |      _set_actor_alive(...)
      |      progress=1 立即完成,visual_hp 不在这里改
      |      state.mark_dirty(actor_id)
      |      (visual_hp 由 VisualUpdater.tick_time 每帧收敛,
      |       见 ../README.md#event-vs-state「事件 vs 状态边界」)
      |
      |    floating_text:
      |      首次: state.spawn_effect(&"floating_text", payload)
      |            -> emit effect_spawned(kind, payload)；到期账本静默忘记
      |
      |    procedural_vfx:
      |      HIT_FLASH: actor.flash_progress = f(progress)
      |      SHAKE:     state.set_screen_shake(offset(progress))
      |      COLOR_TINT: actor.tint_color = color
      |
      |    death:
      |      actor.is_alive=false, hp=0 (transition 那帧 emit actor_died)
      |
      |    attack_vfx:
      |      首次: spawn_effect -> emit effect_spawned(&"attack_vfx", payload)
      |      每帧: payload.scale_factor / alpha 更新 -> emit effect_updated(kind, id, progress, payload)
      |      完成: remove_effect -> emit effect_removed(kind, id)
      |
      |    projectile:
      |      首次: emit effect_spawned(&"projectile", payload)
      |      每帧: payload.position 更新 -> emit effect_updated   # position 是逻辑平面 axial
      |      完成: emit effect_removed
      |
      |    cone_debug_overlay (hex 私有卡片, FrontendConeDebugOverlayAction.apply):
      |      首次: emit effect_spawned(&"cone_debug_overlay", Payload)
      |
      |  updater.tick_time(_state, delta_ms)
      |    -> 到期效果清理（飘字 / overlay 静默出账、程序化特效归零、震屏归零）+ visual_hp 追赶
      |
      |  STEP 5: 批量触发脏 Actor 信号
      |  ================================================
      |  _state.flush_dirty_actors()
      |    -> 遍历 _dirty_actors
      |    -> emit actor_state_changed(id, state) 每个脏 actor
      |    -> _dirty_actors.clear()
      |
      |  STEP 6: 结束检测
      |  ================================================
      |  if current_frame >= total_frames
      |     AND stepper.action_count == 0:
      |      -> _is_playing = false
      |      -> emit playback_ended()
      |
      |  NOTE: 逻辑帧播完后不会立即结束！
      |  会继续 tick 直到所有动画播放完毕。
```

### 阶段三：信号传递到 3D 场景

```
VisualState (账本)
  | signals（actor 4 条 + effect 3 条）
  v
VisualDirector / ReplayDirector (框架件转发层，1:1 转发所有信号)
  | signals
  v
FrontendBattleAnimator (wire 到 view)
  |
  +-- actor_state_changed(id, state)
  |     +-- unit_view.update_state(state)
  |     |     +-- _current_hp = state["visual_hp"]
  |     |     +-- _update_hp_bar()       -> 缩放 BoxMesh + 变色
  |     |     +-- _update_flash_effect() -> 材质 lerp 白色
  |     |     +-- _update_tint_color()   -> 材质 blend
  |     |     (update_state 只做幂等 State 更新, 不推断死亡 ——
  |     |      死亡动画走 actor_died signal -> unit_view.play_death(),
  |     |      transition-only Event 路径, _death_played 门控)
  |     +-- unit_view.set_world_position(world_pos)
  |           +-- _target_position = pos
  |              (UnitView._process 中 lerp 平滑跟随)
  |
  +-- effect_spawned(kind, payload)      按 kind 分发:
  |     +-- floating_text: FloatingTextView.new() -> effects_root, initialize(text, color, _project(pos), style, duration)
  |     +-- attack_vfx:    AttackVFXView.new() -> effects_root
  |     +-- projectile:    ProjectileView.new() -> effects_root
  |     +-- cone_debug_overlay: ConeDebugOverlayView.new() -> effects_root
  |
  +-- effect_updated(kind, id, progress, payload)
  |     +-- attack_vfx: vfx_view.update_progress(progress, payload.scale_factor, payload.alpha)
  |     +-- projectile: view.update_position(_project(payload.position))
  |
  +-- effect_removed(kind, id)
  |     +-- attack_vfx / projectile: view.cleanup() + erase
  |
  +-- _process(delta)
        +-- _update_all_unit_positions()
        |     +-- 每个 unit_view: set_world_position(
        |          _project(director.get_actor_position(id)))
        |          -> axial 浮点(含在飞插值) -> FrontendHexProjection(录像 map_config 的 GridLayout) -> Vector3
        +-- 震屏: camera_rig.position += shake_offset * 0.1
```

### 示例：damage 事件的完整生命周期

```
timeline[frame=10].events[0] =
  { kind: "damage", target: "actor_2", damage: 25, is_critical: false }
  |
  | [1] Registry.translate()
  |   FrontendDamageTranslator.can_handle() -> true
  |   FrontendDamageTranslator.translate():
  v
生成 3 个 VisualAction:
  [0] VisualFloatingTextAction  { "-25", WHITE, pos, NORMAL, 1000ms }   <-- Event
  [1] VisualProceduralVfxAction { HIT_FLASH, 300ms, actor_2 }            <-- Event
  [2] VisualHpDeltaAction       { delta:-25, delay:200ms }               <-- 瞬时指令(state 路径)
  |
  | [2] ActionStepper.enqueue() -> 3 个 ActiveAction 启动
  |     [0]/[1] 走"持续 progress 0→1"; [2] duration=0,delay 结束当帧 progress=1 立即完成
  |
  | [3] 每帧 tick:
  |
  |   t=0ms    飘字 p=0.0   闪白 p=0.0   hp delta [等待 delay]
  |   t=100ms  飘字 p=0.1   闪白 p=0.33  hp delta [等待 delay]
  |   t=200ms  飘字 p=0.2   闪白 p=0.67  hp delta apply: target_hp 80→55(瞬时)
  |   t=300ms  飘字 p=0.3   闪白 p=1.0   visual_hp lerp ~ 65 (rate=8/s)
  |   t=500ms  飘字 p=0.5                visual_hp lerp ~ 56
  |   t=1000ms 飘字 p=1.0                visual_hp ≈ 55(snap)
  |
  | [4] apply 过程中:
  |   - 飘字 / 闪白: 同前(Event 路径,持续 progress)
  |   - hp delta: 一帧把 actor.target_hp 从 80 改到 55,is_alive transition guard
  |     visual_hp 跟踪由 VisualUpdater.tick_time(state, delta_ms) 每 tick 推进,
  |     与 ActionStepper 解耦
  |
  | [5] 多次伤害的连续性:
  |     第二次伤害命中(还在 lerp 中)生成新 VisualHpDeltaAction(delta=-15):
  |     target_hp 55→40,visual_hp 从当前位置(比如 62)继续追赶 40,不跳变。
  |     → 不需要 action 互斥 / from-hp 快照,设计上消除并行覆盖问题。
  |
  | [6] tick_time: 飘字 1000ms 后账本静默忘记（view 自管节点寿命）
```

---

## 目录结构

```
hex-atb-battle/frontend/
├── README.md                 # 本文档
├── main.gd                   # 入口脚本
├── main.tscn                 # 入口场景
│
├── actions/
│   └── cone_debug_overlay_action.gd # hex 私有卡片 (自定义 kind + Payload + static apply)
│
├── translators/              # 事件翻译员（项目件，extends 框架 Translator）
│   ├── move_translator.gd    # 移动事件
│   ├── damage_translator.gd  # 伤害事件
│   ├── heal_translator.gd    # 治疗事件
│   ├── death_translator.gd   # 死亡事件
│   ├── ...                   # displacement / push_blocked / regeneration / projectile / stage_cue / buff / shield_bar / actor_facing_changed
│   └── default_registry.gd   # 默认注册表工厂 (FrontendDefaultRegistry)
│
│   （框架件在 addons/logic-game-framework/presentation/：core/ = VisualDirector / ReplayDirector / ActionStepper / VisualState / VisualUpdater /
│     VisualStateQuery / ActorVisualState / Translator / TranslatorRegistry / AnimationConfig / VisualEffectPayload /
│     BuffSummary / ShieldSummary；actions/ = VisualAction + 内置 11 种 Visual*Action）
│
├── scene/                    # 3D 场景组件
│   ├── unit_view.gd          # 单位视图
│   ├── floating_text_view.gd # 飘字视图
│   ├── attack_vfx_view.gd    # 攻击特效
│   └── projectile_view.gd    # 投射物
│
├── world_view.gd             # 响应式 World 视图(订阅 mutation signal 管 unit view 生命周期)
├── battle_animator.gd        # 战斗动画播放器(消费 timeline, 在已有 view 上叠加 VFX/飘字)
├── main.gd / main.tscn       # F6 入口,响应式 wire 样板
│
├── grid/                     # 坐标系统
│
└── ui/                       # UI 组件
    └── playback_controls.gd  # 播放控制面板(原 replay_controls.gd, 2026-04-26 改名)
```

---

## 核心类说明

### 1. VisualDirector / ReplayDirector (`presentation/core/visual_director.gd` / `replay_director.gd`，框架件)

**职责**：`VisualDirector` 持四件框架件（TranslatorRegistry / ActionStepper / VisualState / VisualUpdater），`pump(delta_ms, events)` 是共享 tick 体，只发信号不持 view；`ReplayDirector` 在其上加帧时钟（录像帧表 + 播放控制）。hex 没有自己的 Director：`FrontendBattleAnimator._ready` 里 `ReplayDirector.new(FrontendDefaultRegistry.create())` 持一个，翻译员注册表由构造函数注入，私有卡片的记账 handler 建好就能登记（组件在 `_init` 建，不等入树）

```gdscript
class_name ReplayDirector
extends VisualDirector   # VisualDirector extends Node

# 信号: 播放 3 条 + 转发自 VisualState 的 7 条
signal playback_state_changed(is_playing: bool)
signal frame_changed(current_frame: int, total_frames: int)
signal playback_ended()
signal actor_state_changed(actor_id: String, state: ActorVisualState)
signal actor_spawned(actor_id: String, state: ActorVisualState)
signal actor_died(actor_id: String)
signal actor_despawned(actor_id: String)
signal effect_spawned(kind: StringName, payload: VisualEffectPayload.Effect)
signal effect_updated(kind: StringName, effect_id: String, progress: float, payload: VisualEffectPayload.Effect)
signal effect_removed(kind: StringName, effect_id: String)

# 播放控制（ReplayDirector）
func load_playback(record: PlaybackData.BattleRecord) -> void
func play() / pause() / toggle() / reset() -> void
func step(delta_ms: float) -> void          # 不看播放态的精确推进
func set_speed(speed: float) -> void
func get_current_frame() / get_total_frames() -> int
func is_playing() / is_ended() -> bool

# 共享体与读账本（VisualDirector）
func pump(delta_ms: float, events: Array[Dictionary]) -> void
func get_actors_snapshot() -> Dictionary
func get_actor_position(actor_id: String) -> Vector2   # 逻辑平面坐标，含在飞插值
func get_action_count() -> int                         # 0 = 动画已排空
var updater: VisualUpdater                              # register_handler 登记私有卡片
```

### 2. TranslatorRegistry (`presentation/core/translator_registry.gd`，框架件)

**职责**：管理翻译员，将 GameEvent 翻译为 VisualAction[]

```gdscript
class_name TranslatorRegistry
extends RefCounted

func register(translator: Translator) -> TranslatorRegistry
func translate(event: Dictionary, query: VisualStateQuery) -> Array[VisualAction]
func has_translator_for(event_kind: String) -> bool
```

### 3. ActionStepper (`presentation/core/action_stepper.gd`，框架件)

**职责**：管理卡片的生命周期和进度

```gdscript
class_name ActionStepper
extends RefCounted

func enqueue(actions: Array[VisualAction]) -> void
func tick(delta_ms: float) -> TickResult
func cancel_all() -> void
```

### 4. VisualState + VisualUpdater (`presentation/core/visual_state.gd` / `visual_updater.gd`，框架件)

**职责**：VisualState 持账本、提供记账原语、发 7 条信号；VisualUpdater 持记账规则（kind -> handler 表）

```gdscript
class_name VisualState
extends RefCounted

signal actor_state_changed(actor_id: String, state: ActorVisualState)
signal actor_spawned(actor_id: String, state: ActorVisualState)
signal actor_died(actor_id: String)
signal actor_despawned(actor_id: String)
signal effect_spawned(kind: StringName, payload: VisualEffectPayload.Effect)
signal effect_updated(kind: StringName, effect_id: String, progress: float, payload: VisualEffectPayload.Effect)
signal effect_removed(kind: StringName, effect_id: String)

func initialize_from_replay(record: PlaybackData.BattleRecord) -> void
func reset_to(record: PlaybackData.BattleRecord) -> void
func as_query() -> VisualStateQuery

class_name VisualUpdater
extends RefCounted

func register_handler(kind: StringName, handler: Callable) -> void
func apply_actions(state: VisualState, active_actions: Array[ActionStepper.ActiveAction]) -> void
func apply_event(state: VisualState, event: Dictionary) -> void
func tick_time(state: VisualState, delta_ms: float) -> void
```

### 5. VisualAction (`presentation/actions/visual_action.gd`，框架件)

**职责**：声明式描述视觉效果（卡片纯数据，记账规则在 VisualUpdater）

```gdscript
class_name VisualAction
extends RefCounted

# 内置 kind: KIND_MOVE / KIND_HP_DELTA / KIND_FLOATING_TEXT / KIND_PROCEDURAL_VFX / KIND_DEATH /
#   KIND_ATTACK_VFX / KIND_PROJECTILE / KIND_BUFF_STATE / KIND_SHIELD_STATE / KIND_BUMP / KIND_FACING_STATE
enum EasingType { LINEAR, EASE_IN, EASE_OUT, EASE_IN_OUT, ... }

var kind: StringName   # 项目私有卡片自定义 kind + VisualUpdater.register_handler
var actor_id: String
var duration: float    # 毫秒
var delay: float       # 延迟毫秒
```

---

## 事件类型 (来自逻辑层)

| 事件类型 | 字段 | 说明 |
|---------|------|------|
| `move_start` | `actor_id`, `from_hex`, `to_hex` | 单位开始移动 |
| `damage` | `target_actor_id`, `damage`, `source_actor_id`, `is_critical` | 造成伤害 |
| `heal` | `target_actor_id`, `heal_amount`, `source_actor_id` | 治疗 |
| `death` | `actor_id`, `killer_actor_id` | 单位死亡 |

---

## 录像数据格式

```json
{
  "meta": {
    "battle_id": "battle_001",
    "recorded_at": 1706000000,
    "tick_interval": 100,
    "total_frames": 50,
    "result": "victory"
  },
  "world_snapshot": {
    "actors": [
      {
        "id": "actor_1",
        "config_id": "warrior",
        "display_name": "Warrior",
        "team": 0,
        "position": { "hex": { "q": -2, "r": 0 } },
        "attributes": { "hp": 100.0, "max_hp": 100.0 }
      }
    ],
    "map_config": {},
    "position_formats": { "Character": "hex" }
  },
  "timeline": [
    {
      "frame": 5,
      "events": [
        {
          "kind": "move_start",
          "actor_id": "actor_1",
          "from_hex": { "q": -2, "r": 0 },
          "to_hex": { "q": -1, "r": 0 }
        }
      ]
    }
  ]
}
```

---

## 使用方法

> 战斗回放的权威 wire 见顶部「现状响应式 wire」节;旧 `FrontendBattleReplayScene` API 已删除。

### 添加自定义翻译员

```gdscript
# 1. 继承框架 Translator
class_name FrontendMyCustomTranslator
extends Translator

func can_handle(event: Dictionary) -> bool:
    return event.get("kind") == "my_custom_event"

func translate(event: Dictionary, query: VisualStateQuery) -> Array[VisualAction]:
    var actor_id: String = event.get("actor_id", "")
    return [VisualFloatingTextAction.new(
        actor_id, "Custom!", Color.YELLOW, query.get_actor_position(actor_id),
        VisualFloatingTextAction.FloatingTextStyle.NORMAL, 1000.0
    )]

# 2. 注册到 Registry
var registry := FrontendDefaultRegistry.create()
registry.register(FrontendMyCustomTranslator.new())
```

---

## 新技能表演层接入清单

逻辑与表演**同步接入，不留 `# TODO 表演层`**——每落地一个技能 / buff 就把下面几项过一遍。接入面比想象小，常见技能只碰 1-2 处（Expose 整体接入 = `BUFF_REGISTRY` 加 1 行 + 复用 1 个 cue id）。scenario / headless 验证不读表演层（走 logic event collector），漏接不会红在 skill scenario 上，而是由 `hex/regression` 组的 manifest lint（`tests/battle/smoke_manifest_lint.gd`，断言 1-4）兜底。

### 接入面候选清单

| 接入点 | 文件 | 何时必接 |
|---|---|---|
| **BUFF_REGISTRY**（buff 头顶图标） | `translators/buff_translator.gd::BUFF_REGISTRY` | 任何**新 buff** ability（config_id 白名单，不接**永远不显示**；lint 断言 2 兜底——带 buff tag 未登记会红；确需豁免的写进 lint 的 `BUFF_ICON_EXEMPT` 并注明理由） |
| **StageCue cue_id**（施法瞬间 vfx） | 先 `logic/config/hex_battle_cues.gd` 加常量 → 再 `translators/stage_cue_translator.gd` 对应注册表引用该常量 | 用 `StageCueAction` 时；**优先复用现有 cue**（菜单里挑），声明处只许写 `HexBattleCues.XXX`（frontend 对未登记 cue **静默跳过**，lint 断言 3 抓未注册 cue）；暂无视觉的 cue 进 lint 的 `CUE_NO_VISUAL_YET` 豁免名单并在菜单「暂无视觉」分组登记 |
| **default_registry**（翻译员注册） | `translators/default_registry.gd::create()` | **只有**新加翻译员类时才动（普通技能 / buff 复用现有翻译员即够） |
| **投射物视觉类型** | 技能侧 `ProjectileActor.CFG_VISUAL_TYPE`（现有 `"arrow"` / `"fireball"` / `"lightning"`）→ `translators/projectile_translator.gd` 的 `_parse_projectile_type` / `_get_projectile_color` 映射 | 仅当技能用了**自定义投射物形态**（先复用现有类型；新形态两边同步加分支） |

### BUFF_REGISTRY 一行格式

照抄 `BUFF_REGISTRY` 里任一现有条目：key 是 buff 的 `CONFIG_ID` 常量（不写裸字符串），值含 `short`（头顶 1-2 字符）/ `color` / `primary_source`（`PrimarySource.STACKS` 读 ability stacks、`SHIELD_REMAINING` 读护盾余量、`NONE` 只显 duration）。

`short` / `color` 选取约定：
- buff 取名首字母大写（P=Poison、E=Expose、S=Ward、U=Surge、T=Thorn、V=Vitality、G=Vigor、I=Inspire；护盾类双字母 PS / MS），控制类状态可用单个符号（★ 眩晕 / 🤐 沉默 / ✗ 破坏）
- 颜色避开已用色：以 `BUFF_REGISTRY` 现有条目为准（行内注释写明各自色相与「区分谁」），新条目同样注明
- 同性质 buff（positive / negative）颜色区分够即可，不必一致；控制类飘字（`stage_cue_translator.gd::CONTROL_FLOATING_TEXTS`）与对应 buff 图标同色

### 复用 cue id 的判断

**优先复用，不编新名**。例如 Expose 的 setup 标记直接复用 `HexBattleCues.MELEE_SLASH`（挥手特效），玩家看到「caster 朝 target 挥了一下」的视觉反馈即可。只有视觉语义与现有任何 cue 都不匹配（召唤 / 远程瞬移 / debuff glow 圈这类特殊视觉）才加新 cue，流程：`HexBattleCues` 加常量（官方菜单）→ `stage_cue_translator.gd` 加类别 / 配置并引用该常量（控制 / 进阶技能大多走 `CONTROL_FLOATING_TEXTS` 加一行飘字配置即可）；暂时不接视觉则进 lint 的 `CUE_NO_VISUAL_YET` 豁免名单。

背景：`stage_cue_translator` 对未登记的 cue id 静默跳过（不报错），所以 cue 走常量菜单 + lint 断言 3 双保险——编新名 / 打错字都过不了 `hex/regression`。
