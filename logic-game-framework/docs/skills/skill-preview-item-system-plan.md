# Hex Item System Sandbox Plan

> 本轮目标改为：先在 hex 示例中做一个独立 `item-preview` sandbox，验证 `ItemSystem`、player bag、actor equipment slots、drag/drop 和 lifecycle。
> 暂不改 `skill_preview.gd/.tscn`。等 Claude Code 的新技能开发稳定后，再把同一套 item model 接入 `skill-preview`。

## Scope

目标：

- 新增一个独立 item 测试场景，不占用现有 `skill-preview` 主场景。
- sandbox 有一个 preview-local `Player` 概念。
- `Player` 持有一个格子背包，所有 item 占 1 格。
- item 支持 stack policy：可堆叠 item 合并数量，不可堆叠 item 各占一格。
- sandbox 内真实创建 `HexBattleActor`，每个 actor 都有一个固定槽位装备容器。
- 每个 actor equipment container 有 6 个装备槽位，槽位只编号为 `1..6`。
- UI 左侧显示 player bag，右侧显示可切换的 actor equipment panel。
- Hex 项目层直接使用全局 `ItemSystem`；项目级自定义能力通过注册 `ItemDomain` / `ItemCatalog` 提供。
- model/controller 要能在后续接入 `SkillPreviewWorldGI`，不要写死 sandbox UI。
- sandbox 场景必须接入 DevAgent Debug Mode，并用 `run-dev-scene` 做 UI 布局和 UI 操作验收。

明确不做：

- 本轮不修改 `skill_preview.gd/.tscn`。
- 不把 item / equipment 做成 `Actor`。
- 不在本轮 grant/revoke LGF `Ability`。
- 不设计 Affix / 词缀 / 装备触发技能等 skill-related 机制。
- 不修改 `Strike`、`AttackLandedEvent`、`HexBattleGeneralPassive`。
- 不实现装备属性、法球、attack effect、durability、affix、cooldown。
- 不做完整背包经济、掉落、商店、存档。
- 不做 stack split。V1 只支持整 stack 移动。
- 不做 swap；occupied equipment slot 直接拒绝。

## Why Sandbox First

- `skill_preview.gd/.tscn` 是当前新技能开发的热区，直接并行改 UI/scene 容易冲突。
- item 系统第一阶段要验证的是 `ItemSystem + containers + move/reject/cleanup`，不依赖 timeline/workbench。
- 独立 sandbox 可以先把 InventoryKit 的硬缝修干净，再接入复杂 UI。
- 后续接 `skill-preview` 时只需要写 adapter，把已验证 model 挂到 `SkillPreviewWorldGI`。

## Current Baseline

已有框架层能力：

- `ItemSystem` 已是 project autoload，是 InventoryKit 的全局 registry / location authority。
- `ItemSystem` 管理 item id、container id、item location。
- `BaseContainer` 缓存 item ids，并通过 `on_item_added` / `on_item_moved_out` / `on_item_moved_in` / `on_item_removed` 更新空间状态。
- `ContainerSpaceConfig` 支持 `UNORDERED` / `FIXED` / `GRID`。
- `FixedSlotSpaceManager` 支持 slot type -> slot index 查询。
- `ItemInstance` 已有 `item_type` 和 `metadata`；本轮保留为 framework base instance，不把 preview 规则直接塞成 core 语义。

本轮必须先处理的框架缝：

- 同容器移动目前只改 item location，不通知 container 更新旧槽/新槽状态。
- `item_moved_in` signal 没带 `target_slot_index`，UI 监听时无法知道落到哪个槽。
- 当前 `ItemSystem.create_item()` 名字过业务化；它实际只是分配 item id、创建 base `ItemInstance`、写入 `_item_map`、通知 container。计划改为底层 `register_item_instance()`。
- 新的 `ItemSystem.create_item()` 改成业务语义：接收 `container_id`、`config_id`、`count`、`slot_index`，通过 `ItemDomain` / `ItemCatalog` 创建项目级 instance data。
- 底层注册仍先调用 `can_add_item(-1, slot_index)`；装备容器不适合直接注册新实例。V1 规定 item 只通过 `ItemSystem.create_item()` 创建到 player bag，再 move 到 equipment slot。
- 当前 `ItemSystem` 没有 domain / catalog / instance data map / stack hook / snapshot hook，需要在 InventoryKit 层补扩展点。
- `ItemSystem` 是全局 autoload；sandbox exit / reset 时必须清理本轮创建的 containers/items。

## Resolved Decisions

