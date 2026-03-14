# Grid Map Renderer - 使用说明

## 📦 已完成的组件

### 渲染器
- ✅ `grid_map_renderer_2d.gd` - 2D 网格渲染器（支持 HEX, RECT_SIX_DIR, SQUARE, RECT）
- ✅ `grid_map_renderer_3d.gd` - 3D 网格渲染器（支持 HEX, RECT_SIX_DIR, SQUARE, RECT）

### 测试脚本
- ✅ `test_renderer_2d.gd` - 2D 测试场景脚本
- ✅ `test_renderer_3d.gd` - 3D 测试场景脚本

## 🎯 待完成：创建测试场景

测试脚本已经完成，但需要在 Godot 编辑器中手动创建场景文件并连接节点。

### 创建 2D 测试场景

1. **创建新场景**
   - 在 Godot 编辑器中，右键点击 `addons/grid-map/renderer/`
   - 选择 "New Scene"
   - 保存为 `test_renderer_2d.tscn`

2. **添加节点结构**
   ```
   TestRenderer2D (Node2D)
   ├── GridMapRenderer2D
   ├── Camera2D
   └── UI (CanvasLayer)
       └── VBoxContainer
           ├── RenderButton (Button)
           ├── HighlightButton (Button)
           ├── FillButton (Button)
           └── ClearButton (Button)
   ```

3. **配置节点**
   - **TestRenderer2D (根节点)**:
     - 附加脚本：`test_renderer_2d.gd`
   
   - **Camera2D**:
     - Enabled: true
     - Zoom: `Vector2(0.5, 0.5)` (根据需要调整)
   
   - **UI (CanvasLayer)**:
     - Layer: 1
   
   - **VBoxContainer**:
     - Anchors: 左上角
     - Position: `Vector2(10, 10)`
   
   - **按钮文本**:
     - RenderButton: "Render Grid"
     - HighlightButton: "Highlight Center"
     - FillButton: "Fill Outer"
     - ClearButton: "Clear All"

4. **连接信号**
   - RenderButton.pressed → `_on_render_button_pressed()`
   - HighlightButton.pressed → `_on_highlight_button_pressed()`
   - FillButton.pressed → `_on_fill_button_pressed()`
   - ClearButton.pressed → `_on_clear_button_pressed()`

### 创建 3D 测试场景

1. **创建新场景**
   - 在 Godot 编辑器中，右键点击 `addons/grid-map/renderer/`
   - 选择 "New Scene"
   - 保存为 `test_renderer_3d.tscn`

2. **添加节点结构**
   ```
   TestRenderer3D (Node3D)
   ├── GridMapRenderer3D
   ├── Camera3D
   ├── DirectionalLight3D
   └── UI (CanvasLayer)
       └── VBoxContainer
           ├── RenderButton (Button)
           ├── HighlightButton (Button)
           ├── FillButton (Button)
           └── ClearButton (Button)
   ```

3. **配置节点**
   - **TestRenderer3D (根节点)**:
     - 附加脚本：`test_renderer_3d.gd`
   
   - **Camera3D**:
     - Position: `Vector3(0, 500, 0)` (俯视角度)
     - Rotation: `Vector3(-90, 0, 0)` (向下看)
     - Projection: Orthogonal (可选，便于观察)
     - Size: 500 (如果使用 Orthogonal)
   
   - **DirectionalLight3D**:
     - Position: `Vector3(0, 100, 0)`
     - Rotation: `Vector3(-45, -45, 0)`
   
   - **UI 和按钮**: 与 2D 场景相同

4. **连接信号**: 与 2D 场景相同

## 🧪 测试步骤

### 2D 测试
1. 打开 `test_renderer_2d.tscn`
2. 运行场景 (F6)
3. 点击 "Render Grid" - 应该看到六边形网格线框
4. 点击 "Highlight Center" - 中心 3x3 区域应该高亮显示
5. 点击 "Fill Outer" - 外围一圈应该填充半透明蓝色
6. 点击 "Clear All" - 所有效果清除

