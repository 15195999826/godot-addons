# Hex ATB Battle Frontend (表演层)

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
| **逻辑层** | `addons/logic-game-framework/example/hex-atb-battle/` | 战斗逻辑计算、事件生成 |
| **Web 表演层** | `../inkmon-web/lib/battle-replay/` | TypeScript 实现的参考架构 |
| **本项目** | `hex-atb-battle-frontend/` | Godot 3D 表演层 |

---

## 框架设计

### 核心思路：录像回放驱动的声明式动画管线

表演层不实时响应逻辑层，而是消费逻辑层产出的**录像数据**（timeline of events），
通过四层管线将事件翻译为 3D 动画：

```
录像数据 --> 翻译层 --> 调度层 --> 状态层 --> 渲染层
```

### 四层管线架构

**1. 翻译层（Visualizer）** -- 事件到动作的纯函数映射

- `BaseVisualizer` 定义 `can_handle()` + `translate()` 接口
- 每个 Visualizer 是纯函数：只读 context，不修改状态，返回声明式 `VisualAction[]`
- `VisualizerRegistry` 支持多对多：一个事件可被多个 Visualizer 处理
  （如 damage 同时触发飘字 + 闪白 + 血条）
- 通过 `DefaultRegistry` 工厂统一注册，用户可自由扩展

**2. 调度层（ActionScheduler）** -- 时序管理

- 所有 Action 入队后并行执行（非阻塞队列）
- 每个 Action 有 `delay`（延迟启动）和 `duration`（持续时间）
- `tick(delta_ms)` 推进所有活跃 Action 的进度（0->1），返回 `TickResult`
- 职责单一：只管"什么时候执行到什么进度"，不管"执行什么"

**3. 状态层（RenderWorld）** -- 状态机

- 接收 `TickResult`，根据 Action 类型 + 进度更新内部状态（位置、HP、特效等）
- 通过 `match action.type` 分发到具体的 `_apply_xxx_action()` 方法
- 维护脏标记（`_dirty_actors`），批量触发信号，避免每帧频繁 emit
- 提供 `as_context()` 创建只读快照给 Visualizer 查询

**4. 渲染层（BattleReplayScene + Views）** -- 信号驱动的 3D 场景

- 监听 Director 转发的信号（`actor_state_changed`、`floating_text_created` 等）
- `UnitView` 接收状态 Dictionary，更新网格颜色/血条/位置
- 特效（飘字、攻击 VFX、投射物）通过 create/update/remove 三段式生命周期管理

### 关键设计决策

| 决策 | 选择 | 原因 |
|------|------|------|
| 数据驱动 vs 命令式 | VisualAction 是纯数据对象，不持有 Node | 逻辑与渲染解耦，支持序列化/回放 |
| 并行 vs 串行动画 | 全部并行，通过 delay 控制时序 | 简化调度器，避免复杂的队列/阻塞逻辑 |
| 信号 vs 直接调用 | Director -> Scene 通过信号 | 层间松耦合，Scene 可替换 |
| 帧驱动 vs 事件驱动 | 逻辑帧累积器 + 动画 tick 分离 | 逻辑帧结束后动画可继续播放至完成 |
| 状态管理 | RenderWorld 集中管理，View 只读 | 单一数据源，避免状态不一致 |
| 跨平台 | 与 Web 端 TypeScript 实现保持 1:1 架构对应 | 两端行为一致，便于维护 |

### 扩展机制

扩展一种新的战斗表演只需 3 步：

1. **新建 Action 子类**（如 `FrontendProjectileAction`）-- 声明数据
2. **新建 Visualizer**（如 `ProjectileVisualizer`）-- 翻译逻辑
3. **在 RenderWorld 的 `_apply_action()` 中添加 match 分支** -- 状态应用

`DefaultRegistry.create()` 注册新 Visualizer 即可生效，无需修改 Director 或 Scheduler。

---