- 装备槽位只使用 `1..6` 号槽，不命名、不分类。
- 后续接入 `skill-preview` 时，所有 scene 内 `BattleActor` 都创建 equipment container。
- occupied equipment slot 直接拒绝，不做 swap；swap 等本轮装备系统接入完成后再设计。
- 测试场景背包容量给足，V1 不设计 bag-full unload fallback。
- `Player` 是 preview-local 简单概念类；sandbox 先持有它，未来由 `SkillPreviewWorldGI` 持有同一套 model。
- 不新增 `HexItemSystem` / `FooItemSystem`。所有项目都复用一个 `ItemSystem` autoload。
- Hex 示例通过 `ItemSystem.configure_domain(HexItemDomain.new(), HexItemCatalog.new())` 注册项目规则。
- Hex 示例代码、UI、DevAgent 和测试默认只调用 `ItemSystem` 的业务 API，不直接调用底层 `register_item_instance()`。

## System Shape

### System Ownership

本轮采用一个全局 runtime + 项目扩展点：

```text
ItemSystem
  InventoryKit autoload
  generic item id / container id / location authority / item instance data owner
  calls project domain hooks for create / stack / move / destroy / snapshot

ItemDomain
  project rules object
  creates item instance data
  validates stack / move / equipment rules
  builds project snapshots
  no Node ownership, no UI, no actor/container lifecycle ownership

ItemCatalog
  project config lookup
  config_id -> id / display_name / icon_key / max_stack / item_tags / equipable
```

`ItemSystem` 继续保留为唯一 autoload。它不通过继承替换自身，而是通过 composition 注册项目规则：

```gdscript
ItemSystem.configure_domain(HexItemDomain.new(), HexItemCatalog.new())
ItemSystem.reset_session()
```

这样每个项目不需要创建自己的 `FooItemSystem`。项目只实现规则对象和 catalog，调用方仍然统一使用 `ItemSystem`。

V1 只支持一个 active item domain / session。`item-preview` 和未来 `skill-preview` 启动时负责配置 domain。

生命周期 API 必须拆开：

- `ItemSystem.reset_session()`：完整 teardown，清理本轮 tracked items、tracked containers、instance data、domain state。用于 `item-preview` exit、整场景销毁、测试清理。
- `HexPlayerInventory.reset_actor_equipment_keep_player()`：Hex 项目侧 orchestration，只清理 actor equipment containers，把装备 item 先通过 `ItemSystem.move_item()` 移回 player bag，保留 player bag、player-owned items、instance data 和 domain。用于未来 `SkillPreviewWorldGI.reset()`。

未配置 domain / catalog 的行为：

- `ItemSystem` 默认持有 no-op `DefaultItemDomain` 和 `EmptyItemCatalog`。
- `register_item_instance()` / `move_item()` / `destroy_item()` 保持可用于底层 InventoryKit 测试。
- 业务 `create_item(container_id, config_id, count, slot_index)` 必须在 catalog 可解析 `config_id` 时才成功；未配置或找不到 config 时返回 `ItemCreateResult.success == false` 和明确错误。
- `get_item_snapshot(item_id)` 在没有 project data 时只返回 base identity/location fields。

### Architecture Decisions

Chosen:

- 复用现有 `ItemSystem` autoload 作为唯一 item runtime。
- 把 `ItemSystem` 从低层 registry 升级为可配置 InventoryKit runtime。
- 用 `ItemDomain` 承接项目规则，而不是每个项目继承 / 新建一个 item system。
- 用 `ItemCatalog` 做 Type Object / Flyweight 式配置来源。
- 用 actor-owned equipment container 作为 component sidecar，key 为真实 actor id。

Rejected:

- 不新增 `HexItemSystem` / `FooItemSystem`，避免每个项目复制一套 facade。
- 不用继承替换 autoload `ItemSystem`；Godot 下继承 autoload 的替换/注册/测试隔离成本高于组合式 domain。
- 不把 item / equipment 做成 LGF `Actor`；本轮 item 只是不拥有动态外部属性的容器数据。
- 不让 UI 持有 item 权威状态；UI 只发命令并读 snapshot。
- 不让 Hex UI / DevAgent / 测试直接调底层 `register_item_instance()`，避免绕过 stack/equip/player ownership 规则。

### Shared Hex Item Model

新增可复用逻辑，先服务 `item-preview`，未来接入 `skill-preview`：

- `ItemSystem` domain extension API
- `ItemDomain`
- `ItemCatalog`
- `ItemInstanceData`
- `HexItemDomain`
- `HexPlayerInventory`
- `HexActorEquipmentContainer extends BaseContainer`
- `HexItemCatalog`
- `HexItemInstanceData`

职责边界：

