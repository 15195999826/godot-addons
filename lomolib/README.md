# LomoLib - Godot 通用函数库

## 概述

LomoLib 是一个 Godot 4.x 通用工具库插件，提供常用的开发工具。

## 功能模块

### 1. InventoryKit - 库存框架系统

从 Unreal Engine 移植的专业库存管理框架，提供灵活的物品和容器管理。

**核心功能：**
- ✅ 权威数据源模式 - 物品系统统一管理所有物品位置
- ✅ 三种槽位管理策略 - 无序/固定槽位/网格容器
- ✅ 容器组件本地缓存 - 优化查询性能
- ✅ 灵活的配置系统 - 支持运行时配置容器类型
- ✅ 完整的信号通知 - 物品移动、添加、移除事件

**API 分层（v0.5.0+）：**
- 业务 API 走 `ItemSystem.create_item(container_id, config_id, count, slot_index) -> ItemCreateResult` /
  `ItemSystem.move_item(...) -> ItemMoveResult`，依赖 `configure_domain(ItemDomain, ItemCatalog)` 注册项目规则。
- 底层 API `ItemSystem.register_item_instance(container_id, slot_index, item_type, notify)` 跳过 catalog/domain，
  只做 base ItemInstance + location 写入，用于框架自身测试或不需要项目语义的简单 demo。

**业务 API 快速示例（项目通过 configure_domain 注册规则后）：**
```gdscript
# 1. 项目实现 ItemDomain / ItemCatalog 子类，注册项目规则（具体见 hex-atb-battle 示例）
ItemSystem.configure_domain(MyItemDomain.new(), MyItemCatalog.new())

# 2. 创建背包容器（无序，30个格子）+ 装备栏（固定槽位）
var backpack := BaseContainer.create_unordered(&"Backpack", 30)
var backpack_id := ItemSystem.register_container(backpack)
var equipment := BaseContainer.create_fixed(&"Equipment", [&"Helmet", &"Armor", &"Weapon", &"Shield"])
var equipment_id := ItemSystem.register_container(equipment)

# 3. 业务 create_item -> ItemCreateResult（catalog 必须含 config_id）
var create_result := ItemSystem.create_item(backpack_id, &"iron_sword", 1)
if not create_result.success:
    print("创建失败: ", create_result.error_message)
var sword_id := create_result.created_item_ids[0]

# 4. 业务 move_item -> ItemMoveResult
var weapon_slot := equipment.get_space_manager().get_slot_index_by_type(&"Weapon")
var move_result := ItemSystem.move_item(sword_id, equipment_id, weapon_slot)
if not move_result.success:
    print("移动失败: ", move_result.error_message)

# 5. 整场景退出/重置时清理本轮 containers/items/data
ItemSystem.reset_session()
```

**底层 API 快速示例（不需要项目规则的简单 demo / 框架自身测试）：**
```gdscript
var backpack := BaseContainer.create_unordered(&"Backpack", 30)
var backpack_id := ItemSystem.register_container(backpack)

# 底层 register_item_instance：跳过 catalog/domain，直接登记 base ItemInstance
var sword_id := ItemSystem.register_item_instance(backpack_id, -1, &"IronSword")
ItemSystem.move_item(sword_id, equipment_id, 0)  # move_item 仍可用，只是 domain.can_move_item 走 DefaultItemDomain（默认 allow）
```

**文件结构：**
- `types.gd` - 核心类型定义（ItemLocation, ItemInstance, ContainerSpaceConfig）
- `item_system.gd` - 物品系统（AutoLoad 单例，权威数据源）
- `base_container.gd` - 基础容器组件
- `space_manager.gd` - 空间管理器（UnorderedSpaceManager, FixedSlotSpaceManager, GridSpaceManager）
- `void_container.gd` - 虚空容器（ContainerID=0，存放无容器的物品）

### 2. Camera & Player - 相机和玩家控制器

从 Unreal Engine 移植的相机和玩家控制器系统，提供 RTS/战棋风格的相机控制。

**核心功能：**
- ✅ 弹簧臂相机（SpringArm3D + Camera3D）
- ✅ 缩放/旋转/移动控制
- ✅ 目标跟随（平滑插值）
- ✅ 鼠标状态机（Idle/Press/Pressing/Release）
- ✅ 射线检测（地面/可点击物体）
- ✅ 虚函数供子类重写

