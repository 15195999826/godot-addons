# Item Preview Sandbox — DevAgent Contract

`item_preview.tscn` 的 scene-specific DevAgent adapter 文档。

## Scene Classification

**UI operation → UI update loop / UX correctness**

核心验收 = 拖拽 / 点击 → `ItemSystem.move_item()` → snapshot 更新。
- 数据 setup / reset / seed: direct call (`reset_sandbox` / `seed_items` / `select_actor`)
- bag cell / equipment slot drag: real input (`drag_at` / `click_at`), 走完整 `Control._get_drag_data → _drop_data → handle_drop` 路径,不绕过任何 UI bug

## Launch

```bash
SESS_NAME="<short-task-slug>"   # e.g. item-equip-flow, occupied-reject
SESS_DIR="$APPDATA/Godot/app_userdata/Inkmon/dev-agent/sessions/$SESS_NAME"
rm -rf "$SESS_DIR" && mkdir -p "$SESS_DIR"
godot --path D:/GodotProjects/inkmon/inkmon-godot \
  res://addons/logic-game-framework/example/hex-atb-battle/item-preview/item_preview.tscn \
  -- --dev-agent --dev-agent-session=$SESS_NAME \
  > "$SESS_DIR/godot.log" 2>&1
```

inbox / outbox 路径在 godot.log 开头打印:
```
[ItemPreview] inbox:  C:\Users\...\app_userdata\Inkmon\dev-agent\sessions\<sess>\inbox.jsonl
[ItemPreview] outbox: C:\Users\...\app_userdata\Inkmon\dev-agent\sessions\<sess>\outbox.jsonl
```

每条 JSONL 命令往 `inbox.jsonl` append,scene 自动读取,结果写到 `outbox.jsonl`。

## Op Vocabulary

### Observation (read-only, no side effect)

| op | args | data 字段 |
|---|---|---|
| `state` | — | alias of `inventory_state` (兼容 run-dev-scene 默认 op) |
| `inventory_state` | — | `player_bag_id` / `bag[]` / `actors[]` / `selected_actor_idx` / `selected_actor_id` / `last_op_message` / `last_op_success` / `last_error` |
| `layout_state` | — | `window_size` / `bag_grid_rect` / `bag_cells[]{slot_index,rect}` / `equipment_panel_rect` / `equipment_slots[]{slot_index,slot_label_1_based,rect}` / `actor_selector_rect` / `status_label_rect` |
| `selected_actor_state` | — | 当前 selected actor: `actor_id` / `display_name` / `equipment_container_id` / `slots[]` / `selected_actor_idx` |

### Action / mutation

| op | args | 副作用 | 验证字段 |
|---|---|---|---|
| `reset_sandbox` | — | ItemSystem.reset_session + configure_domain + 重 init inventory + register 3 actors + 重 seed | `inventory_state.bag.size() == 5` (seed) |
| `seed_items` | — | 当前实现 = `reset_sandbox` | `inventory_state.bag.size() == 5` |
| `select_actor` | `{idx: int}` 0..2 | `_selected_actor_idx = idx` + 重绘 equipment panel | `selected_actor_state.selected_actor_idx == idx` |

### Raw real-input (走 DevAgentBridge 通用 op)

| op | args | 用途 |
|---|---|---|
| `click_at` | `{x: float, y: float, button?: int}` | 点击 (例如 ActorSelector OptionButton 切人) |
| `drag_at` | `{from_x, from_y, to_x, to_y, button?, steps?}` | 拖拽 (bag↔equipment, 走真实 _get_drag_data → _drop_data) |
| `tap_key` | `{key: string}` | 键盘 |
| `capture` | `{label?, width?, format?, quality?}` | 截图 |
| `inspect_controls` | `{root?, include_hidden?}` | 验证 Control 树可见性 / rect 重叠 |
| `inspect_tree` | `{root?, max_depth?}` | 验证场景 tree 结构 |
| `dump_node` | `{path}` | 单 node detail |

## Snapshot 字段 -> action op 触发 -> 期望 verify 字段