- `ItemSystem`：唯一 item API，提供 business `create_item()` / `move_item()` / `destroy_item()` / `get_item_snapshot()`，同时保留底层 `register_item_instance()`。
- `ItemDomain`：框架扩展点，定义创建 data、stack、move validation、destroy cleanup、snapshot 等 hook。
- `ItemCatalog`：框架扩展点，定义 `config_id -> item config` 查询。
- `HexItemDomain`：Hex 示例规则实现，处理 stack、equipable、snapshot，不持有 actor/container 生命周期。
- `HexPlayerInventory`：保存 player bag container id、玩家 item ids、`actor_id -> equipment_container_id`；不持有 item instance data。
- `HexActorEquipmentContainer`：fixed 6-slot container，验证 item 是否可装备、目标槽是否为空。
- `HexItemCatalog`：`config_id -> item config`，本轮先用代码内静态数据。
- `HexItemInstanceData`：项目层 instance data，只放本轮需要的 `config_id` / `count`。

sandbox 必须创建真实 `HexBattleActor`，并使用 actor 自己的 runtime `actor_id` 作为 equipment container 的归属 key；不再引入 fake `PreviewItemActorRecord`。

### API Shape

项目调用入口：

```gdscript
ItemSystem.configure_domain(domain: ItemDomain, catalog: ItemCatalog) -> void
ItemSystem.reset_session() -> void
ItemSystem.create_item(container_id: int, config_id: StringName, count: int = 1, slot_index: int = -1) -> ItemCreateResult
ItemSystem.move_item(item_id: int, target_container_id: int, target_slot_index: int = -1) -> ItemMoveResult
ItemSystem.destroy_item(item_id: int) -> bool
ItemSystem.get_item_data(item_id: int) -> ItemInstanceData
ItemSystem.get_item_config(config_id: StringName) -> Dictionary
ItemSystem.get_item_snapshot(item_id: int) -> Dictionary
```

InventoryKit 底层入口：

```gdscript
ItemSystem.register_item_instance(container_id: int, slot_index: int = -1, item_type: StringName = &"", notify: bool = true) -> int
```

旧 `create_item(container_id, slot_index, item_type, notify)` 语义迁到 `register_item_instance()`；新 `create_item()` 变成业务创建入口。迁移期如果需要兼容旧 demo，可临时保留 `create_raw_item()` 或 README 示例同步改掉，避免同名函数长期双语义。

`ItemCreateResult` contract：

```text
success: bool
error_message: String
created_item_ids: Array[int]
updated_item_ids: Array[int]
remaining_count: int
```

语义：

- `created_item_ids`：本次新建的 item ids。
- `updated_item_ids`：本次 stack merge 修改过 count 的已有 item ids。
- `remaining_count`：因容量或规则限制未创建 / 未合并的数量。V1 测试背包容量足够，正常应为 `0`。

`ItemMoveResult` contract：

```text
success: bool
error_message: String
source_location: ItemLocation
target_location: ItemLocation
```

语义：

- `success == false` 时，UI / DevAgent 直接读取 `error_message` 展示或断言失败原因。
- `source_location` / `target_location` 用于 UI 刷新和 DevAgent 验收；失败时 `target_location` 表示尝试移动的目标位置。
- V1 不做 swap；目标槽被占用时返回失败 result。

### ItemDomain Contract

V1 `ItemDomain` 只提供同步、确定性的规则 hook，不做 UI、不持有 Node、不直接生成 scene 对象。

建议接口：

```gdscript
func create_instance_data(config_id: StringName, count: int) -> ItemInstanceData
func can_stack(existing_item_id: int, config_id: StringName) -> bool
func merge_stack(existing_data: ItemInstanceData, incoming_count: int, max_stack: int) -> int
func can_create_item(config_id: StringName, container_id: int, slot_index: int, count: int) -> ContainerResult
func can_move_item(item_id: int, target_container_id: int, target_slot_index: int) -> ContainerResult
func on_item_created(item_id: int, data: ItemInstanceData) -> void
func on_item_moved(item_id: int, old_location: ItemLocation, new_location: ItemLocation) -> void
func on_item_destroyed(item_id: int, data: ItemInstanceData) -> void
func build_item_snapshot(item_id: int, data: ItemInstanceData) -> Dictionary
func reset() -> void
```

`merge_stack()` 返回未合并的 remaining count；调用方据此决定是否继续创建新 stack。

`ItemSystem` 的顺序约定：

```text
create_item:
  catalog lookup
  domain.can_create_item()
  domain stack merge in target container only
  domain.create_instance_data()
  register_item_instance(notify=false)
  _item_data_by_id[item_id] = data
  mirror debug metadata
  container.on_item_added()
  domain.on_item_created()
  emit item_created

move_item:
  domain.can_move_item()
  target_container.can_add_item()
  container callbacks
  location update
  domain.on_item_moved()

destroy_item:
  container callback
  domain.on_item_destroyed()
  _item_data_by_id.erase(item_id)
  base item map erase
```