**快速示例：**
```gdscript
# 1. 实例化相机
var camera_scene := preload("res://addons/lomolib/camera/lomo_camera_rig.tscn")
var camera_rig := camera_scene.instantiate() as LomoCameraRig
add_child(camera_rig)
camera_rig.make_current()

# 2. 创建控制器
var controller := LomoPlayerController.new()
add_child(controller)
controller.use_camera_rig(camera_rig)

# 3. 相机控制
camera_rig.move(Vector2(1, 0))      # 向右移动
camera_rig.zoom(1)                   # 放大
camera_rig.rotate_camera(1)          # 顺时针旋转
camera_rig.begin_trace(target_node)  # 跟随目标
camera_rig.reset_camera()            # 重置

# 4. 监听事件
controller.ground_clicked.connect(func(pos, btn): print("Clicked: ", pos))
controller.actor_hovered.connect(func(actor): print("Hover: ", actor.name))
```

**继承 Controller 示例：**
```gdscript
class_name MyGameController
extends LomoPlayerController

func _custom_process(delta: float, hit_info: Dictionary) -> void:
    # 自定义游戏逻辑
    if hit_info.hit_ground and is_left_just_pressed():
        _move_selected_unit_to(hit_info.ground_position)

func _remap_hit_location(location: Vector3) -> Vector3:
    # 对齐到网格
    return Vector3(round(location.x), 0, round(location.z))
```

**文件结构：**
- `camera/lomo_camera_rig.gd` - 弹簧臂相机组件
- `camera/lomo_camera_rig.tscn` - 相机场景模板
- `player/lomo_player_controller.gd` - 玩家控制器基类
- `camera/demo/camera_demo.tscn` - 演示场景

**示例场景：** `res://addons/lomolib/camera/demo/camera_demo.tscn`

### 3. WaitGroup - 多任务同步工具

类似 Go 语言的 `sync.WaitGroup`，用于等待多个异步任务完成。

**核心功能：**
- ✅ 简单的 Add/Done 计数器机制
- ✅ 支持 `await` 协程等待
- ✅ 支持链式回调 `next()`
- ✅ 自动生命周期管理
- ✅ 调试日志支持

**快速示例：**
```gdscript
func load_resources() -> void:
    # 创建 WaitGroup
    var result = WaitGroupManager.create_wait_group(&"LoadResources")
    var wg: LomoWaitGroup = result[1]

    # 添加 3 个任务
    wg.add(3)

    load_texture(wg)
    load_audio(wg)
    load_scene(wg)

    # 等待所有任务完成
    await wg.wait()

    print("所有资源加载完成！")

func load_texture(wg: LomoWaitGroup) -> void:
    await get_tree().create_timer(1.0).timeout
    wg.done(&"LoadTexture")
```

**详细文档：** [WAIT_GROUP_USAGE.md](wait_group/WAIT_GROUP_USAGE.md)

**示例场景：** `res://addons/lomolib/wait_group/wait_group_demo.tscn`

### 4. DevAgent Debug Mode - 开发期场景调试桥

面向 Codex / 开发者的 **development-only** 调试工具。它通过 JSONL 文件让外部助手在一个真实运行中的 Godot 场景里下发命令、注入真实输入、截图、检查 Control/Node 状态，并读取结构化 outbox 结果。

**边界：**
- ✅ 用于开发期手动/探索式调试、UI 真实输入验证、截图和 runtime dump 取证
- ✅ 通用层只提供 bridge、input driver、screenshot、inspector、scene ops base
- ❌ 不接入 CI / `tools/run_tests.ps1 -Required`
- ❌ 不是回归测试框架，不提供稳定 PASS/FAIL 语义
- ❌ 不是生产功能或玩家自动化能力
- ❌ 通用 `dev_agent` 不承载具体游戏策略

**核心命令：**
```jsonl
{"id":"cmd-001","op":"capture","label":"initial"}
{"id":"cmd-002","op":"click_at","x":80,"y":100}
{"id":"cmd-003","op":"tap_key","key":"Escape"}
{"id":"cmd-004","op":"inspect_controls","label":"controls"}
```

**产物目录：**
```text
user://dev-agent/sessions/<session-id>/
  inbox.jsonl
  outbox.jsonl
  screenshots/
  node-dumps/
  state-dumps/
```

**详细规范：** [docs/dev-agent-debug-mode-spec.md](docs/dev-agent-debug-mode-spec.md)

**示例场景：** `res://addons/lomolib/dev_agent/example/dev_agent_demo.tscn`

## 安装

1. 将 `addons/lomolib` 文件夹复制到项目中
2. 打开 **项目 → 项目设置 → 插件**
3. 启用 **LomoLib** 插件

