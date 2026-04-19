# 2026-04-20 — skill_preview 切换到响应式战斗路径

## 范围 / 前置

- **动的文件**：
  - `example/skill-preview/skill_preview_procedure.gd`（新）
  - `example/skill-preview/skill_preview_world.gd`（新）
  - `example/skill-preview/skill_preview.gd`（大改）
  - `example/hex-atb-battle-core/hex_world_gameplay_instance.gd`（+1 字段）
  - `example/hex-atb-battle/hex_battle.gd`（-1 字段）
  - `example/hex-atb-battle/actions/*.gd` × 7、`target_selectors.gd`、`utils/*.gd` × 2 —— 把 `battle: HexBattle` 改 `HexWorldGameplayInstance`
  - 主仓库 `tests/smoke_skill_preview_reactive.tscn/gd`（新）
- **依赖的前轮决策**：
  - 阶段 1（`2026-04-19-world-as-single-instance.md`）把 `HexBattle` 拆成 `HexWorldGameplayInstance`（持久状态） + `HexBattleProcedure`（短命过程），`HexBattle` 仅作兼容门面。
  - 阶段 2（`2026-04-20-world-view.md`）新增 `FrontendWorldView`（订阅 mutation signal）+ `FrontendBattleAnimator`（消费 event_timeline 叠加动画），但未接入任何现有场景。

## 背景

阶段 2 结束时，`FrontendWorldView` / `FrontendBattleAnimator` 只有 smoke 验证，`main.tscn` / `skill_preview` / Web 桥接全部还走老 `FrontendBattleReplayScene.load_replay(record)` destructive 路径。阶段 3 的目标是**把 skill_preview 这个编辑器工具切到响应式路径**，作为第一批真正接入生产路径的调用端，验证"无缝展开战斗"（编辑态 actor view 在战斗触发瞬间不重建）可行。

原 `skill_preview.gd` 的 START 流程：

```
UI 改 actor → _rebuild_editor_preview → _replay_scene.load_replay(mini_record)  # destructive 重建 _units_root
点 START → SkillPreviewBattle.run_with_config(...)
           ↓ (GameWorld.init → 临时 _PreviewInstance → tick → GameWorld.destroy)
         返回 replay dict
       → _replay_scene.load_replay(replay_dict)  # 再一次 destructive 重建
       → _replay_scene.play()
```

两层"load_replay 重建场景"的视觉跳变（grid 重建、unit view 重 spawn、相机重算）是阶段 0 POC 点名要消灭的东西。

## 定位

### P1：SkillPreviewBattle 与常驻 world 互斥

`SkillPreviewBattle.run_with_config` 在 headless 场景是自洽的（`GameWorld.init → create_instance(_PreviewInstance) → run → GameWorld.destroy`），但常驻 skill_preview world 跟它是**互斥**的 —— 每次 START 都 `GameWorld.destroy()` 会把 UI 里的常驻 WorldGI 一并清掉。

两条可能出路：

- **A**：改 `SkillPreviewBattle` 支持"传入现有 world 跑一把"，不再 init/destroy。但它同时给 `tests/skill_scenarios/` scenario runner 和 Web 桥接用，两条路径的"每场独立 GameWorld 生命周期"语义对 scenario runner 来说是简单且已稳的假设，改动扩散面大。
- **B**：保留 `SkillPreviewBattle` 纯 headless 不动，skill_preview UI 走全新的 BattleProcedure 路径 —— 新写 `SkillPreviewProcedure` 承接 tick loop，SkillPreviewWorldGI.`_create_battle_procedure` 返回它。UI 场景和 scenario runner 用不同的引擎。

**选 B**。scenario runner 的"一次一 GameWorld"足够简单不值得破坏；skill_preview UI 的"常驻 world + 无缝战斗"是本阶段核心诉求。两个工具服务不同需求，一条路径优化给一种场景更克制。

### P2：HexBattleProcedure 不直接适用

`HexBattleProcedure.tick_once` 跑的是 ATB loop（`accumulate_atb` / `can_act` / `_decide_action`），cover 完整战斗。skill_preview 的预期是"caster 主动施放指定 ability，tick 到 no executing + no flying projectile"，完全是另一套终止条件。强行复用 `HexBattleProcedure` 需要在它身上叠条件分支，会污染真实战斗流程。