关键约束：业务 `create_item()` 不能在写入 `_item_data_by_id` 前触发 container callback 或 public signal。否则 UI / DevAgent / container listener 可能在 `item_created` 或 `item_added` 时读到缺失的 project instance data。

### Item Instance Design

UE 参考：

- `FItemBaseInstance` 只包含 `ItemID` 和 `ItemLocation`；InventoryKit core 只负责 identity / location。
- DESKTK 项目侧用 `FDESKTKItemInstance` 扩展实例数据：`Row`、`Count`、`ChargeTimes`、`MaxChargeTimes`、`bAutoDestroy`、`bCanRecharge`、`Affixes`、`RuntimeAttribute`。
- `Affixes` 在 UE 项目里是词缀/附魔类实例数据，通常会修改属性或触发额外效果；本计划不引入。
- `UDESKTKItemSystem` 额外维护 `ItemInstanceMap: item id -> FDESKTKItemInstance`，`CreateItem()` 时根据 config clamp `Count` / durability / charge 等运行时数据。
- container 回调拿到 base instance 后，如果需要 game semantics，再通过 item system 用 item id 查询项目侧 instance data。

Godot V1 对应设计：

- `addons/lomolib/inventoryKit/ItemInstance` 继续保持 framework base instance：`item_id`、`location`、`item_type`。
- InventoryKit 新增 `ItemInstanceData` base，`ItemSystem` 维护 `item_id -> ItemInstanceData`。
- Hex 侧新增 `HexItemInstanceData extends ItemInstanceData`，由 `HexItemDomain` 创建。
- `ItemInstance.metadata` 只做 debug / DevAgent snapshot mirror，不作为装备规则的权威数据。
- `HexActorEquipmentContainer` 不直接解释 `metadata`；它通过 `ItemSystem.get_item_data(item_id)` 和 `ItemSystem.get_item_config(config_id)` / `ItemSystem.get_item_snapshot(item_id)` 判断 item 是否可装备。

V1 instance data：

```text
config_id: StringName
count: int
```

V1 config-derived snapshot：

```text
display_name: String
stackable: bool
max_stack: int
equipable: bool
```

`stackable` 是 snapshot/UI 字段，由 `max_stack > 1` 推导；catalog config 不单独存 `stackable`。

预留但本轮不实现：

```text
charge_times: int
max_charge_times: int
auto_destroy: bool
can_recharge: bool
runtime_attributes: Dictionary
```

不进入本计划：

```text
affixes: Array[StringName]
granted_ability_ids: Array[StringName]
attack_effect_ids: Array[StringName]
```

创建规则：

- `ItemSystem.create_item(player_bag_container_id, config_id, count, bag_slot)` 先查注册的 `ItemCatalog`。
- stackable item 只在目标 container 内合并已有 stack，`count` 不超过 `max_stack`；不会跨 actor equipment container 或其他背包合并。
- 剩余数量先通过 `ItemDomain.create_instance_data(config_id, count)` 创建 `HexItemInstanceData`。
- 然后通过 `ItemSystem.register_item_instance(player_bag_container_id, slot, config_id, notify=false)` 创建 base instance。
- base instance 创建成功后，由 `ItemSystem` 写入 `_item_data_by_id[item_id]`，再触发 container callback / public signal。
- 如果 item 被 `ItemSystem.destroy_item()` 或本轮 cleanup 销毁，必须同步删除 `_item_data_by_id[item_id]`。
- Hex 代码禁止直接调用 `register_item_instance()` 创建业务 item；只能走 `ItemSystem.create_item()`。

### Player Inventory

`Player` 是 preview-local controller/data holder，不是 `Actor`。具体落码可用 `HexPlayerInventory` 表达这个概念。

职责：

- 创建并注册 player bag container。
- 维护 player bag container id 和 player-owned item ids。
- 提供 `register_actor(actor_id, equipment_container_id)` / `unregister_actor(actor_id)`。
- 负责 actor equipment container lifecycle：创建、登记、卸回背包、unregister。
- 提供 `reset_actor_equipment_keep_player()`，用于保留 player bag 时清理并重建 actor equipment containers。
- 在 sandbox reset / exit 时清理本轮 containers/items。

不负责：

- 不维护 `item_id -> HexItemInstanceData`；该 map 归 `ItemSystem`。
- 不解释 stack / equipable 规则；规则归 `ItemDomain`。
- 不持有 UI 节点引用。

业务操作统一通过 `ItemSystem`：

```text
create_item -> catalog lookup / stack merge / base instance register / data map write
move_item -> domain move validation / container validation / location update
destroy_item -> domain cleanup / data map cleanup / container cleanup
get_item_snapshot -> domain snapshot builder
```

### Player Bag

背包是 grid container。

V1 建议：

```text
Grid: 10 columns x 8 rows
Item size: always 1 slot
Stack: HexItemInstanceData.count / HexItemCatalog.max_stack
```