### 3D 测试
1. 打开 `test_renderer_3d.tscn`
2. 运行场景 (F6)
3. 使用鼠标旋转相机观察网格（如果实现了相机控制）
4. 测试步骤与 2D 相同

## 📚 API 参考

### GridMapRenderer2D / GridMapRenderer3D

```gdscript
# 属性
@export var model: GridMapModel  # 地图数据模型
@export var grid_color: Color = Color.WHITE
@export var highlight_color: Color = Color.YELLOW
@export var fill_color: Color = Color(0.2, 0.6, 1.0, 0.3)
@export var line_width: float = 2.0

# 方法
func render_grid() -> void
func highlight_cell(coord: Vector2i, color: Color = highlight_color) -> void
func fill_cell(coord: Vector2i, color: Color = fill_color) -> void
func clear_highlights() -> void
func clear_fills() -> void
func clear_all() -> void
```

### 使用示例

```gdscript
# 创建渲染器
var renderer := GridMapRenderer2D.new()
add_child(renderer)

# 创建地图配置
var config := GridMapConfig.new()
config.grid_type = GridMapConfig.GridType.HEX
config.orientation = GridMapConfig.Orientation.FLAT
config.draw_mode = GridMapConfig.DrawMode.RADIUS
config.radius = 5
config.size = 50.0

# 创建地图模型
var model := GridMapModel.new()
model.configure(config)

# 设置数据模型
renderer.model = model

# 渲染网格
renderer.render_grid()

# 高亮指定格子
renderer.highlight_cell(Vector2i(0, 0), Color.RED)

# 填充指定格子
renderer.fill_cell(Vector2i(2, 2), Color(1, 0, 0, 0.5))

# 清除所有
renderer.clear_all()
```

## ⚠️ 注意事项

1. **坐标系统**:
   - 2D: X-Y 平面（标准 2D 坐标）
   - 3D: X-Z 平面（Y 轴向上）

2. **性能**:
   - 当前实现每次调用都会重绘所有内容
   - 适用于小型地图（<100 格子）
   - 大型地图可能需要优化（视锥剔除、批量绘制）

3. **材质**:
   - 3D 渲染器使用 UNSHADED 材质
   - 填充使用 ALPHA 透明度
   - 颜色通过 vertex_color 传递

## 🎨 自定义

### 修改默认颜色

在场景中选择渲染器节点，在 Inspector 中修改：
- Grid Color: 网格线框颜色
- Highlight Color: 高亮颜色
- Fill Color: 填充颜色
- Line Width: 线条宽度

### 扩展功能

参考 `grid_map_renderer_2d.gd` 和 `grid_map_renderer_3d.gd` 的实现，可以添加：
- 自定义渲染层
- 动画效果
- 鼠标交互
- 格子选择

## 🌐 支持的网格类型

渲染器支持 4 种网格类型：

| 类型 | 说明 | 邻居数 | 适用场景 |
|------|------|--------|----------|
| HEX | 标准六边形 | 6 | 策略游戏、地图编辑器 |
| RECT_SIX_DIR | 六方向矩形 | 6 | 类六边形但使用矩形格子 |
| SQUARE | 标准正方形 | 4 | 棋盘游戏、像素游戏 |
| RECT | 标准矩形 | 4 | 平台游戏、瓦片地图 |

配置示例：

```gdscript
# 六边形网格
config.grid_type = GridMapConfig.GridType.HEX
config.orientation = GridMapConfig.Orientation.POINTY  # 或 FLAT

# 正方形网格
config.grid_type = GridMapConfig.GridType.SQUARE

# 矩形网格
config.grid_type = GridMapConfig.GridType.RECT
config.rect_width = 32.0
config.rect_height = 16.0

# 六方向矩形网格
config.grid_type = GridMapConfig.GridType.RECT_SIX_DIR
config.rect_width = 32.0
config.rect_height = 16.0
```