**结论**：新写 `SkillPreviewProcedure extends BattleProcedure`。承接原 `SkillPreviewBattle.run_with_actions` 里那段 tick loop（`MAX_TICKS=500 / POST_EXECUTION_TICKS=10` / `_still_executing` 检查 / `_broadcast_projectile_events`），但寄生在外部常驻 world 上，不做 init/destroy。

### P3：logger 字段位置

实装后第一次跑 smoke 出 `Invalid access to property 'logger' on base object 'SkillPreviewWorldGI'`。追根：`damage_utils / heal_action` 里有 `if battle.logger != null: battle.logger.damage_dealt(...)`，`logger` 字段只在 `HexBattle`（`HexWorldGameplayInstance` 的具体子类）上。`SkillPreviewWorldGI` 是 `HexBattle` 的**姊妹**子类，不继承这个字段。

修法两选：

- **A**：下沉 `logger` 到 `HexWorldGameplayInstance`，默认 null，所有子类共享。
- **B**：每处 `battle.logger` 改 `if battle is HexBattle: (battle as HexBattle).logger.xxx`。

**选 A**。logger 本质就是"可选日志"，不是 HexBattle 特有。放在 World 层面字段更自然，且避免散落的 is-check。HexBattle 上原 `var logger: HexBattleLogger = null` 声明删除以避免 shadowing。

### P4：HexBattle 静态类型标注是遗留

同一次 smoke 还吐 `Trying to assign value of type 'skill_preview_world.gd' to a variable of type 'hex_battle.gd'`。多处 action / damage_utils / game_state_utils / target_selectors 里的 `var battle: HexBattle = ctx.game_state_provider` 是阶段 1 的**遗漏** —— 阶段 1 把 `get_actor / get_alive_actor_ids / grid / remove_actor / get_actors` 全部下沉到了 `HexWorldGameplayInstance`，这些 action 访问的 API 早已是父类的，但标注仍保留着具体子类。`HexBattle` 跑完整战斗时 IS-A 兼容不报错，换成 `SkillPreviewWorldGI` 就炸。

批量改为 `HexWorldGameplayInstance`（11 处，含 damage_utils 函数签名）。AI 目录（`ai/*.gd` × 5）未改 —— SkillPreviewProcedure 不跑 AI，`HexBattleProcedure._decide_action` 传入 `_world_instance: HexWorldGameplayInstance` 但运行时实际是 HexBattle，IS-A 兼容不报错。等未来"WorldGI 直接驱动 AI"需求落地再改，避免扩 scope。

## 架构决策

### D1：SkillPreviewProcedure 只知道 caster_id，不知道 left_team/right_team

`HexBattleProcedure` 按 `left_team` / `right_team` 组织参战者（胜负判定用）。SkillPreviewProcedure 不做胜负判定，不需要队伍语义 —— 它只需要 `caster_id` + `ability_config` + `target_id` + `passives`。

`participants` 数组通过 base `BattleProcedure._init(world, participants)` 传进来（服务 `_mark_in_combat` 的 in_combat tag 管理），仅用于"标记谁在战斗里"。caster_id / target_id 是**额外参数**，通过 skill_preview 专属的 `SkillPreviewWorldGI.queue_preview(...)` 预存，`_create_battle_procedure` 消费参数并组装 procedure。

把参数预存到 WorldGI 而不是扩展 base `start_battle` 签名 —— 避免污染框架 API（base `start_battle(participants: Array[Actor])` 保持干净）。queue + consume 一对儿的 contract 放在 SkillPreviewWorldGI 上，消费后字段清空，防止"上一场 queue 过，下一场忘了 queue"误用。

### D2：reset 清 _actors / _actor_id_2_actor_dic / _systems / grid / _logic_time，不清 _state

阶段 0 设计 doc 的 reset 草稿（line 181-194）只清 `_actors / _systems / grid`。实装扩展了：

- `_actor_id_2_actor_dic` 必须跟着 `_actors` 一起清（是后者的 index）
- `_logic_time = 0.0` —— 让录像时间戳起点稳定
- 清 `_queued_*` preview 参数 —— 防止跨场残留

**不清** `_state` —— `start_battle` 的重入保护靠 `_active_battle == null`，不看 `_state`（`WorldGI.tick` 本来就只在 `is_running()` 为 true 时走 system tick；skill_preview 在 `_ready` 里 `_world.start()` 之后 `_state="running"`，整个 session 保持不变）。reset 不流转 state 机器。