## 流程图

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
  +--[1] _director.load_replay(record)            <-- FrontendBattleDirector
  |    +-- 构建 _frame_data_map: { frame_number -> FrameData }
  |    +-- _world.initialize_from_replay(record)  <-- FrontendRenderWorld
  |    |     +-- 解析 positionFormats 配置
  |    |     +-- 从 mapConfig 创建 GridLayout
  |    |     +-- 遍历 initialActors -> 初始化每个 actor 状态 Dictionary
  |    |     |     { id, position, visual_hp, max_hp, is_alive,
  |    |     |       flash_progress, tint_color }
  |    |     +-- emit actor_state_changed() 给每个 actor（初始同步）
  |    +-- _analyze_event_coverage()              <-- 打印事件覆盖摘要
  |    +-- 重置: _current_frame=0, _logic_accumulator=0
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
FrontendBattleDirector._process(delta)
  +-- _tick(delta * 1000 * _speed)
      |
      |  STEP 1: 逻辑帧推进（累积器模式）
      |  ================================================
      |  _logic_accumulator += delta_ms
      |
      |  while _logic_accumulator >= 100ms:
      |      _logic_accumulator -= 100ms
      |      _current_frame++
      |
      |      if _frame_data_map.has(current_frame):
      |          遍历该帧所有 events:
      |
      |          context = _world.as_context()
      |            只读快照:
      |            - actors 状态
      |            - interpolated_positions
      |            - animation_config
      |            - layout (坐标转换)
      |
      |          actions = _registry.translate(event, ctx)
      |            遍历所有 Visualizer:
      |            +-- v.can_handle(event)?
      |            +-- v.translate(event, ctx)
      |                -> Array[VisualAction]
      |
      |          _scheduler.enqueue(actions)
      |            -> 每个 action 包装为 ActiveAction
      |               { id, action, elapsed=0, progress=0 }
      |
      |      emit frame_changed(current, total)
      |
      |  STEP 2: 推进世界时间
      |  ================================================
      |  _world.advance_time(delta_ms)
      |
      |  STEP 3: 调度器 tick（推进所有动画进度）
      |  ================================================
      |  result = _scheduler.tick(delta_ms)
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
      |  STEP 4: 应用动作到世界状态（if has_changes）
      |  ================================================
      |  _world.apply_actions(result.active_actions)
      |  _world.apply_actions(result.completed_this_tick)
      |
      |    对每个 ActiveAction, match action.type:
      |
      |    MOVE:
      |      interpolated_pos = action.get_interpolated_hex(progress)
      |      _interpolated_positions[actor_id] = pos
      |      if progress>=1: actor["position"] = to_hex
      |
      |    UPDATE_HP:
      |      actor["visual_hp"] = lerp(from, to, progress)
      |      if progress>=1: 精确赋值 + 更新 is_alive
      |      _dirty_actors[actor_id] = true
      |
      |    FLOATING_TEXT:
      |      首次: 加入 _floating_texts 列表
      |      emit floating_text_created(data)
      |
      |    PROCEDURAL_VFX:
      |      HIT_FLASH: actor["flash_progress"] = f(progress)
      |      SHAKE:     _screen_shake = offset(progress)
      |      COLOR_TINT: actor["tint_color"] = color
      |
      |    DEATH:
      |      actor["is_alive"]=false, hp=0
      |      if progress>=1: emit actor_died()
      |
      |    ATTACK_VFX:
      |      首次: emit attack_vfx_created(data)
      |      每帧: emit attack_vfx_updated(progress, scale, alpha)
      |      完成: emit attack_vfx_removed(id)
      |
      |    PROJECTILE:
      |      首次: emit projectile_created(data)
      |      每帧: emit projectile_updated(pos, dir)
      |      完成: emit projectile_removed(id)
      |
      |  _world.cleanup(world_time)
      |    -> 清理过期飘字、特效、震屏
      |
      |  STEP 5: 批量触发脏 Actor 信号
      |  ================================================
      |  _world.flush_dirty_actors()
      |    -> 遍历 _dirty_actors
      |    -> emit actor_state_changed(id, state) 每个脏 actor
      |    -> _dirty_actors.clear()
      |
      |  STEP 6: 结束检测
      |  ================================================
      |  if current_frame >= total_frames
      |     AND scheduler.action_count == 0:
      |      -> _is_playing = false
      |      -> emit playback_ended()
      |
      |  NOTE: 逻辑帧播完后不会立即结束！
      |  会继续 tick 直到所有动画播放完毕。
```

### 阶段三：信号传递到 3D 场景

```
RenderWorld (状态层)
  | signals
  v
BattleDirector (转发层，1:1 转发所有信号)
  | signals
  v
