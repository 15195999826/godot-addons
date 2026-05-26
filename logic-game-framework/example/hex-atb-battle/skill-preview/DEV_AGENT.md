# Skill Preview DevAgent Debug Mode

让 AI agent 经 JSONL 文件协议在运行中的 `skill_preview.tscn` 里自主配置场景、跑战斗、读结果——目标是新技能开发循环里, AI 自己摆 actor / 加 keyframe / 起 battle / 读 timeline 验证流程与表演, 不再需要让用户手动点。

## 设计分类 (per dev-agent-scene-debug-mode SKILL Step 0)

**业务逻辑 / 数据流 / 表演验证 + Inventory UI operation loop**。

技能战斗类 action / setup ops 仍 **直调 SkillPreview 方法**，用于验证技能流程、timeline 和表演，不用真实按钮点击。

Inventory 是 Phase F 接入的 UI 操作闭环，验收目标是 `Control._get_drag_data -> _drop_data -> ItemSystem.move_item -> snapshot refresh`。因此 bag / equipment drag/drop 必须用 `drag_at` 真实输入验证；`inventory_state` / `inventory_layout_state` / `selected_actor_equipment_state` 用于结构化观察。

## 一图概览

```
Codex / Claude
  ├─ append → user://dev-agent/sessions/<id>/inbox.jsonl
  └─ read   ← user://dev-agent/sessions/<id>/outbox.jsonl
                  + screenshots/  + state-dumps/

skill_preview.tscn
  ├─ SkillPreview            (业务逻辑节点 + dev_agent_* 公共 API)
  ├─ DevAgentSceneOps        (适配器: scene op ↔ dev_agent_* / 直调函数)
  └─ DevAgentBridge          (lomolib 通用 bridge, enabled=false 默认)
```

## 启动

DevAgentBridge 默认 `enabled = false`, 用以下任一方式启用:

```powershell
# 推荐: 命令行 flag (双 -- 把后续参数交给 user_args)
godot --path . res://addons/logic-game-framework/example/hex-atb-battle/skill-preview/skill_preview.tscn -- --dev-agent

# 或者指定 session id 便于复用 inbox 文件
godot --path . res://addons/logic-game-framework/example/hex-atb-battle/skill-preview/skill_preview.tscn -- --dev-agent --dev-agent-session=skill-dev-001

# 或者: 通过项目设置 debug/dev_agent/enabled = true (谨慎, 全局生效)
```

启动后控制台打印:

```
[DevAgent] enabled
[DevAgent] session: <id>
[DevAgent] inbox: C:\...\user_data\Inkmon\dev-agent\sessions\<id>\inbox.jsonl
[DevAgent] outbox: C:\...\user_data\Inkmon\dev-agent\sessions\<id>\outbox.jsonl
```

## 通用 op (来自 lomolib bridge)

| op | 关键字段 | 说明 |
|---|---|---|
| `capture` | `label`, `width?` (默认 960), `format?` (`jpeg`/`png` 默认 jpeg), `quality?` (默认 80) | 截图到 `screenshots/`, 写绝对路径 + 实际尺寸/字节数到 outbox。默认 960×540 JPEG q=80 ≈ 25–40 KB; `width:0` 保留原始 viewport 尺寸 |
| `click_at` | `x`, `y`, `button?` | 真实 viewport 输入, 走完整 gui_input |
| `drag_at` | `from_x`, `from_y`, `to_x`, `to_y`, `steps?` | 框选 / 拖动 |
| `tap_key` | `key` | InputEventKey, 支持 "Escape" / "Enter" / 字符 |
| `wait_frames` | `frames` | 等 N 个 process frame (与 wait_for_idle 区别见下) |
| `inspect_tree` | `root?`, `max_depth?` | dump 子树 |
| `inspect_controls` | `root?`, `include_hidden?` | dump Control rects |
| `dump_node` | `path` | dump 单节点公共字段 |

## 本场景 scene op

通过 `{"op":"scene","name":"...","args":{...}}` 调用。

### Action ops (直调函数)

| name | args | 行为 |
|---|---|---|
| `start_battle` | — | 直调 `_on_start_pressed`, 跑当前 _actors 配置的战斗 |
| `reset_battle` | — | 直调 `_on_reset_pressed`, world 回到 _actors 模型并恢复初始 demo inventory |
| `replay_battle` | — | 直调 `_on_replay_pressed`, 重播上次 timeline |
| `add_enemy` | — | 等价点 `%ActorAddEnemyButton` 但直调 `_add_actor_at_next_free("B")` |
| `add_ally` | — | 等价点 `%ActorAddAllyButton` 但直调 `_add_actor_at_next_free("A")` |
| `enter_setup_mode` | — | 切回 setup workspace (战斗结束后 mode 滞留 playback 时用) |
| `wait_for_idle` | `timeout_frames?` (默认 1800) | 轮询 `_is_playing`, 等战斗 + animator 跑完。比 `wait_frames` 可靠 |
| `pause_playback` | — | 暂停回放(director)。配合 `step_playback` 做确定性定格 |
| `step_playback` | `delta_ms?` 或 `frames?` (默认 1 逻辑帧=100ms) | 暂停态按精确量推进回放一步;返回 `current_frame/total_frames/is_playing/is_ended` |
| `playback_state` | — | 只读回放状态 `{current_frame,total_frames,is_playing,is_ended}`,供步进循环判停 |

