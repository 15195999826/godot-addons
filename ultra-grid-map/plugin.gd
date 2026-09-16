@tool
extends EditorPlugin
## Ultra Grid Map 只提供类（GridMapModel / GridMapConfig / HexCoord / 渲染器 / 寻路），不注册任何 autoload：
## 棋盘由持有它的对象自己建、自己持（如 LGF stdlib 的 GridWorldGameplayInstance），没有全局槽位可被后来者钉住。
## u_grid_map.gd 是可选的全局单例脚本，需要时由消费项目自行加进 autoload。