BattleReplayScene (渲染层)
  |
  +-- actor_state_changed(id, state)
  |     +-- unit_view.update_state(state)
  |     |     +-- _current_hp = state["visual_hp"]
  |     |     +-- _update_hp_bar()       -> 缩放 BoxMesh + 变色
  |     |     +-- _update_flash_effect() -> 材质 lerp 白色
  |     |     +-- _update_tint_color()   -> 材质 blend
  |     |     +-- if !is_alive -> _play_death_animation()
  |     |           +-- Tween: scale->0.1, y-=0.5, -> hide
  |     +-- unit_view.set_world_position(world_pos)
  |           +-- _target_position = pos
  |              (UnitView._process 中 lerp 平滑跟随)
  |
  +-- floating_text_created(data)
  |     +-- FloatingTextView.new() -> effects_root
  |     +-- initialize(text, color, pos, style, duration)
  |
  +-- attack_vfx_created / updated / removed
  |     +-- created: AttackVFXView.new() -> effects_root
  |     +-- updated: vfx_view.update_progress(p, scale, alpha)
  |     +-- removed: vfx_view.cleanup() + erase
  |
  +-- projectile_created / updated / removed
  |     +-- created: ProjectileView.new() -> effects_root
  |     +-- updated: view.update_position(pos) + direction
  |     +-- removed: view.cleanup() + erase
  |
  +-- _process(delta)
        +-- _update_all_unit_positions()
        |     +-- 每个 unit_view: set_world_position(
        |          director.get_actor_world_position(id))
        |          -> hex 插值坐标 -> GridLayout.coord_to_pixel -> Vector3
        +-- 震屏: camera_rig.position += shake_offset * 0.1
```

### 示例：damage 事件的完整生命周期

```
timeline[frame=10].events[0] =
  { kind: "damage", target: "actor_2", damage: 25, is_critical: false }
  |
  | [1] Registry.translate()
  |   DamageVisualizer.can_handle() -> true
  |   DamageVisualizer.translate():
  v
生成 3 个 VisualAction:
  [0] FloatingTextAction { "-25", WHITE, pos, NORMAL, 1000ms }
  [1] ProceduralVFXAction { HIT_FLASH, 300ms, actor_2 }
  [2] UpdateHPAction { from:80, to:55, 300ms, delay:200ms }
  |
  | [2] Scheduler.enqueue() -> 3 个 ActiveAction 并行启动
  |
  | [3] 每帧 tick:
  |
  |   t=0ms    飘字 p=0.0   闪白 p=0.0   血条 [等待 delay]
  |   t=100ms  飘字 p=0.1   闪白 p=0.33  血条 [等待 delay]
  |   t=200ms  飘字 p=0.2   闪白 p=0.67  血条 p=0.0  <-- delay 结束
  |   t=300ms  飘字 p=0.3   闪白 p=1.0   血条 p=0.33
  |   t=500ms  飘字 p=0.5                血条 p=1.0
  |   t=1000ms 飘字 p=1.0
  |
  | [4] apply 过程中:
  |   - 飘字: 首帧 emit floating_text_created
  |           -> Scene 创建 FloatingTextView
  |   - 闪白: actor["flash_progress"] 从 0->1->0
  |           -> dirty -> flush -> UnitView 材质变白再恢复
  |   - 血条: actor["visual_hp"] 从 80->55 插值
  |           -> dirty -> flush -> UnitView HPBar 缩放+变色
  |
  | [5] cleanup: 飘字 1000ms 后从 _floating_texts 移除
```

---

## 目录结构

```
hex-atb-battle-frontend/
├── README.md                 # 本文档
├── main.gd                   # 入口脚本
├── main.tscn                 # 入口场景
│
├── core/                     # 核心框架
│   ├── battle_director.gd    # 主控制器 (Node)
│   ├── action_scheduler.gd   # 动作调度器
│   ├── render_world.gd       # 渲染状态管理
│   ├── visualizer_registry.gd # Visualizer 注册表
│   ├── visualizer_context.gd # 只读查询上下文
│   └── animation_config.gd   # 动画配置
│
├── actions/                  # 视觉动作定义
│   ├── visual_action.gd      # 基类 + ActionType 枚举
│   ├── move_action.gd        # 移动动作
│   ├── update_hp_action.gd   # 血条更新
│   ├── floating_text_action.gd # 飘字
│   ├── procedural_vfx_action.gd # 程序化特效
│   └── death_action.gd       # 死亡动画
│
├── visualizers/              # 事件翻译器
│   ├── base_visualizer.gd    # 抽象基类
│   ├── move_visualizer.gd    # 移动事件
│   ├── damage_visualizer.gd  # 伤害事件
│   ├── heal_visualizer.gd    # 治疗事件
│   ├── death_visualizer.gd   # 死亡事件
│   └── default_registry.gd   # 默认注册表工厂
│
├── scene/                    # 3D 场景组件
│   ├── battle_replay_scene.gd # 主场景管理
│   ├── unit_view.gd          # 单位视图
│   └── floating_text_view.gd # 飘字视图
│
├── grid/                     # 坐标系统
│
├── ui/                       # UI 组件
│   └── replay_controls.gd    # 播放控制面板
│
└── test_*.gd/tscn            # 测试脚本/场景
```

---

## 核心类说明

### 1. BattleDirector (`core/battle_director.gd`)

**职责**：整合所有组件，驱动回放流程

```gdscript
class_name FrontendBattleDirector
extends Node