## 文件结构

```
addons/lomolib/
├── plugin.cfg                      # 插件配置
├── lomolib.gd                      # 插件主脚本
├── inventoryKit/                   # InventoryKit 模块目录
│   ├── types.gd                    # 核心类型定义
│   ├── item_system.gd              # 物品系统 (AutoLoad)
│   ├── base_container.gd           # 基础容器组件
│   ├── space_manager.gd            # 空间管理器
│   └── void_container.gd           # 虚空容器
├── camera/                         # Camera 模块目录
│   ├── lomo_camera_rig.gd          # 弹簧臂相机组件
│   ├── lomo_camera_rig.tscn        # 相机场景模板
│   └── demo/                       # 演示
│       ├── camera_demo.gd          # 演示脚本
│       └── camera_demo.tscn        # 演示场景
├── player/                         # Player 模块目录
│   └── lomo_player_controller.gd   # 玩家控制器基类
├── wait_group/                     # WaitGroup 模块目录
│   ├── wait_group.gd               # WaitGroup 核心类
│   ├── wait_group_manager.gd       # WaitGroup 管理器 (AutoLoad)
│   ├── wait_group_demo.tscn        # 示例场景
│   ├── wait_group_demo.gd          # 示例脚本
│   └── WAIT_GROUP_USAGE.md         # WaitGroup 详细文档
├── dev_agent/                      # DevAgent Debug Mode 开发期调试桥
│   ├── dev_agent_bridge.gd         # JSONL session / command dispatch
│   ├── dev_agent_input_driver.gd   # Viewport.push_input 输入注入
│   ├── dev_agent_screenshot.gd     # viewport 截图
│   ├── dev_agent_inspector.gd      # node/control dump
│   ├── dev_agent_scene_ops.gd      # 场景 adapter base
│   └── example/                    # 可运行 demo
└── README.md                       # 本文件
```

## AutoLoad 单例

启用插件后，会自动注册以下 AutoLoad：

| 名称 | 说明 |
|------|------|
| `ItemSystem` | 物品系统全局管理器（权威数据源） |
| `WaitGroupManager` | WaitGroup 全局管理器 |

## 全局类

以下类通过 `class_name` 声明，可在项目任意位置直接使用：

| 类名 | 说明 |
|------|------|
| `LomoCameraRig` | 弹簧臂相机组件 |
| `LomoPlayerController` | 玩家控制器基类 |
| `BaseContainer` | 库存容器基类 |
| `LomoWaitGroup` | 多任务同步工具 |
| `DevAgentBridge` | 开发期 JSONL 调试桥 |
| `DevAgentSceneOps` | 场景专属 DevAgent adapter 基类 |

## 版本历史

- **v0.5.0** - InventoryKit API 分层（业务 vs 底层）
  - 新增 `ItemDomain` / `ItemCatalog` / `ItemInstanceData` 扩展点
  - 新增 `ItemCreateResult` / `ItemMoveResult` 返回 contract
  - `ItemSystem.create_item()` 改为业务入口（`container_id, config_id, count, slot_index`）；
    旧 raw 创建语义迁移到 `register_item_instance(container_id, slot_index, item_type, notify)`
  - `ItemSystem.move_item()` 返回 `ItemMoveResult`（替换旧 bool 返回值）
  - `ItemSystem.configure_domain(domain, catalog)` + `reset_session()` 生命周期
  - `BaseContainer.item_moved_in` signal 补 `target_slot_index`（3 参 → 4 参）
  - `BaseContainer` 新增同容器换槽 callback `on_item_moved` + signal `item_moved_within`
- **v0.4.0** - 新增 DevAgent Debug Mode
  - JSONL inbox/outbox 开发期调试桥
  - 真实输入注入、截图、Control/Node inspector
  - 示例场景和 repo-local 接入 skill
- **v0.3.0** - 新增 Camera & Player 模块
  - 从 UE SpringArmCameraActor 移植
  - 从 UE LomoGeneralPlayerController 移植
  - 支持缩放/旋转/移动/跟随
  - 鼠标状态机和射线检测
- **v0.2.0** - 新增 InventoryKit 库存框架
  - 从 UE C++ 移植到 GDScript
  - 支持无序/固定槽位/网格三种容器类型
  - 权威数据源模式 + 组件本地缓存
- **v0.1.0** - 初始版本
  - 实现 WaitGroup 多任务同步工具

## 许可证

MIT License

## 作者

lomo