背包容量按测试场景给足，正常流程不应遇到卸装时 bag full。

背包 UI 使用 merged snapshot，不直接读 raw metadata：

```text
item_config_id: StringName
display_name: String
stackable: bool
count: int
max_stack: int
equipable: bool
container_id: int
slot_index: int
```

`ItemSystem` 负责 id/location/container 和 instance data ownership；item game semantics 由注册的 `ItemDomain` + `ItemCatalog` 解释。

### Actor Equipment Containers

sandbox 中真实创建 `HexBattleActor`，每个 actor 创建一个 fixed container。

后续接入 `skill-preview` 时沿用同一规则：所有 scene 内 `HexBattleActor` / `BattleActor` 都用自己的 runtime `actor_id` 注册 equipment container。

V1 六槽：

```text
slot_1
slot_2
slot_3
slot_4
slot_5
slot_6
```

UI 显示 `1..6`，底层 `slot_index` 仍按 `0..5` 存储；UI / DevAgent adapter 负责把 slot label / command 参数转换成 InventoryKit slot index。

容器职责：

- 只接受 catalog 判定 `equipable == true` 的 item。
- 只接受空槽；occupied slot 直接拒绝，不做 swap。
- V1 不校验职业、部位、等级、阵营、actor type 或技能授予。
- 缓存装备中的 item ids。
- 只做位置与 UI 状态同步，不产生战斗效果。
- actor 删除时，装备容器中的 item 通过 `ItemSystem.move_item()` 移回 player bag。
- bag 容量足够大；如果卸回失败，视为 lifecycle bug，记录错误并阻断静默丢 item。
- unregister equipment container。

### Item Catalog

本轮先用 `HexItemCatalog` 代码内静态数据，并通过 `ItemSystem.configure_domain()` 注册，不引入 Resource / data table。

最小 config 字段固定为：`id` / `display_name` / `icon_key` / `max_stack` / `item_tags` / `equipable`。

最小样例：

```text
training_sword
  id: training_sword
  display_name: Training Sword
  icon_key: sword
  max_stack: 1
  item_tags: [equipment]
  equipable: true

frost_orb
  id: frost_orb
  display_name: Frost Orb
  icon_key: orb
  max_stack: 1
  item_tags: [equipment]
  equipable: true

minor_rune
  id: minor_rune
  display_name: Minor Rune
  icon_key: rune
  max_stack: 9
  item_tags: [equipment, rune]
  equipable: true

broken_stone
  id: broken_stone
  display_name: Broken Stone
  icon_key: stone
  max_stack: 99
  item_tags: [material]
  equipable: false
```

`frost_orb` 本轮只是一个可装备 item，不触发 attack effect。

## Sandbox UI Contract

建议路径：

```text
addons/logic-game-framework/example/hex-atb-battle/item-preview/item_preview.tscn
addons/logic-game-framework/example/hex-atb-battle/item-preview/item_preview.gd
addons/logic-game-framework/example/hex-atb-battle/item-preview/item_preview_agent_ops.gd
addons/logic-game-framework/example/hex-atb-battle/item-preview/DEV_AGENT.md
```

布局：

```text
Item Preview
  Left: Player Bag Grid
  Right: Actor Equipment Panel
```

左侧 bag：

- grid cell 显示 item name / short label。
- stackable item 显示 count badge。
- empty cell 可作为 drag return target。

右侧 actor panel：

- actor selector：sandbox 固定 2-3 个真实 `HexBattleActor`。
- equipment slots：6 个固定 slot。
- 切换 actor 后，slot 状态从对应 actor equipment container 读取。

拖拽规则：

- bag -> empty equipment slot：`ItemSystem.move_item(item_id, actor_equipment_container_id, slot_index)`。
- equipment slot -> bag empty slot：`ItemSystem.move_item(item_id, player_bag_container_id, slot_index)`。
- non-equipable item 或 invalid slot：拒绝移动，UI 使用 `ItemMoveResult.error_message` 给简短错误。
- occupied equipment slot：V1 拒绝，不自动 swap。
- stack item：拖拽整 stack。

## DevAgent Contract

`item-preview` 必须从第一版开始就是 DevAgent-enabled scene。

设计分类：

- 这个场景的核心验收是 **UI operation -> UI update loop** 和 **UX correctness**。
- 数据 setup / reset / seed 可以用 direct scene op。
- 背包格子点击、装备槽点击、drag/drop、hover / hit-test / layout reachability 必须走 real input 或 raw input op，不能用 direct call 绕过 UI bug。

必须提供的文件：

- `item_preview_agent_ops.gd`：scene-specific adapter。
- `DEV_AGENT.md`：说明启动方式、op 表、snapshot 字段、每个 action 后应该观察哪些字段。

