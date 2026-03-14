## InventoryKit - 容器空间配置
##
## 用于创建不同类型的容器空间管理器
class_name ContainerSpaceConfig
extends RefCounted

## 容器空间类型
var space_type: ContainerSpaceType.ContainerSpaceType = ContainerSpaceType.ContainerSpaceType.UNORDERED

## === Unordered 配置 ===
## 容量（-1 表示无限）
var capacity: int = -1

## === Fixed 配置 ===
## 固定槽位类型数组（使用 StringName 替代 UE 的 GameplayTag）
var fixed_slot_types: Array[StringName] = []

## === Grid 配置 ===
## 网格宽度
var grid_width: int = 0

## 网格高度
var grid_height: int = 0


## 创建无序容器配置
static func create_unordered(cap: int = -1) -> ContainerSpaceConfig:
	var config := ContainerSpaceConfig.new()
	config.space_type = ContainerSpaceType.ContainerSpaceType.UNORDERED
	config.capacity = cap
	return config


## 创建固定槽位容器配置
static func create_fixed(slot_types: Array[StringName]) -> ContainerSpaceConfig:
	var config := ContainerSpaceConfig.new()
	config.space_type = ContainerSpaceType.ContainerSpaceType.FIXED
	config.fixed_slot_types = slot_types.duplicate()
	return config


## 创建网格容器配置
static func create_grid(width: int, height: int) -> ContainerSpaceConfig:
	var config := ContainerSpaceConfig.new()
	config.space_type = ContainerSpaceType.ContainerSpaceType.GRID
	config.grid_width = width
	config.grid_height = height
	return config


## 转换为字符串表示
func to_string() -> String:
	match space_type:
		ContainerSpaceType.ContainerSpaceType.UNORDERED:
			return "ContainerSpaceConfig(Type=Unordered, Capacity=%d)" % capacity
		ContainerSpaceType.ContainerSpaceType.FIXED:
			return "ContainerSpaceConfig(Type=Fixed, Slots=%d)" % fixed_slot_types.size()
		ContainerSpaceType.ContainerSpaceType.GRID:
			return "ContainerSpaceConfig(Type=Grid, Size=%dx%d)" % [grid_width, grid_height]
		_:
			return "ContainerSpaceConfig(Type=Unknown)"