reset 里没调 `remove_actor` 逐个清 —— 因为 `remove_actor` 会走 `HexWorldGameplayInstance.remove_actor` 里的 `grid.remove_occupant / cancel_reservation`，但 reset 反正也要把 `grid = null`，逐个清是浪费。直接 `_actors.clear()` + `actor_removed.emit(aid)` 推 signal 让 `FrontendWorldView` 回收 view 就够了。

### D3：WorldView / Animator 常驻，每场战斗结束不 free

`skill_preview._on_playback_ended` 里只调 `_rebuild_world_from_model()`（重建 world 侧状态），**不** `unbind/bind WorldView`、**不** `queue_free` Animator。view 通过 WorldView 订阅的 signal 响应式更新；Animator 每次 `play(timeline, views)` 重设 unit_views dict + `_clear_effects()` 干净，自身节点可以无限复用。

smoke_skill_preview_reactive 明确断言 3 场战斗间 `WorldView.get_instance_id() == _world_view_instance_id` / `Animator` 同理，保证复用不意外被重建。

### D4：console event log 降级为战斗结束后一次性 dump

老版 skill_preview 通过 `_director.frame_changed` signal 在动画推进时同步打印 damage/heal/death 等事件 —— 视觉和文字日志对齐。切到 Animator 后，Animator 包装 director 但**没转发 `frame_changed`**（阶段 2 简化审查时认定 frame_changed 未被消费，删掉了 `get_director()` getter）。

本阶段**不**补这个 API。替代方案：`_on_battle_finished` 拿到 timeline 后立即 `_dump_timeline_events`，文字日志一次性全部打出来，视觉动画按 speed 慢慢播。UX 略退化但阶段 3 可接受，省得为 skill_preview 单独加 frame signal 反向污染 Animator。后续补的话几行代码就行，留在 "待处理"。

### D5：不修战斗期死亡 view 消失问题

`damage_utils.apply_damage` 在 hp ≤ 0 时会 `battle.remove_actor(target_id)` —— 在 WorldGI 架构下 emit `actor_removed` signal，`FrontendWorldView` 跟着 queue_free 对应 view。这意味着战斗结束时死亡角色的 view 已经消失，Animator 随后 `play(timeline, views)` 里死亡动画要找那个 view 会 miss（Animator 已有 `if not _unit_views.has(actor_id): return` tolerant 处理）。

视觉上：skill_preview 在战斗期间就会看到"打死的角色瞬间消失"而不是播死亡动画 → 消失。这是阶段 2 `smoke_world_view` 已暴露的同一问题（smoke 注释明确提到）。

**本阶段不修**。修法要改 WorldGameplayInstance 里 `remove_actor` 的语义（比如"只从 actor registry 移除但延迟 emit 到战斗结束"）或者给 WorldView 加"战斗期冻结"开关 —— 都是 framework 级改动。阶段 4 录像格式 v3 + `ReplayPlayer`（临时 WorldGI + WorldView）会从另一个角度解掉：skill_preview 可以 bind 到 ReplayPlayer 构造的临时 world 看完整死亡动画。或者本阶段的常驻路径保留作为"编辑态+快速战斗验证"，录像路径走 ReplayPlayer，两条路径共存。

## 实现

### skill_preview.gd 的关键替换

```gdscript
# Before (阶段 2):
_replay_scene = FrontendBattleReplayScene.new()
...
func _rebuild_editor_preview():
    var record := _build_minimal_record_from_ui_actors()
    _replay_scene.load_replay(record)  # destructive

func _on_start_pressed():
    var result := SkillPreviewBattle.run_with_config(...)  # init/destroy GameWorld
    var record := ReplayData.BattleRecord.from_dict(result.replay)
    _replay_scene.load_replay(record)  # destructive again
    _replay_scene.play()

# After (阶段 3):
GameWorld.init()
_world = SkillPreviewWorldGI.new()
GameWorld.create_instance(func(): return _world)
_world.start()
_world.battle_finished.connect(_on_battle_finished)
_world_view = FrontendWorldView.new(); _world_view.bind_world(_world)
_animator = FrontendBattleAnimator.new()

func _rebuild_world_from_model():
    _world.reset()
    _world.configure_grid(cfg)           # -> signal -> WorldView 重建 grid
    _world.add_system(ProjectileSystem.new(...))
    for actor_data in _actors:
        var actor := CharacterActor.new(...)
        _world.add_actor(actor)          # -> signal -> WorldView spawn view
        actor.set_team_id(...)
        _world.grid.place_occupant(coord, actor)
        actor.hex_position = coord
        _role_id_to_actor_id[role_id] = actor.get_id()

func _on_start_pressed():
    _rebuild_world_from_model()
    _world.queue_preview(caster_id, ability_cfg, target_id, passives)
    _world.start_battle(participants)
    _world.tick(TICK_INTERVAL)           # BATTLE_TICKS_PER_WORLD_FRAME=INT_MAX → 同步跑完

func _on_battle_finished(timeline):
    _dump_timeline_events(timeline)      # 一次性 console dump
    _animator.play(timeline, _world_view.get_unit_views())
```

