# Hex ATB Battle Frontend (表演层)

> ⚠ **2026-04-26 — A 层老路径下线**:`FrontendBattleReplayScene.load_replay(record)` destructive 路径已删除。当前权威 wire 示例见 `demo_frontend.gd::_on_start_battle_button_pressed`(响应式 `WorldView + BattleAnimator`)与 `example/hex-atb-battle/skill-preview/skill_preview.gd::_init_world_stack`。详见 `addons/logic-game-framework/CLAUDE.md`（World owns Battle 节）。

## 现状响应式 wire(2026-04-26 起)

```gdscript
# demo_frontend.gd 简化版,完整版见 demo_frontend.gd 源码
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

本目录是 **hex-atb-battle 示例的 3D 表演层**：把逻辑层跑出的战斗录像翻译成 3D 动画。表演框架件（Director / 翻译员基类 / 卡片 / 步进器 / 账本 / 更新器）自 adr/0013 起上提到 LGF `presentation/`，本目录是它的**第一个消费者**，只写 hex 事件方言的翻译员、私有卡片和 3D 视图（见下文「表演框架在哪」）。

设计上沿用框架的三条约束：逻辑与表演分离（逻辑层只算，不知道表演层存在）、声明式卡片（`VisualAction` 说「做什么」，view 决定「怎么做」）、录像可播放（加载 / 播放 / 暂停 / 重置）。

---

## 表演框架在哪（2026-09-24 起，adr/0013）

框架件住 LGF `addons/logic-game-framework/presentation/`（`core/` = `VisualDirector` / `ReplayDirector` / `Translator` / `TranslatorRegistry` / `ActionStepper` / `VisualState` / `ActorVisualState` / `VisualStateQuery` / `VisualUpdater` / `AnimationConfig` / `VisualEffectPayload` / `BuffSummary` / `ShieldSummary`；`actions/` = `VisualAction` + 内置 11 种 `Visual*Action`）。词表、`pump` 的 8 步顺序、7 条信号、消费方接入清单全在 [`addons/logic-game-framework/CLAUDE.md`](../../../CLAUDE.md)「Presentation layer」节，本文不复述。

hex 是第一个消费者，本目录只剩项目件（`Frontend*` 前缀）：

- **翻译员** `translators/`：12 个 `Frontend*Translator extends Translator`，认 hex 事件方言（`core/` 的 `BattleEvents` 强类型 `from_dict`），只出内置卡片、位置一律逻辑 axial `Vector2`；`FrontendDefaultRegistry.create()` 工厂装一个 `TranslatorRegistry`
- **私有卡片** `actions/cone_debug_overlay_action.gd`：`FrontendConeDebugOverlayAction`（自定义 `KIND` + `Payload` + `static apply`），animator 建好 Director 后 `updater.register_handler` 登记
- **Animator / WorldView**：`FrontendBattleAnimator` 持一个 `ReplayDirector`（注册表经构造函数注入），把 7 条信号接到 view；`FrontendWorldView` 响应式观察 world 管 unit view 生命周期
- **视图与投影** `scene/`：3D views + `FrontendHexProjection`（axial → `Vector3` 的唯一投影入口，棋盘几何由 animator 在 `load` 时从录像 `map_config` 建）

### hex 接线（Director 信号 → view）

```
VisualState（账本）
  | 7 条信号
  v
ReplayDirector（框架件，原样转发）
  |
  v
FrontendBattleAnimator（本目录）
  +-- actor_state_changed(id, state)
  |     +-- unit_view.update_state(state)      幂等 State 更新：hp 条 / 闪白 / 染色 / buff / 盾 / bump / 朝向，不推断死亡
  |     +-- unit_view.set_world_position(_project(director.get_actor_position(id)))
  +-- actor_spawned(id, state)               中途入场：view 已存在则当 state 更新，否则懒建 animator 自有的 replay unit view
  +-- actor_died(id)                         unit_view.play_death()（transition-only Event，view 用 _death_played 门控 once）
  +-- effect_spawned(kind, payload)          按 kind 分发到自有节点：
  |     floating_text       -> FloatingTextView（_project(payload.position)）
  |     attack_vfx          -> AttackVFXView
  |     projectile          -> ProjectileView
  |     cone_debug_overlay  -> ConeDebugOverlayView（hex 私有）
  +-- effect_updated(kind, id, progress, payload)
  |     attack_vfx -> update_progress(progress, payload.scale_factor, payload.alpha)
  |     projectile -> update_position(_project(payload.position))
  +-- effect_removed(kind, id)               attack_vfx / projectile -> view.cleanup() + erase
  +-- playback_ended / playback_state_changed / frame_changed   转发给 UI（FrontendPlaybackControls）
  +-- _process（播放中）: 每个 unit_view.set_world_position(_project(director.get_actor_position(id)))
        axial 浮点（含在飞插值）-> FrontendHexProjection（录像 map_config 建的 GridLayout）-> Vector3
```

Reset / Replay 复活是 session control，不走 Director 信号：`FrontendBattleAnimator.reset()` 遍历 view 调 `revive()`（见 [`../README.md`](../README.md)「事件 vs 状态边界」）。

### 扩展：新翻译员 / 私有卡片

- **新翻译员**（新事件 kind 要表演）：继承框架 `Translator`，`FrontendDefaultRegistry.create()` 里 `register` 即生效，不改 Director / ActionStepper

```gdscript
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
```

- **私有卡片**（内置 11 种卡片不够时）：照 `actions/cone_debug_overlay_action.gd` 三件套——`extends VisualAction` 定义自己的 `KIND`（声明数据）+ `static func apply(state: VisualState, action: VisualAction, progress: float, action_id: String)`（记账规则）+ `battle_animator.gd::_ready` 里 `_director.updater.register_handler(KIND, apply)`；效果节点在 `_on_effect_spawned` 按 kind 加分支

---

## 目录结构

```
hex-atb-battle/frontend/
├── README.md                          # 本文档
├── demo_frontend.gd / .tscn           # F6 入口，响应式 wire 样板（smoke_frontend_main 的基线）
├── demo_random_frontend.gd / .tscn    # 随机技能 demo
├── world_view.gd                      # FrontendWorldView：响应式 World 视图（订阅 mutation signal 管 unit view 生命周期）
├── battle_animator.gd                 # FrontendBattleAnimator：持 ReplayDirector，在已有 view 上叠加 VFX / 飘字 / 死亡动画
│
├── translators/                       # 12 个 Frontend*Translator（extends 框架 Translator）
│   └── default_registry.gd            # FrontendDefaultRegistry.create() 注册表工厂
├── actions/
│   └── cone_debug_overlay_action.gd   # hex 私有卡片：自定义 KIND + Payload + static apply
├── scene/                             # 3D views + 投影
│   ├── hex_projection.gd              # FrontendHexProjection：axial → Vector3 的唯一投影入口
│   ├── unit_view.gd                   # 单位（hp_bar / shield_bar / buff_row / name_label / facing_indicator 子 view 同目录）
│   ├── floating_text_view.gd / attack_vfx_view.gd / projectile_view.gd / cone_debug_overlay_view.gd
│   └── ...
└── ui/
    └── playback_controls.gd           # FrontendPlaybackControls 播放控制面板

框架件不在本目录：addons/logic-game-framework/presentation/{core,actions}/
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