> 每个 action op 内部都自带 guard (`_is_playing` / `disabled` / `_last_timeline.is_empty()`), 不合法调用直接返回 `ok=false`。无需 AI 先 check。

#### 瞬时 VFX 定格验证回路(截一次性特效必用)

`wait_frames` 是**墙钟**、与回放时间轴无固定换算、不可定格 —— 截不到超短战斗里的一次性 VFX(斩杀爆、命中闪、投射物消失帧)。验证瞬时特效**必须**用 `pause_playback` + `step_playback` 确定性步进,每步后 `capture` 必落在该回放位置:

```jsonl
{"id":"01","op":"scene","name":"start_battle"}
{"id":"02","op":"scene","name":"wait_for_idle"}
{"id":"03","op":"scene","name":"replay_battle"}
{"id":"04","op":"scene","name":"pause_playback"}
{"id":"05","op":"scene","name":"step_playback","args":{"delta_ms":40}}
{"id":"06","op":"capture","label":"f1"}
{"id":"07","op":"scene","name":"playback_state"}
{"id":"08","op":"scene","name":"step_playback","args":{"delta_ms":40}}
{"id":"09","op":"capture","label":"f2"}
...循环 step_playback + capture + playback_state, 直到 playback_state.data.is_ended == true
```

逐步走过 VFX 触发帧时, 对应 `capture` 即定格到该特效。`delta_ms` 越小定格越细(子帧精度落在特效中段);1 逻辑帧 = 100ms。

### Setup mutation (直调 SkillPreview.dev_agent_* API, 战斗中拒绝)

| name | args | 行为 |
|---|---|---|
| `load_preset` | `name` 或 `index` | 通过 OptionButton 加载 preset (走 `_on_preset_load_selected` 完整解构) |
| `save_preset` | `name` | 保存当前 UI state 到 `user://skill_preview_presets/<name>.json` |
| `set_map` | `radius?`, `orientation?`, `hex_size?` | 改 grid, 触发 view 重排 |
| `set_controls` | `max_ticks?`, `speed?` | 改 Run footer 控件 |
| `add_actor` | `team` (A/B) | 等价 add_enemy/add_ally; 返回新 idx |
| `remove_actor` | `idx` | 删除非 caster actor; idx=0 (caster) 拒绝 |
| `select_actor` | `idx` | 选择 actor, 同步 Character panel + Inventory equipment panel |
| `set_actor_pos` | `idx`, `q`, `r` | 移动 actor; 占位冲突拒绝 |
| `set_actor_hp` | `idx`, `hp` | 改 hp |
| `set_actor_atk` | `idx`, `atk` | 改 atk |
| `set_actor_passives` | `idx`, `ids: Array[String]` | 整体替换 passive 列表 |
| `add_stone_wall` | `q`, `r` | 放石墙 |
| `remove_environment` | `idx` | 移除 environment |
| `add_keyframe` | `actor_idx`, `time_ms?`, `skill?`, `target?` | 添 keyframe; target = `{mode, index?, q?, r?}` |
| `remove_keyframe` | `actor_idx`, `kf_idx` | 删 keyframe |
| `set_keyframe` | `actor_idx`, `kf_idx`, `fields: {time_ms?, skill?, target?}` | 改 keyframe |
| `reset_world_to_model` | — | 强制按 `_actors` 数据模型重建 world 并恢复初始 demo inventory |
| `show_inventory` | — | 展开 Workspace drawer 并切到 Inventory tab, 返回 inventory layout |
| `equip_item` | `actor_idx`, `item_config_id`, `slot?` | 从 player bag 找 matching config 装备到 actor；`slot` 为 UI/command 槽位 `1..6`，缺省或 `-1` 自动找空槽 |
| `unequip_item` | `actor_idx`, `slot` | 卸下 actor 的 UI/command 槽位 `1..6`，item 回到 player bag |

### 观察 (只读, 不写场景)

| name | args | 返回 data |
|---|---|---|
| `scene_state` | — | actors / environments / map / controls / status / is_playing / button disabled |
| `world_state` | — | 当前 world 中 actor 的 id/team/pos/hp/max_hp/atk |
| `inventory_state` | — | player bag / actor equipment containers / selected actor / last inventory op result |
| `inventory_layout_state` | — | bag cells / equipment slots / status label rects, 供 `drag_at` 坐标计算 |
| `selected_actor_equipment_state` | — | 当前 selected actor 的 6 个 equipment slots |
| `timeline` | `max_events?` (默认 60) | 最近一场战斗 timeline.events 前 N 条 (flatten 成 `{frame, event}` 数组) |
| `console_log` | `max_chars?` (默认 8000) | _console_log 解析后的纯文本 |
| `setup_error` | — | `_find_preview_setup_error()` 返回的提示 |
| `list_presets` | — | OptionButton 中所有 preset 项 (index / label / path) |
| `list_skills` | — | 注册的 active / passive skill config_id 列表 |
| `control_rect` | `name` (unique 名) | 该 Control 当前 global_rect |

