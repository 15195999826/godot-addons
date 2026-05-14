# Skill Preview DevAgent Debug Mode

让 AI agent 经 JSONL 文件协议在运行中的 `skill_preview.tscn` 里自主配置场景、跑战斗、读结果——目标是新技能开发循环里, AI 自己摆 actor / 加 keyframe / 起 battle / 读 timeline 验证流程与表演, 不再需要让用户手动点。

## 设计分类 (per dev-agent-scene-debug-mode SKILL Step 0)

**业务逻辑 / 数据流 / 表演验证**。AI 的目标是验证新技能的战斗效果, 不是 SpinBox / Button 自身的 UX。因此所有 action / setup ops **直调 SkillPreview 方法**, 不走 `Viewport.push_input`。`click_control` 作为 raw 真输入逃生口保留, 将来真要做"按钮点击 → UI 更新链路"validation 时再用。

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
| `capture` | `label` | 截图到 `screenshots/`, 写绝对路径到 outbox |
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
| `reset_battle` | — | 直调 `_on_reset_pressed`, world 回到 _actors 模型 |
| `replay_battle` | — | 直调 `_on_replay_pressed`, 重播上次 timeline |
| `add_enemy` | — | 等价点 `%ActorAddEnemyButton` 但直调 `_add_actor_at_next_free("B")` |
| `add_ally` | — | 等价点 `%ActorAddAllyButton` 但直调 `_add_actor_at_next_free("A")` |
| `enter_setup_mode` | — | 切回 setup workspace (战斗结束后 mode 滞留 playback 时用) |
| `wait_for_idle` | `timeout_frames?` (默认 1800) | 轮询 `_is_playing`, 等战斗 + animator 跑完。比 `wait_frames` 可靠 |

> 每个 action op 内部都自带 guard (`_is_playing` / `disabled` / `_last_timeline.is_empty()`), 不合法调用直接返回 `ok=false`。无需 AI 先 check。

### Setup mutation (直调 SkillPreview.dev_agent_* API, 战斗中拒绝)

| name | args | 行为 |
|---|---|---|
| `load_preset` | `name` 或 `index` | 通过 OptionButton 加载 preset (走 `_on_preset_load_selected` 完整解构) |
| `save_preset` | `name` | 保存当前 UI state 到 `user://skill_preview_presets/<name>.json` |
| `set_map` | `radius?`, `orientation?`, `hex_size?` | 改 grid, 触发 view 重排 |
| `set_controls` | `max_ticks?`, `speed?` | 改 Run footer 控件 |
| `add_actor` | `team` (A/B) | 等价 add_enemy/add_ally; 返回新 idx |
| `remove_actor` | `idx` | 删除非 caster actor; idx=0 (caster) 拒绝 |
| `set_actor_pos` | `idx`, `q`, `r` | 移动 actor; 占位冲突拒绝 |
| `set_actor_hp` | `idx`, `hp` | 改 hp |
| `set_actor_atk` | `idx`, `atk` | 改 atk |
| `set_actor_passives` | `idx`, `ids: Array[String]` | 整体替换 passive 列表 |
| `add_stone_wall` | `q`, `r` | 放石墙 |
| `remove_environment` | `idx` | 移除 environment |
| `add_keyframe` | `actor_idx`, `time_ms?`, `skill?`, `target?` | 添 keyframe; target = `{mode, index?, q?, r?}` |
| `remove_keyframe` | `actor_idx`, `kf_idx` | 删 keyframe |
| `set_keyframe` | `actor_idx`, `kf_idx`, `fields: {time_ms?, skill?, target?}` | 改 keyframe |
| `reset_world_to_model` | — | 强制按 `_actors` 数据模型重建 world |

### 观察 (只读, 不写场景)

| name | args | 返回 data |
|---|---|---|
| `scene_state` | — | actors / environments / map / controls / status / is_playing / button disabled |
| `world_state` | — | 当前 world 中 actor 的 id/team/pos/hp/max_hp/atk |
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