| 触发 op | 后续 observation | 期望字段变化 |
|---|---|---|
| `reset_sandbox` / `seed_items` | `inventory_state` | `bag.size() == 5`, `selected_actor_idx == 0`, `last_op_success == true` |
| `select_actor {idx: N}` | `selected_actor_state` | `selected_actor_idx == N` |
| `drag_at` bag → eq slot (equipable) | `inventory_state` | bag 少 1 item, 对应 actor slots 多 1 item; `last_op_success == true` |
| `drag_at` bag → 已占用 slot | `inventory_state` | bag / equipment 不变;`last_op_success == false`;`last_error` 含 "槽位 N 不可用" |
| `drag_at` bag (non-equipable) → eq slot | `inventory_state` | bag / equipment 不变;`last_op_success == false`;`last_error` 含 "不可装备" |
| `drag_at` 跨 actor 切换 (`select_actor` 后) | `selected_actor_state` | slots 内容随 actor 切换变化 (装备隔离) |

## Drag 坐标计算

每个 bag cell / equipment slot 的 `rect` 都在 `layout_state` 内。drag from/to 用 cell rect 中心:

```python
# bag cell N
bag_cell = layout_state["bag_cells"][N]   # slot_index == N
from_x = bag_cell["rect"]["x"] + bag_cell["rect"]["w"] / 2
from_y = bag_cell["rect"]["y"] + bag_cell["rect"]["h"] / 2

# equipment slot 1 (UI label)
eq_slot_0 = layout_state["equipment_slots"][0]  # slot_label_1_based == 1
to_x = eq_slot_0["rect"]["x"] + eq_slot_0["rect"]["w"] / 2
to_y = eq_slot_0["rect"]["y"] + eq_slot_0["rect"]["h"] / 2
```

drag steps 建议 ≥ 8 (Godot drag threshold ≈ 几像素 + 累计 motion ≥ 8 才触发 _get_drag_data)。

## Seed Layout

`reset_sandbox` / `seed_items` 后 bag 内容固定:

| bag slot | item | count |
|---|---|---|
| 0 | training_sword (equipable, max_stack=1) | 1 |
| 1 | frost_orb (equipable, max_stack=1) | 1 |
| 2 | minor_rune (equipable, max_stack=9) | 5 |
| 3 | broken_stone (**non-equipable**, max_stack=99) | 10 |
| 10 | training_sword (第二把,验装第一把 slot 1 后还能装第二把到 slot 2) | 1 |

`selected_actor_idx == 0` (Actor 1 (Warrior)),所有 actor 装备槽空。

## Acceptance Flow 13 步

详见 `addons/logic-game-framework/docs/skills/skill-preview-item-system-plan.md` §"DevAgent Acceptance Flow"。

简要:
1. `state` → 拿 `supported_ops`
2. `seed_items` (= reset) + `inventory_state` → bag.size()==5
3. `inspect_controls` + `layout_state` → bag / equipment panel rect 可见、不重叠
4. drag bag[0] (sword) → eq slot 1 (eq_slot[0]); `inventory_state.last_op_success==true`,bag 少 sword,actor 0 slots[0] 有 sword
5. drag bag[1] (orb) → eq slot 1 (eq_slot[0],占用); `last_op_success==false`,`last_error` 含 "槽位 0 不可用"
6. drag bag[3] (stone, non-equipable) → eq slot 2 (eq_slot[1]); `last_op_success==false`,`last_error` 含 "不可装备"
7. `select_actor {idx:1}` → `selected_actor_state.slots` 全空 (Actor 1 没装备, Actor 0 才有 sword)
8. drag back: eq slot 1 (eq_slot[0] when select_actor 0) → bag 空槽; `last_op_success==true`
9. `reset_sandbox` → bag / actors 回到 seed 状态

(`select_actor 0` 切回去验证之前 actor 1 装的 sword 仍在;`reset_sandbox` 清空全部)

## Known constraints

- **不要硬编 `actor_id` 字符串** ("preview-actor-1"): 用 `selected_actor_idx` (0/1/2) 或 `display_name` 字段。Phase F 接入 SkillPreview 时 ID 变成 `HexBattleActor.get_id()` 自动生成格式。
- bag 总是 10x8 = 80 cells; equipment 总是 6 slots。layout 变了再调 layout_state。
- drag drop 到非 cell/slot 区 (panel 之间) ItemPreview root 会发 status "drop ignored: dropped on empty area",不算 fail。

## Cleanup

JSONL session 在 `user://dev-agent/sessions/<sess>/` 下,不自动清。手动:
```powershell
pwsh .claude/skills/dev-agent-scene-debug-mode/cleanup-sessions.ps1
```