必须提供的 scene ops：

```text
Observation:
  state
  inventory_state
  layout_state
  selected_actor_state

Setup / action:
  reset_sandbox
  seed_items
  select_actor

Raw real-input:
  click_control
  drag_item
  click_at
  drag_at
  tap_key
  capture
  inspect_controls
  inspect_tree
  dump_node
```

`state` / `inventory_state` 返回值必须包含：

- player bag container id。
- item id、config id、display name、count、max stack、stackable、equipable、slot index、container id。
- actor id / display name。
- 每个 actor equipment container id。
- 1..6 slot 的 item id 或 empty。
- last error / last operation result。
- `supported_ops`。

`layout_state` 返回值必须包含：

- bag grid root rect。
- 每个可见 bag cell rect。
- actor selector rect。
- 当前 actor equipment panel rect。
- 1..6 equipment slot rect。
- 当前 hovered / focused / modal blocker 信息，如果 adapter 能拿到。

## DevAgent Acceptance Flow

`Phase D` 完成后，必须用 `run-dev-scene` 验证，不只靠人工编辑器观察。

验收流程：

```text
1. 启动 item_preview.tscn -- --dev-agent --dev-agent-session=<slug>
2. 读取 DEV_AGENT.md，先调用 state 获取 supported_ops
3. 调用 seed_items / inventory_state 验证数据初始化
4. 调用 inspect_controls / layout_state 验证 bag 与 equipment panel 可见且不重叠
5. 用 real input drag_item 或 drag_at：bag equipable item -> actor slot 1
6. inventory_state 验证 item location 到 equipment container slot 0
7. 用 real input drag_item 或 drag_at：另一个 item -> 已占用 slot 1
8. inventory_state / last error 验证 occupied slot 被拒绝
9. 用 real input drag_item 或 drag_at：non-equipable item -> actor slot 2
10. inventory_state / last error 验证 non-equipable 被拒绝
11. 切换 actor，验证装备状态隔离
12. 从 equipment slot 拖回 bag，验证位置恢复
13. capture 只在布局/视觉状态需要人工确认时使用
14. stop Godot process
```

## Data Flow

```text
ItemPreview seed
  -> ItemSystem.configure_domain(HexItemDomain, HexItemCatalog)
  -> ItemSystem.create_item(player_bag_container_id, config_id, count)
  -> ItemDomain merges existing stacks in player bag only if possible
  -> ItemDomain.create_instance_data(config_id, stack_count)
  -> ItemSystem.register_item_instance(player_bag_container_id, slot, config_id, notify=false)
  -> ItemSystem._item_data_by_id[item_id] = HexItemInstanceData
  -> BaseContainer.on_item_added()
  -> ItemInstance.metadata mirrors debug snapshot
  -> UI reads ItemSystem snapshots

Drag bag item to actor slot
  -> UI resolves target actor equipment container + slot index
  -> ItemSystem.move_item(item_id, equipment_container_id, slot_index)
  -> ItemDomain can reject project-level invalid moves
  -> HexActorEquipmentContainer validates via ItemSystem data + HexItemCatalog
  -> source BaseContainer.on_item_moved_out()
  -> target HexActorEquipmentContainer.on_item_moved_in()
  -> UI refreshes from ItemSystem snapshot
```

## Implementation Phases

### Phase Diff Overview

| Phase | 改动层 | 主要差分 | 明确不做 |
|---|---|---|---|
| A | `addons/lomolib/inventoryKit` | 把 `ItemSystem` 从 raw registry 升级为可配置业务入口，补 domain/catalog/data/result contract | 不写 Hex 规则，不写 UI |
| B | `example/hex-atb-battle` model | 实现 Hex item domain、catalog、instance data、player bag、actor equipment containers | 不接 `skill-preview`，不做 drag/drop UI |
| C | `item-preview` scene UI | 新增独立 item sandbox，做 bag/equipment 面板和真实 UI 拖拽 | 不接 LGF skill effect，不做装备授予技能 |
| D | DevAgent adapter | 给 `item-preview` 接入 scene debug mode 和 structured ops | 不绕过真实 UI 输入路径 |
| E | validation | 跑 data smoke、scene boot、`run-dev-scene` UI 操作验收 | 不靠人工观察替代验收 |
| F | `skill-preview` integration | 把已验证 model 接入真实 SkillPreview lifecycle | 不重做 item model，不引入 swap |

### Phase A - InventoryKit Hardening

目标：让现有 `ItemSystem` 足够可靠地支撑 sandbox 和未来 `skill-preview` UI。

差分：

