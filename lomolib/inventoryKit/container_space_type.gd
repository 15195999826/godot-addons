## InventoryKit - 容器空间类型枚举
##
## 定义容器空间类型的枚举值
class_name ContainerSpaceType
extends RefCounted

## 容器空间类型枚举
enum ContainerSpaceType {
	UNORDERED = 0,  ## 无序容器 - 不关心物品具体位置
	FIXED = 1,      ## 固定槽位容器 - 预定义槽位类型
	GRID = 2        ## 网格容器 - 二维网格布局
}