# 信号
signal playback_state_changed(is_playing: bool)
signal frame_changed(current_frame: int, total_frames: int)
signal playback_ended()
signal actor_state_changed(actor_id: String, state: Dictionary)
signal floating_text_created(data: Dictionary)
signal actor_died(actor_id: String)

# 核心方法
func load_replay(replay_data: Dictionary) -> void
func play() -> void
func pause() -> void
func reset() -> void
func set_speed(speed: float) -> void
```

### 2. VisualizerRegistry (`core/visualizer_registry.gd`)

**职责**：管理 Visualizer，将 GameEvent 翻译为 VisualAction[]

```gdscript
class_name FrontendVisualizerRegistry
extends RefCounted

func register(visualizer: FrontendBaseVisualizer) -> void
func translate(event: Dictionary, context: FrontendVisualizerContext) -> Array
```

### 3. ActionScheduler (`core/action_scheduler.gd`)

**职责**：管理动作的生命周期和进度

```gdscript
class_name FrontendActionScheduler
extends RefCounted

func enqueue(action: FrontendVisualAction) -> void
func tick(delta_ms: float) -> TickResult
func clear() -> void
```

### 4. RenderWorld (`core/render_world.gd`)

**职责**：管理渲染状态，应用动作到状态

```gdscript
class_name FrontendRenderWorld
extends RefCounted

signal actor_state_changed(actor_id: String, state: Dictionary)
signal floating_text_created(data: Dictionary)
signal actor_died(actor_id: String)

func initialize_from_replay(replay_data: Dictionary) -> void
func apply_actions(tick_result: FrontendActionScheduler.TickResult) -> void
func get_actor_state(actor_id: String) -> Dictionary
func reset() -> void
```

### 5. VisualAction (`actions/visual_action.gd`)

**职责**：声明式描述视觉效果

```gdscript
class_name FrontendVisualAction
extends RefCounted

enum ActionType { MOVE, UPDATE_HP, FLOATING_TEXT, MELEE_STRIKE, PROCEDURAL_VFX, DEATH }
enum EasingType { LINEAR, EASE_IN, EASE_OUT, EASE_IN_OUT, ... }

var type: ActionType
var actor_id: String
var duration: int      # 毫秒
var delay: int         # 延迟毫秒
var easing: EasingType
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
  "version": "2.0",
  "meta": {
    "battleId": "battle_001",
    "recordedAt": 1706000000,
    "tickInterval": 100,
    "totalFrames": 50,
    "result": "victory"
  },
  "configs": {},
  "initialActors": [
    {
      "id": "actor_1",
      "configId": "warrior",
      "displayName": "Warrior",
      "team": 0,
      "position": { "hex": { "q": -2, "r": 0 } },
      "attributes": { "hp": 100.0, "maxHp": 100.0 },
      "abilities": [],
      "tags": {}
    }
  ],
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

### 基本使用

```gdscript
# 1. 创建回放场景
var replay_scene = FrontendBattleReplayScene.new()
add_child(replay_scene)

# 2. 加载录像
var replay_data = load_replay_json("user://Replays/battle.json")
replay_scene.load_replay(replay_data)

# 3. 控制播放
replay_scene.play()
replay_scene.pause()
replay_scene.reset()
replay_scene.set_speed(2.0)

# 4. 监听信号
var director = replay_scene.get_director()
director.playback_ended.connect(_on_playback_ended)
director.frame_changed.connect(_on_frame_changed)
```

### 添加自定义 Visualizer

```gdscript
# 1. 继承 FrontendBaseVisualizer
class_name MyCustomVisualizer
extends FrontendBaseVisualizer

func can_handle(event: Dictionary) -> bool:
    return event.get("kind") == "my_custom_event"

func translate(event: Dictionary, context: FrontendVisualizerContext) -> Array:
    var action = FrontendFloatingTextAction.new()
    action.actor_id = event.get("actor_id", "")
    action.text = "Custom!"
    action.color = Color.YELLOW
    return [action]

# 2. 注册到 Registry
var registry = FrontendDefaultRegistry.create()
registry.register(MyCustomVisualizer.new())
```

---