- 修改 `addons/lomolib/inventoryKit` 内的 framework item runtime。
- `create_item()` 从 raw 创建语义改为 business 创建语义。
- raw 创建语义迁移到 `register_item_instance()`。
- 新增 `ItemCreateResult` / `ItemMoveResult` / `ItemDomain` / `ItemCatalog` / `ItemInstanceData`。
- 增加 domain/callback/signal 顺序约束和 smoke 覆盖。

- 增加 `ItemSystem.register_item_instance()`，把当前 `create_item()` 的底层登记逻辑迁进去。
- 将 `ItemSystem.create_item()` 重新定义为业务创建入口：`container_id + config_id + count + slot_index`。
- 增加 `ItemCreateResult`，返回 created / updated / remaining count，供 UI 和 DevAgent 稳定验收。
- 增加 `ItemDomain` / `ItemCatalog` / `ItemInstanceData` base classes。
- 增加 no-op `DefaultItemDomain` 和 `EmptyItemCatalog`；未配置 catalog 时 business `create_item()` 明确失败，但 raw `register_item_instance()` 仍可用于底层测试。
- 增加 `ItemSystem.configure_domain(domain, catalog)` 和 `ItemSystem.reset_session()`。
- 增加 `ItemSystem._item_data_by_id`，由 domain 创建、由 ItemSystem 持有和清理。
- 增加 domain hooks：create data、stack merge、move validation、destroy cleanup、snapshot builder。
- 业务 `create_item()` 的 callback 顺序必须保证 `_item_data_by_id` 已写入后才触发 container callback / public signal。
- 将 `ItemSystem.move_item()` 的返回值定义为 `ItemMoveResult`，让 UI / DevAgent 能读取失败原因和移动前后位置。
- 给 `BaseContainer` 增加同容器移动 callback，例如 `on_item_moved(old_slot, new_slot)`。
- `ItemSystem.move_item()` / `_move_item_within_container()` 先调用 domain validation，再调用 container validation 和 callbacks。
- `item_moved_in` signal 补 `target_slot_index`。
- 明确 container unregister 的 destructive 语义；Hex model 清理时先转移 / destroy tracked items，再 unregister。
- 加最小 smoke：create -> move bag/equipment -> move within grid -> destroy/unregister。

边界：

- 不新增 `HexItemSystem`。
- 不实现 Hex catalog 静态数据。
- 不创建 preview scene。

### Phase B - Hex Domain Model

目标：先跑通无 UI 的 player bag + actor equipment。

差分：

- 在 `example/hex-atb-battle` 增加 Hex 项目侧 item model。
- 用 `ItemSystem.configure_domain(HexItemDomain, HexItemCatalog)` 注册项目规则。
- 创建 preview-local `HexPlayerInventory`，由它持有 player bag 与 actor equipment container lifecycle。
- sandbox 创建真实 `HexBattleActor`，用 actor 自己的 runtime `actor_id` 绑定 equipment container。

- 实现 `HexItemDomain extends ItemDomain`。
- 实现 `HexItemCatalog extends ItemCatalog`。
- 实现 `HexItemInstanceData extends ItemInstanceData`。
- 实现 preview-local `HexPlayerInventory`。
- 初始化 grid bag。
- 创建 2-3 个真实 sandbox `HexBattleActor`。
- 为每个 actor id 创建 fixed equipment container。
- actor equipment container lifecycle 放在 `HexPlayerInventory` / scene orchestration，不放进 `HexItemDomain`。
- 实现 `HexPlayerInventory.reset_actor_equipment_keep_player()`。
- actor 删除时通过 `ItemSystem.move_item()` 同步清理 equipment container。
- seed 样例 item。
- 验证 Hex 项目层只通过 `ItemSystem` 业务 API 操作 item，不直接调用 `register_item_instance()`。

边界：

- 不接入 `skill_preview.gd` / `skill_preview.tscn`。
- 不做 UI drag/drop。
- 不做装备赋予技能、attack effect、affixes。
- 不支持 swap。

### Phase C - Item Preview Sandbox UI

目标：让用户能在独立 sandbox 里操作装备，不碰 `skill-preview`。

差分：

- 新增独立 `item-preview` scene，作为本轮 item system 验证入口。
- UI 左侧只读写 player bag snapshot，右侧按 actor selector 读取对应 equipment container。
- drag/drop 只调用 `ItemSystem.move_item()`，失败展示 `ItemMoveResult.error_message`。

- 新增 `item_preview.tscn` / `item_preview.gd`。
- 左侧绘制 player bag grid。
- 右侧绘制 actor selector + 6 slots。
- 支持 bag -> equipment、equipment -> bag drag/drop。
- 所有 UI 状态从 `ItemSystem.get_item_snapshot()` / container cache 读取，不维护第二份权威状态。

边界：

- 不占用 `skill-preview` 热区。
- 不通过 UI 直接改 container cache 或 item metadata。
- occupied equipment slot 只拒绝，不做自动交换。

