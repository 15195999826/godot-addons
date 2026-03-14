# Grid Map Plugin

通用网格地图插件，支持多种网格类型的地图创建、寻路和渲染。

## 功能特性

- ✅ 支持 4 种网格类型：六边形（HEX）、六方向矩形（RECT_SIX_DIR）、正方形（SQUARE）、矩形（RECT）
- ✅ 统一的坐标系统（HexCoord）
- ✅ 坐标转换（coord_to_world, world_to_coord）
- ✅ 邻居查询（get_neighbors）
- ✅ 距离计算（get_distance）
- ✅ 高度系统（tile.height）
- ✅ 占用管理（is_occupied, place_occupant, remove_occupant）
- ✅ 事件系统（tile_changed, height_changed, occupant_changed）
- ✅ A* 寻路
- ✅ 2D/3D 渲染器
- ✅ Autoload 单例（GridMap）

## 支持的网格类型

| 类型 | 说明 | 邻居数 |
|------|------|--------|
| HEX | 标准六边形 | 6 |
| RECT_SIX_DIR | 六方向矩形 | 6 |
| SQUARE | 标准正方形 | 4 |
| RECT | 标准矩形 | 4 |

## 快速开始

### 1. 启用插件

在 Godot 编辑器中：
1. 打开 `Project > Project Settings > Plugins`
2. 启用 "Grid Map" 插件

### 2. 配置地图

```gdscript
# 创建配置
var config := GridMapConfig.new()
config.grid_type = GridMapConfig.GridType.HEX
config.orientation = GridMapConfig.Orientation.POINTY
config.draw_mode = GridMapConfig.DrawMode.RADIUS
config.radius = 5
config.size = 32.0

# 配置全局 GridMap
GridMap.configure(config)
```

### 3. 使用地图

```gdscript
# 创建坐标
var coord := HexCoord.new(1, 2)

# 坐标转换
var world_pos := UGridMap.coord_to_world(coord)
var hex := UGridMap.world_to_coord(world_pos)

# 邻居查询
var neighbors := UGridMap.get_neighbors(coord)  # Array[HexCoord]

# 距离计算
var distance := UGridMap.get_distance(HexCoord.new(0, 0), HexCoord.new(3, 3))

# 寻路
var pathfinding := GridPathfinding.new(UGridMap.model)
var path := pathfinding.astar_simple(HexCoord.new(0, 0), HexCoord.new(5, 5))
```

### 4. 渲染地图

#### 2D 渲染

```gdscript
# 添加 GridMapRenderer2D 节点到场景
var renderer := GridMapRenderer2D.new()
renderer.model = GridMap.model
add_child(renderer)

# 高亮格子
renderer.highlight_cell(Vector2i(1, 1), Color.RED)

# 填充格子
renderer.fill_cell(Vector2i(2, 2), Color.BLUE)
```

#### 3D 渲染

```gdscript
# 添加 GridMapRenderer3D 节点到场景
var renderer := GridMapRenderer3D.new()
renderer.model = GridMap.model
renderer.height_scale = 1.0
add_child(renderer)

# 高亮格子
renderer.highlight_cell(Vector2i(1, 1), Color.RED)

# 填充格子
renderer.fill_cell(Vector2i(2, 2), Color.BLUE)
```

## API 参考

### 核心模块

- `GridMapConfig` - 地图配置 Resource
- `GridMapModel` - 地图数据模型
- `HexCoord` - 六边形坐标值对象
- `CoordConverter` - 坐标系统转换工具（Offset, Doubled 等）
- `GridMath` - 数学运算工具
- `GridLayout` - 像素转换工具

### 寻路模块

- `GridPathfinding` - 寻路算法（A*, BFS, FOV, Raycast）

### 渲染模块

- `GridMapRenderer2D` - 2D 渲染器
- `GridMapRenderer3D` - 3D 渲染器

### Autoload

- `UGridMap` - 全局单例，提供便捷访问

## 测试

运行单元测试：

```bash
godot --headless --script addons/ultra-grid-map/tests/test_grid_map.gd
```

预期输出：

```
Tests: 6 passed, 0 failed
```

## 许可证

MIT License