### Raw real-input 逃生口

| name | args | 用途 |
|---|---|---|
| `click_control` | `name` | 真实 Viewport.push_input click 目标 Control 中心。预检 (gui_get_hovered_control) 不通过会返回 `ok=false` + 报告实际遮挡节点。**仅当需要验证"按钮点击 → UI 更新链路"时使用**, 业务场景请用 action ops |

## Inventory 验收回路

Inventory tab 使用与 `item-preview` 相同的 Hex item model 和 bag/equipment 控件规则。DevAgent 验收时先 `show_inventory`，再等 2-3 帧让 TabContainer 完成 layout，随后读取 `inventory_layout_state` 计算 drag 坐标。

```jsonl
{"id":"01","op":"scene","name":"show_inventory"}
{"id":"02","op":"wait_frames","frames":3}
{"id":"03","op":"scene","name":"inventory_state"}
{"id":"04","op":"scene","name":"inventory_layout_state"}
{"id":"05","op":"drag_at","from_x":63,"from_y":831,"to_x":736,"to_y":847,"steps":18}
{"id":"06","op":"scene","name":"inventory_state"}
```

`drag_at` 只说明真实输入已派发；业务成败必须读后续 `inventory_state.last_op_success` / `last_error`。

建议 acceptance:

1. `show_inventory` + `inventory_state`: bag 至少有 seed items, actors 都有 runtime `actor_id` 和 equipment container。
2. `inventory_layout_state`: `bag_cells.size()==80`, `equipment_slots.size()==6`, 目标 cell/slot 可见。
3. `drag_at` bag slot 0 `training_sword` -> equipment slot 1: `last_op_success==true`。
4. `drag_at` `frost_orb` -> occupied slot 1: `last_op_success==false`。
5. `drag_at` `broken_stone` -> equipment slot 2: `last_op_success==false`, `last_error` 含不可装备。
6. `drag_at` equipment slot 1 -> empty bag slot: item 回到 player bag。
7. `select_actor {idx:1}` + `selected_actor_equipment_state`: actor selection 同步, slots 与 actor 隔离。
8. `add_actor` 后新 actor 有 equipment container; 装备 item 后 `remove_actor` 会卸回 bag 并 unregister container。
9. `reset_world_to_model` / `reset_battle`: inventory 恢复初始 demo seed, actor equipment containers 用新 runtime actor ids 重建且为空。
10. `start_battle` -> `wait_for_idle` -> `reset_battle`: inventory 回到初始 demo state。

## 典型新技能验证回路

```jsonl
{"id":"01","op":"scene","name":"list_skills"}
{"id":"02","op":"scene","name":"load_preset","args":{"name":"[builtin] 01_caster_strike"}}
{"id":"03","op":"scene","name":"set_keyframe","args":{"actor_idx":0,"kf_idx":0,"fields":{"skill":"skill_<your_new_id>"}}}
{"id":"04","op":"scene","name":"setup_error"}
{"id":"05","op":"capture","label":"before_start"}
{"id":"06","op":"scene","name":"start_battle"}
{"id":"07","op":"scene","name":"wait_for_idle"}
{"id":"08","op":"scene","name":"scene_state"}
{"id":"09","op":"scene","name":"timeline","args":{"max_events":120}}
{"id":"10","op":"scene","name":"console_log"}
{"id":"11","op":"capture","label":"after_battle"}
{"id":"12","op":"scene","name":"world_state"}
{"id":"13","op":"scene","name":"reset_battle"}
{"id":"14","op":"scene","name":"enter_setup_mode"}
```

`wait_for_idle` 替代 `wait_frames` —— 不用硬猜帧数。

每条命令的结果会按到达顺序追加到 `outbox.jsonl`, 每行一个 JSON object:

```json
{
  "id": "06",
  "op": "scene",
  "ok": true,
  "message": "battle started",
  "data": { "is_playing": true, "scene_op": "start_battle", "supported_ops": [...] },
  "artifacts": [],
  "time_msec": 4123,
  "session_id": "..."
}
```

## 设计边界

- **不是回归测试设施**: 这套机制不进 `tools/run_tests.ps1`, CI 不依赖, outbox 没有 PASS/FAIL 协议。
- **战斗中只读不写**: `_is_playing == true` 时所有 mutation op 直接返回 `{"ok": false}`, 防止打断 animator。
- **直调 vs 真输入**: 业务场景一律直调 (`start_battle` 等), 真输入 (`click_control` 等) 留给未来 UI-loop validation 场景。判定标准见 `.claude/skills/dev-agent-scene-debug-mode/SKILL.md` Step 0/1。
- **不要把这层接口塞进 production**: 整个 DevAgent 系是 dev-time 工具, bridge 默认 disabled, 出包/正常 F6 都看不见它。

详细 spec 见 `addons/lomolib/docs/dev-agent-debug-mode-spec.md`。