### Phase D - DevAgent Debug Mode

目标：让 `item-preview` 可以被 AI agent 通过 JSONL 驱动，覆盖 UI 布局和 UI 操作验收。

差分：

- 给 `item-preview` 新增 scene-specific DevAgent adapter。
- 暴露 structured observation，方便验收 layout 和 item state。
- 暴露 real-input ops，用真实点击/拖拽路径验证 UI。

- 按 `dev-agent-scene-debug-mode` 给 `item_preview.tscn` 接入 scene-specific adapter。
- 新增 `item_preview_agent_ops.gd`。
- 新增 `DEV_AGENT.md`。
- 在 adapter doc comment 中写明场景分类：UI operation -> UI update loop / UX correctness。
- 提供 `state` / `inventory_state` / `layout_state` 等 structured observation ops。
- 提供 `click_control` / `drag_item` / `drag_at` 等 real-input ops。
- 验证 `capture`、`inspect_controls`、`inspect_tree`、`dump_node` 可用。
- DevAgent 默认 disabled，只通过 `-- --dev-agent` 或 debug setting 启用。

边界：

- DevAgent 不作为 gameplay automation。
- 不提供绕过 UI 状态机的直接 equip/unequip shortcut，除非只用于只读 inspection。

### Phase E - Sandbox Validation

目标：确认 `item-preview` 的数据层、场景加载、UI 操作闭环可重复通过。

差分：

- 新增/更新最小 smoke 覆盖 ItemSystem contract。
- 新增 scene boot 验证。
- 用 `run-dev-scene` 跑真实 UI 操作验收。

必测：

- player bag 创建并显示 seed items。
- stackable item 合并数量；不可堆叠 item 占不同格。
- 每个 sandbox `HexBattleActor` 都有 6 个 equipment slots。
- equipment slots 显示为 `1..6`，没有语义命名。
- 拖拽 equipable item 到空装备槽成功，item location 更新到 actor equipment container。
- 拖拽到 occupied slot 被拒绝，不触发 swap。
- non-equipable item 被拒绝。
- 切换 actor 后装备状态正确隔离。
- 从装备拖回 bag 成功。
- reset / exit 后 `ItemSystem` 不残留本轮 containers/items。

建议测试入口：

- Headless smoke 验证 `ItemSystem` / container 数据 contract。
- 独立 scene boot check 验证 `item_preview.tscn` 可加载。
- 用 `run-dev-scene` 驱动 `item-preview`，通过 `inventory_state` / `layout_state` / real input 验证 drag/drop UI。
- Editor 视觉检查只作为补充，不替代 DevAgent 验收。

边界：

- 不因为 UI 肉眼可见就跳过 DevAgent 操作验收。
- 不在验证 Phase 临时改规则；失败要回到对应 Phase 修因。

### Phase F - SkillPreview Integration

前置条件：Claude Code 的新技能开发不再长期占用 `skill-preview` 热区。

目标：把 sandbox 已验证 model 接入真实 `skill-preview`。

差分：

- 在 `SkillPreviewWorldGI` / `skill_preview.gd` lifecycle 中接入已验证的 `ItemSystem` + Hex domain model。
- actor add/remove/reset 时同步管理 equipment containers。
- 保留 player bag 和 player-owned items，只重建 scene actor equipment。

- `SkillPreviewWorldGI` / `skill_preview.gd` 启动时配置 `ItemSystem.configure_domain(HexItemDomain, HexItemCatalog)`。
- `SkillPreviewWorldGI` 持有同一套 `HexPlayerInventory`。
- `SkillPreviewWorldGI.add_actor()` 后，为所有 scene 内 `HexBattleActor` / `BattleActor` 注册 equipment container。
- `SkillPreviewWorldGI.remove_actor()` 前，通过 `ItemSystem.move_item()` 把装备 item 移回 player bag 并 unregister container。
- `SkillPreviewWorldGI.reset()` 调用 `HexPlayerInventory.reset_actor_equipment_keep_player()`，保留 player bag 和 player-owned items，只清理并重建 actor equipment containers。

边界：

- 不重写 `item-preview` 已验证的数据规则。
- 不引入 swap。
- 不在本轮接装备授予技能效果；只为后续 equipment attack effects 留好数据入口。
- `skill_preview.gd/.tscn` 增加 Inventory tab/panel，复用 sandbox UI 组件或逻辑。
- 点击 battle actor 时，同步右侧 actor equipment panel。

## Boundaries For Later

- swap 设计。
- stack split。
- item/equipment Resource 化。
- 多 active item sessions / 多 world 并行。
- 装备 grant/revoke skill。
- 装备 attack effect。
- Affix / 词缀 / 附魔。
- 装备属性被外部 Buff/Aura 动态修改时，是否把 equipment 提升为 Actor。