### SkillPreviewProcedure 的关键方法

`_broadcast_projectile_events` 下沉为 `HexWorldGameplayInstance.broadcast_projectile_events()` 公共方法（`HexBattleProcedure` 与 `SkillPreviewProcedure` 共用，避免两处内联相同 collect+match+process_post_event 段）。

`_still_executing` 不再做独立全量扫描 —— `tick_once` 循环里跑 `ability_set.tick_executions` 后顺带累积 `any_ability_executing`，投射物由 `_any_projectile_flying` 单独只扫一遍。省掉每 tick 对 `world.get_actors()` 里所有 CharacterActor + 其 abilities 的第二次遍历。

```gdscript
func _start_recorder():
    # 走 start_recording(actors, configs, map_config) 保留 initial_actors,
    # 不走 start_recording_events_only —— Animator.play 消费 timeline 时
    # BattleRecord.from_dict 需要 initial_actors 还原 director 内部 unit state。
    ...

func start():
    super.start()
    var caster := world.get_actor(_caster_id) as CharacterActor
    for passive_cfg in _passive_configs:
        caster.ability_set.grant_ability(Ability.new(passive_cfg, caster.get_id()), world)
    var ability := Ability.new(_ability_config, caster.get_id())
    caster.ability_set.grant_ability(ability, world)
    caster.ability_set.receive_event({
        kind: ABILITY_ACTIVATE_EVENT, sourceId: caster.get_id(),
        abilityInstanceId: ability.id, target_actor_id: _target_id, logicTime: 0,
    }, world)

func tick_once():
    _current_tick += 1
    world.base_tick(_tick_interval)
    var any_ability_executing := false
    for pid in _participant_ids:
        var cchar := _get_actor(pid) as CharacterActor
        cchar.ability_set.tick(_tick_interval, cur_logic_time)
        cchar.ability_set.tick_executions(_tick_interval, world)
        if not any_ability_executing:
            for ability in cchar.ability_set.get_abilities():
                if not ability.is_expired() and ability.get_executing_instances().size() > 0:
                    any_ability_executing = true
                    break
    world.broadcast_projectile_events()
    record_current_frame_events()
    if _current_tick >= MAX_TICKS: mark_finished(); return
    if not (any_ability_executing or _any_projectile_flying(world)):
        if _post_countdown < 0: _post_countdown = POST_EXECUTION_TICKS
        else:
            _post_countdown -= 1
            if _post_countdown <= 0: mark_finished()
```

### SkillPreviewWorldGI.reset

```gdscript
func reset() -> void:
    var aids: Array[String] = []
    for a in _actors:
        aids.append(a.get_id())
    for aid in aids:
        actor_removed.emit(aid)          # -> WorldView queue_free view
    _actors.clear()
    _actor_id_2_actor_dic.clear()
    _systems.clear()
    grid = null
    _logic_time = 0.0
    _queued_caster_id = ""
    _queued_ability_config = null
    _queued_target_id = ""
    _queued_passives = []
```

### logger 下沉

```gdscript
# hex_world_gameplay_instance.gd 新增字段:
var logger: HexBattleLogger = null

# hex_battle.gd 原 var logger 声明删除, 仅保留 _on_battle_finished 里赋值:
func _on_battle_finished(timeline):
    ...
    logger = _hex_procedure.logger   # 实际写的是父类字段, shadow 消失
```

## 验证

| 测试 | 结果 |
|---|---|
| `addons/logic-game-framework/tests/run_tests.tscn` | 59/59 ✅ |
| `tests/smoke_frontend_main.tscn` | PASS（Logic battle completed in 156 ticks） |
| `tests/smoke_skill_scenarios.tscn` | 9/9 ✅ |
| `tests/smoke_world_view.tscn` | PASS（views 1 → 0） |
| `tests/smoke_skill_preview_reactive.tscn` | PASS（3 场连续, view/animator 实例复用 + reset 归 0）|

3 场战斗都能 emit `battle_finished(timeline)`，Animator 每场都能跑到 `playback_ended`，view 集合和 Animator 节点在场与场之间保持同一实例 ID 未被重建。

编辑器手动视觉验证（"无缝展开战斗"的 view 不重建感）在用户接手 —— 不在 headless 覆盖面内。

## 方法论总结

### "门面 vs 姊妹"：静态类型标注是隐形的 IS-A 收敛

阶段 1 把 `HexBattle` 拆成 `HexWorldGameplayInstance + HexBattleProcedure` 时，各处 action / utils 的 `battle: HexBattle` 因为 `HexBattle extends HexWorldGameplayInstance` 还 IS-A 兼容，没人报错。等阶段 3 多一个**姊妹**子类（SkillPreviewWorldGI）登场时才一次性暴露。

**规则**：当一个具体子类在 runtime 被 N 个下游访问，且该子类被重构为基类 + 子类 thin 门面时，**同步把下游静态类型标注收敛到基类**（`grep -n ": HexBattle\b"` 一把扫完批量改）。否则未来多一个姊妹子类会踩同一个坑。

### "字段下沉而非条件检查"：跨子类共用字段优先下沉父类

`logger` 字段 P3 的两个选项里，下沉到父类比每处 `is`-check 干净。一般原则：**如果字段的语义对"所有 X 的子类"都适用（即使有的子类保持默认 null），下沉到 X；而不是强迫每处调用方做类型判断**。

type-check 要留给**真正**只在某些子类才有意义的字段（比如 HexBattle 独有的 `left_team` / `right_team`）。

### "测试路径独立":scenario runner / UI / 录像走不同引擎

切 SkillPreviewBattle 还是新写 SkillPreviewProcedure，本质是"一条引擎支持所有场景 vs 每种场景一条引擎"的取舍。**当两种场景的生命周期语义冲突（destroy vs 常驻）时，硬做一条引擎只会让 API 变胖**（`run_with_config(scene_cfg, existing_world=null)` 这种兼容签名是坑）。新建一条引擎承接新场景更克制。

## 遗留

- **战斗期死亡 view 消失**（D5）：阶段 4 `ReplayPlayer` 路径或 framework 级"WorldView 战斗期冻结"开关可根治。
- **console event log 不同步推进**（D4）：`FrontendBattleAnimator` 加 `frame_changed` 转发即可同步。
- **AI 目录 `battle: HexBattle` 类型标注**（P4）：等 WorldGI 直接驱动 AI 的需求落地再改。
- **`FrontendBattleReplayScene` 仍被 `main.tscn` / `example/hex-atb-battle-frontend/main.gd` / Web 桥接用**：阶段 4 录像 v3 + ReplayPlayer 替换，阶段 5 正式切 main.tscn。
- **map SpinBox 编辑态全量重建**：`_map_radius_input / _map_orientation_option / _map_hex_size_input` 的 value_changed 现在直连 `_rebuild_world_from_model`，拖 spin 每一步都走 reset → configure_grid → add_system(ProjectileSystem new) → register_all_timelines → 每个 actor re-instantiate。对本 phase 无关键影响（改一次 spin 一次重建可接受），但连续拖动会有抖动。阶段 4/5 对编辑态 UX 不满意时补 150ms debounce Timer 或拆"只重配 grid + 重 place 现有 actor"的轻路径。
- **stringly-typed "caster" / "ally_N" / "enemy_N" / "auto" / "fixed_pos" / "A" / "B"**：散落于 `skill_preview.gd._role_id_for / _resolve_target_actor_id / _add_actor`，本 phase 大改 start 路径是抽 const 的机会但没做（preset JSON 向后兼容问题，需一次性 migrate）。阶段 4/5 心疼顺手抽。
- **`SkillPreviewBattle` 与 `SkillPreviewProcedure` 的 "tick-to-done" 逻辑两份**：scenario runner 继续走 `SkillPreviewBattle.run_with_actions`（主仓库 `scripts/` 下），内含几乎同构的"no executing + no flying projectile"判定与 `_broadcast_projectile_events` 内联。本 phase 不动 —— scenario runner 的独立 GameWorld 生命周期假设已稳。未来如果 scenario runner 也切到 WorldGI 路径，可与 SkillPreviewProcedure 合并。
